import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';
import '../../services/keep_alive_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_print_service.dart';
import '../../services/order_speech_service.dart';
import '../../services/session.dart';
import 'vendor_page_wrapper.dart';

class OrdersPage extends StatefulWidget {
  final VoidCallback toggleTheme;
  const OrdersPage({super.key, required this.toggleTheme});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  String? loadError;
  List<Map<String, dynamic>> orders = [];
  Timer? _refreshTimer;
  // Order ids already accounted for, so an announcement plays once per order.
  final Set<String> _seenOrderIds = <String>{};
  // Auto-accept calls currently in flight, so an overlapping poll cannot fire a
  // second accept for an order the first one is still working on.
  final Set<String> _autoAcceptInFlight = <String>{};
  // Orders whose auto-accept call failed. Their cards fall back to manual
  // Accept/Reject rather than sitting under an "Accepting automatically…"
  // notice that will never resolve, while the next poll still retries.
  final Set<String> _autoAcceptFailed = <String>{};

  /// More Pending orders than this arriving in one load means the app was not
  /// running for a while — a reboot, a force-kill, an OEM battery manager.
  /// Accepting and printing that many without asking would burn a roll of
  /// paper, so Auto mode confirms first.
  static const _autoAcceptBurstLimit = 8;
  bool _bulkAcceptDeclined = false;

