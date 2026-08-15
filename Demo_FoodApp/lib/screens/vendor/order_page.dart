import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';
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
    loadOrders();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _silentRefresh(),
    );
  }

  Future<void> _silentRefresh() async {
    try {
      final data = await ApiService.getOrders(
        cafeId: AppSession.cafe?["_id"]?.toString(),
        date: _todayIst(),
      );
      if (!mounted) return;
      setState(() => orders = data.map(_mapApiOrder).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadOrders() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      final data = await ApiService.getOrders(
        cafeId: AppSession.cafe?["_id"]?.toString(),
        date: _todayIst(),
      );
      if (!mounted) return;
      setState(() {
        orders = data.map(_mapApiOrder).toList();
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loadError = error.toString().replaceFirst("Exception: ", "");
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

  List<Map<String, dynamic>> get _filteredOrders {
    final statusFilter = _tabStatus[_selectedTab];
    List<Map<String, dynamic>> result;

    if (statusFilter == null) {
      // "All": excludes Completed. Pending at top, Rejected at bottom.
      result = orders.where((o) => o["status"] != 'Completed').toList();
      result.sort((a, b) {
        final aStatus = a["status"] as String;
        final bStatus = b["status"] as String;
        const bottomStatuses = ['Rejected'];
        final aBottom = bottomStatuses.contains(aStatus);
        final bBottom = bottomStatuses.contains(bStatus);
        if (aBottom != bBottom) return aBottom ? 1 : -1;

        // Pending first within non-bottom
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
    } else {
      result = orders.where((o) => o["status"] == statusFilter).toList();
      if (statusFilter == 'Completed') {
        // CODEX EDITS: Completed filter shows newest/highest token first.
        result.sort((a, b) => _tokenValue(b).compareTo(_tokenValue(a)));
        return result;
      }
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
    if (s == null) {
      return orders.where((o) => o["status"] != 'Completed').length;
    }
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
              const SizedBox(width: 8),
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
      return SizedBox(
        width: double.infinity,
        child: _actionBtn(
          "Mark as Ready",
          primaryBlue,
          () => _setOrderStatus(order, "Ready"),
        ),
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