  // Filter tabs: All, Preparing (Accepted), Preparing, Ready, Completed
  // "Accepted" maps to Preparing status per the spec
  static const _tabs = ['All', 'To Accept', 'Preparing', 'Ready', 'Completed'];
  // Status values that each tab filters by (null = show all)
  static const _tabStatus = [
    null,
    'Pending',
    'Preparing',
    'Ready',
    'Completed',
  ];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    OrderSpeechService.instance.loadPreferences();
    // Holds the process open so orders keep arriving, announcing and printing
    // while nobody is looking at the phone — the whole point of the printer.
    KeepAliveService.instance.start();
    OrderPrintService.instance.loadSettings().then((_) {
      // Tickets that failed while the printer was off get another chance as
      // soon as the page opens.
      OrderPrintService.instance.drainQueue();
    });
    loadOrders();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _silentRefresh(),
    );
    // A vendor push refreshes straight away so the announcement is immediate;
    // the 30s poll above stays as the fallback for a dropped push.
    NotificationService.vendorOrderPushTick.addListener(_onVendorPush);
  }

  void _onVendorPush() {
    if (mounted) _silentRefresh();
  }

  Future<void> _silentRefresh() async {
    try {
      final data = await ApiService.getOrders(
        cafeId: AppSession.cafe?["_id"]?.toString(),
        date: _todayIst(),
      );
      if (!mounted) return;
      final mapped = data.map(_mapApiOrder).toList();
      _announceNewOrders(mapped);
      setState(() => orders = mapped);
      unawaited(_processAutoMode(mapped));
    } catch (_) {}
  }

  // FEATURE: read "One new order, token N" aloud when an order arrives while
  // the vendor is on this page. Only live arrivals are announced — ids already
  // seen are remembered for the lifetime of the page, and the first load seeds
  // that set silently, so reopening the page never replays the backlog.
  void _announceNewOrders(
    List<Map<String, dynamic>> latest, {
    bool announce = true,
  }) {
    for (final order in latest) {
      final id = order["id"]?.toString() ?? '';
      if (id.isEmpty || !_seenOrderIds.add(id)) continue;
      // Only a brand-new order matters; an order that reappears having moved to
      // Preparing or Ready is not news.
      if (!announce || order["status"]?.toString() != 'Pending') continue;
      // orderId is passed so an order already announced from the FCM background
      // isolate is not read out a second time when the app returns and polls.
      OrderSpeechService.instance.announceNewOrder(
        tokenNumber: order["tokenNumber"]?.toString() ?? '',
        orderId: id,
      );
    }
  }

  // FEATURE: Auto mode. The counter works off paper and never touches the
  // phone, so every paid order is accepted and its ticket printed without
  // interaction.
  //
  // Unlike announcements this is not gated on first sight: an accept that
  // failed must be retried on the next poll, and an order left Pending is an
  // order nobody is cooking.
  Future<void> _processAutoMode(List<Map<String, dynamic>> latest) async {
    final printer = OrderPrintService.instance;
    await printer.loadSettings();
    if (!printer.isAutoMode || !mounted) return;

    final pending = latest
        .where((order) => order["status"]?.toString() == 'Pending')
        .where(
          (order) => !printer.isAutoAccepted(order["id"]?.toString() ?? ''),
        )
        .toList();
    if (pending.isEmpty) return;

    if (pending.length > _autoAcceptBurstLimit) {
      if (_bulkAcceptDeclined) return;
      final proceed = await _confirmBulkAccept(pending.length);
      if (!proceed) {
        // Remembered for the session so the 30s poll does not keep asking. The
        // cards fall back to manual Accept/Reject in the meantime.
        _bulkAcceptDeclined = true;
        return;
      }
    }

    for (final order in pending) {
      if (!mounted) return;
      await _autoAccept(order);
    }

    // Anything that failed to reach the printer gets another attempt now that
    // the batch is done.
    unawaited(printer.drainQueue());
  }

  Future<void> _autoAccept(Map<String, dynamic> order) async {
    final id = order["id"]?.toString() ?? '';
    if (id.isEmpty || !_autoAcceptInFlight.add(id)) return;

    try {
      // Accept first, then print. If this call fails nothing is printed and the
      // order stays Pending, so the card falls back to manual buttons. The
      // reverse order would leave a ticket in the kitchen for an order the
      // system still considers unaccepted.
      final updated = await ApiService.updateOrderStatus(id, "Preparing");
      final status = updated["status"]?.toString() ?? "Preparing";
      await OrderPrintService.instance.markAutoAccepted(id);
      _autoAcceptFailed.remove(id);
      // Printed before the mounted check on purpose: the ticket is the
      // kitchen's copy, not a piece of UI. Bailing out here because the vendor
      // navigated away would accept an order and never print it, and nothing
      // would retry since it now counts as auto-accepted.
      await OrderPrintService.instance.printOrder(order);
      if (!mounted) return;
      setState(() => order["status"] = status);
    } catch (error) {
      debugPrint('Auto-accept failed for $id: $error');
      _autoAcceptFailed.add(id);
      if (mounted) setState(() {});
    } finally {
      _autoAcceptInFlight.remove(id);
    }
  }

  Future<bool> _confirmBulkAccept(int count) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Orders waiting'),
        content: Text(
          '$count orders came in while the app was not running. '
          'Accept and print all of them now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept & print all'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    NotificationService.vendorOrderPushTick.removeListener(_onVendorPush);
    // Leaving the page must silence the readout — the platform engine keeps
    // talking after the widget is gone otherwise.
    OrderSpeechService.instance.stop();
    super.dispose();
  }

  Future<void> loadOrders() async {
    // Only blank the page when there is nothing on it yet. Re-showing the
    // full-screen spinner on every refresh is what made an Accept / Mark Ready
    // tap flash the whole page, filter tabs and all, before the list returned.
    // With cards already on screen the refresh happens in place instead.
    final firstLoad = orders.isEmpty;
    setState(() {
      isLoading = firstLoad;
      loadError = null;
    });
    try {
      final data = await ApiService.getOrders(
        cafeId: AppSession.cafe?["_id"]?.toString(),
        date: _todayIst(),
      );
      if (!mounted) return;
      final mapped = data.map(_mapApiOrder).toList();
      // First load only seeds the baseline — the vendor should not be read the
      // whole day's backlog on opening the page. Every later refresh announces,
      // so an order landing during a manual refresh is not silently swallowed.
      _announceNewOrders(mapped, announce: !firstLoad);
      setState(() {
        orders = mapped;
        isLoading = false;
      });
      unawaited(_processAutoMode(mapped));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // A failed refresh must not wipe orders already on screen — the vendor
        // keeps working from the last good list rather than losing it to an
        // error page over one dropped request.
        if (orders.isEmpty) {
          loadError = error.toString().replaceFirst("Exception: ", "");
        }
        isLoading = false;
      });
    }
  }

  Map<String, dynamic> _mapApiOrder(Map<String, dynamic> order) {
    return {
      "id": order["orderId"],
      "tokenNumber": order["tokenNumber"] ?? "",
      "customer": order["customerName"] ?? "Customer",
      "status": order["status"] ?? "Pending",
      "total": order["total"] ?? 0,
      "items": order["items"] ?? [],
      "location": order["location"] ?? "Pickup counter",
      "pickupTime": order["pickupTime"] ?? "",
      // CODEX EDITS: Keep order creation time available for the compact
      // timestamp shown under the pickup location.
      "createdAt": order["createdAt"] ?? "",
      "cafeteriaName": order["cafeteriaName"] ?? "Cafeteria",
    };
  }

  String _todayIst() {
    final ist = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return '${ist.year.toString().padLeft(4, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.day.toString().padLeft(2, '0')}';
  }

  /// Parse the pickupTime ISO string for sorting. Null-safe: empty string sorts last.
  DateTime? _parsePickup(String t) => t.isEmpty ? null : DateTime.tryParse(t);

  int _tokenValue(Map<String, dynamic> order) =>
      int.tryParse(order["tokenNumber"]?.toString() ?? '') ?? -1;

  // CODEX EDITS: Tiny local ordering time for vendor order cards.
  String _formatOrderTime(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  /// Statuses that are finished business. A rejected order needs no further
  /// action from the counter, so it belongs in the Completed tab alongside the
  /// picked-up ones rather than sitting at the bottom of the live list.
  static const _archivedStatuses = {'Completed', 'Rejected'};

  bool _isArchived(Map<String, dynamic> order) =>
      _archivedStatuses.contains(order["status"]);

  List<Map<String, dynamic>> get _filteredOrders {
    final statusFilter = _tabStatus[_selectedTab];
    List<Map<String, dynamic>> result;

    if (statusFilter == null) {
      // "All": the live queue only — Completed and Rejected are archived.
      // Pending at top.
      result = orders.where((o) => !_isArchived(o)).toList();
      result.sort((a, b) {
        final aStatus = a["status"] as String;
        final bStatus = b["status"] as String;

        // Pending first
        final aPending = aStatus == 'Pending';
        final bPending = bStatus == 'Pending';
        if (aPending != bPending) return aPending ? -1 : 1;

        // Within same priority group: sort by pickup time ascending
        final aTime = _parsePickup(a["pickupTime"] as String);
        final bTime = _parsePickup(b["pickupTime"] as String);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
    } else if (statusFilter == 'Completed') {
      // Completed tab holds both Completed and Rejected, in token sequence
      // with the highest first so the most recent order heads the list. An
      // order with no numeric token scores -1 and lands at the bottom.
      result = orders.where(_isArchived).toList();
      result.sort((a, b) => _tokenValue(b).compareTo(_tokenValue(a)));
      return result;
    } else {
      result = orders.where((o) => o["status"] == statusFilter).toList();
      // Sort by pickup time ascending within the tab
      result.sort((a, b) {
        final aTime = _parsePickup(a["pickupTime"] as String);
        final bTime = _parsePickup(b["pickupTime"] as String);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
    }
    return result;
  }

  int _countForTab(int tabIndex) {
    final s = _tabStatus[tabIndex];
    // Both badges follow the same archive rule as _filteredOrders, so a
    // rejected order is counted on Completed and nowhere else.
    if (s == null) return orders.where((o) => !_isArchived(o)).length;
    if (s == 'Completed') return orders.where(_isArchived).length;
    return orders.where((o) => o["status"] == s).length;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return VendorPageWrapper(
      pageTitle: "Order Management",
      selectedMenuIndex: 1,
      toggleTheme: widget.toggleTheme,
      trailingActions: [
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: primaryBlue),
          tooltip: 'Refresh orders',
          onPressed: loadOrders,
        ),
      ],
      child: Scaffold(
        backgroundColor: bgColor,
        body: RefreshIndicator(
          onRefresh: loadOrders,
          child: _buildBody(cardColor, textColor, subText, isDark),
        ),
      ),
    );
  }

  Widget _buildBody(
    Color cardColor,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: primaryBlue));
    }

    if (loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            "Could not load orders",
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(loadError!, style: TextStyle(color: subText)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: loadOrders, child: const Text("Retry")),
        ],
      );
    }

    final visible = _filteredOrders;

    return Column(
      children: [
        // ── Filter tabs ──────────────────────────────────────────────────────
        Container(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final count = _countForTab(i);
                final selected = _selectedTab == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? primaryBlue
                              : (isDark
                                    ? Colors.white10
                                    : const Color(0xFFF4F6F9)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _tabs[i],
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: selected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : textColor),
                              ),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.3)
                                      : primaryBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        // ── Failed prints ────────────────────────────────────────────────────
        // A ticket that never printed means an order nobody is cooking, so it
        // must never fail silently.
        ValueListenableBuilder<int>(
          valueListenable: OrderPrintService.instance.failedCount,
          builder: (context, failed, _) {
            if (failed == 0) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.print_disabled_rounded,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      failed == 1
                          ? '1 ticket did not print'
                          : '$failed tickets did not print',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => OrderPrintService.instance.drainQueue(
                      resetAttempts: true,
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // ── Order list ───────────────────────────────────────────────────────
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 64,
                        color: subText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No orders here",
                        style: TextStyle(
                          color: subText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    return buildOrderCard(
                          visible[index],
                          cardColor,
                          textColor,
                          subText,
                          isDark,
                        )
                        .animate()
                        .fade(delay: (60 * index).ms)
                        .slideY(
                          begin: 0.15,
                          end: 0,
                          curve: Curves.easeOutCubic,
                        );
                  },
                ),
        ),
      ],
    );
  }

  // FEATURE: read the order aloud ("2 Veg Biryani, 1 Coke, for Arjun") so the
  // counter can work without reading the screen. Listens to the shared service
  // so the icon shows "stop" only on the card that is actually talking, and
  // reverts on every card when playback ends.
  Widget _readAloudButton(Map<String, dynamic> order) {
    final orderId = order["id"]?.toString() ?? '';
    return ValueListenableBuilder<String?>(
      valueListenable: OrderSpeechService.instance.speakingOrderId,
      builder: (context, speakingId, _) {
        final isSpeaking = speakingId == orderId && orderId.isNotEmpty;
        return Tooltip(
          message: isSpeaking ? 'Stop reading' : 'Read order aloud',
          child: IconButton(
            onPressed: () => OrderSpeechService.instance.toggle(order),
            icon: Icon(
              isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
              size: 24,
              color: primaryBlue,
            ),
            splashRadius: 22,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
          ),
        );
      },
    );
  }

  // Paper runs out, jams, and gets thrown away mid-shift. Every card can put
  // its ticket through again on demand, bypassing the once-per-order dedup.
  Widget _reprintButton(Map<String, dynamic> order) {
    return Tooltip(
      message: 'Print ticket again',
      child: IconButton(
        onPressed: () => _reprint(order),
        icon: Icon(Icons.print_rounded, size: 22, color: primaryBlue),
        splashRadius: 22,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _reprint(Map<String, dynamic> order) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await OrderPrintService.instance.printOrder(order, force: true);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ticket sent to the printer'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // A reprint is a deliberate action, so its failure is reported rather
      // than quietly queued the way an automatic print is.
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget buildOrderCard(
    Map<String, dynamic> order,
    Color cardColor,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    final pickupRaw = order["pickupTime"] as String? ?? '';
    final pickupDt = _parsePickup(pickupRaw);
    String pickupLabel = '';
    if (pickupDt != null) {
      final h = pickupDt.hour % 12 == 0 ? 12 : pickupDt.hour % 12;
      final m = pickupDt.minute.toString().padLeft(2, '0');
      final p = pickupDt.hour < 12 ? 'AM' : 'PM';
      pickupLabel = '$h:$m $p';
    }
    final orderTime = _formatOrderTime(order["createdAt"]?.toString() ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((order["tokenNumber"] as String? ?? '').isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: primaryBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'TOKEN #${order["tokenNumber"]}',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    Text(
                      "Order #${order["id"]}",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _readAloudButton(order),
              if (OrderPrintService.instance.isReady) _reprintButton(order),
              const SizedBox(width: 4),
              statusChip(order["status"]),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Customer: ${order["customer"]}",
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              color: subText,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (pickupLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 15, color: primaryBlue),
                const SizedBox(width: 5),
                Text(
                  "Pickup by $pickupLabel",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primaryBlue,
                  ),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              thickness: 1.5,
            ),
          ),
          ...order["items"].map<Widget>(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${item["name"]}  x${item["qty"]}",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    "₹${item["price"]}",
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 16,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order["location"],
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: subText,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (orderTime.isNotEmpty) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                'Ordered at $orderTime',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: subText.withValues(alpha: 0.72),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          buildButtons(order),
        ],
      ),
    );
  }

  Widget buildButtons(Map<String, dynamic> order) {
    final status = order["status"] as String;
    final id = order["id"]?.toString() ?? '';
    final printer = OrderPrintService.instance;
    final autoAccepted = printer.isAutoAccepted(id);

    // Auto mode, accept still under way: the buttons are replaced by a note so
    // nobody taps Accept on an order the app is already accepting. An accept
    // that failed drops out of this branch so its card gets real buttons back.
    if (printer.isAutoMode &&
        status == "Pending" &&
        !autoAccepted &&
        !_autoAcceptFailed.contains(id)) {
      return _autoAcceptedBar("Accepting automatically…");
    }

    final action = _primaryAction(order, status, autoAccepted);
    if (!autoAccepted) return action;

    // The marker persists for the life of the order, so the vendor can always
    // tell which ones were handled without them. It only claims a ticket was
    // printed when a printer is actually set up — Auto mode still accepts
    // hands-free with no printer attached.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _autoAcceptedBar(
          printer.isReady ? "Auto-accepted & printed" : "Auto-accepted",
        ),
        const SizedBox(height: 12),
        action,
      ],
    );
  }

  Widget _autoAcceptedBar(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.amber.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryAction(
    Map<String, dynamic> order,
    String status,
    bool autoAccepted,
  ) {
    if (status == "Pending") {
      return Row(
        children: [
          Expanded(
            child: _actionBtn(
              "Accept",
              Colors.green,
              () => _setOrderStatus(order, "Preparing"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _actionBtn(
              "Reject",
              Colors.redAccent,
              () => _setOrderStatus(order, "Rejected"),
            ),
          ),
        ],
      );
    }
    if (status == "Preparing") {
      final ready = _actionBtn(
        "Mark as Ready",
        primaryBlue,
        () => _setOrderStatus(order, "Ready"),
      );
      if (!autoAccepted) {
        return SizedBox(width: double.infinity, child: ready);
      }
      // Auto mode takes away the vendor's chance to refuse an order up front,
      // so Reject stays reachable until it is handed over. Without this an
      // order the kitchen cannot fulfil has no in-app resolution at all.
      return Row(
        children: [
          Expanded(flex: 2, child: ready),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _setOrderStatus(order, "Rejected"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "Reject",
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (status == "Ready") {
      return SizedBox(
        width: double.infinity,
        child: _actionBtn(
          "Mark as Picked Up",
          Colors.teal,
          () => _setOrderStatus(order, "Completed"),
        ),
      );
    }
    if (status == "Completed") {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            "Order Completed",
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }

  Widget _actionBtn(String text, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  Future<void> _setOrderStatus(
    Map<String, dynamic> order,
    String status,
  ) async {
    final prev = order["status"];
    setState(() => order["status"] = status);
    try {
      final updated = await ApiService.updateOrderStatus(order["id"], status);
      order["status"] = updated["status"] ?? status;
      // Manual mode prints on Accept rather than on arrival, so a rejected
      // order never produces a ticket. Auto mode has already printed by the
      // time it gets here, and printOrder dedupes by order id, so this is safe
      // in both modes without a mode check.
      if (order["status"] == "Preparing") {
        unawaited(OrderPrintService.instance.printOrder(order));
      }
      await loadOrders();
    } catch (error) {
      if (!mounted) return;
      setState(() => order["status"] = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst("Exception: ", "")),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget statusChip(String status) {
    final colors = {
      'Pending': Colors.orange,
      'Preparing': Colors.lightBlue,
      'Ready': Colors.tealAccent,
      'Rejected': Colors.red,
      'Completed': Colors.greenAccent,
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
