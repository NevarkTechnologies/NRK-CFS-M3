import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../model/cart_model.dart';
import '../services/notification_service.dart';
import 'cafeteria_page.dart';
import 'cart_page.dart';

class SuccessPage extends StatefulWidget {
  final Map<String, dynamic> order;
  const SuccessPage({super.key, required this.order});

  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int step = 0;
  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;
  static const _primaryBlue = Color(0xFF0F4CFF);

  // True once the "Order Placed" FCM push for THIS order has arrived (or the
  // fallback timeout fired) — drives the "Order is being created" footer.
  bool _orderPushReceived = false;
  Timer? _pushFallbackTimer;

  // How long the footer waits for the order-created push before releasing on
  // its own, and when this page was mounted — the pair lets a resumed tab work
  // out what should already have happened (see _catchUpDelayedMilestones).
  static const _pushFallbackDelay = Duration(seconds: 10);
  static const _successAnimationDelay = Duration(seconds: 4);
  final DateTime _mountedAt = DateTime.now();
  // FIX 2026-07-21: The confirmation popup is now driven by the same signal as
  // the footer loader (order-created push / fallback) instead of a blind 4s
  // timer, so the loader stays visible right up until the popup appears.
  // _successAnimationDone gates it behind the "Payment Successful!" step; both
  // conditions met → popup shown exactly once.
  bool _successAnimationDone = false;
  bool _popupShown = false;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  void _onOrderPush() {
    if (_orderPushReceived) return;
    final pushedId = NotificationService.lastOrderPushOrderId.value;
    if (pushedId != null && pushedId == widget.order['orderId']?.toString()) {
      if (mounted) setState(() => _orderPushReceived = true);
      _maybeShowConfirmationPopup();
    }
  }

  // FIX 2026-07-21: Shows the "Order Confirmed!" popup once, only after both the
  // success animation has played AND the order-created signal has arrived (real
  // FCM push or the 60s fallback). Replaces the previous fixed 4s timer that
  // fired the popup independently of actual order creation.
  void _maybeShowConfirmationPopup() {
    // WEB FIX: the footer-loader/popup signals here are flipped by FCM callbacks
    // and Timers, not by user input. When the tab was backgrounded during the
    // payment redirect the browser drops the requestAnimationFrame that
    // setState scheduled, and the engine's stuck _hasScheduledFrame guard makes
    // later scheduleFrame() calls no-ops — so the dirty tree never repaints and
    // the post-frame callback below never fires until an unrelated tab switch.
    // scheduleForcedFrame() bypasses that guard and forces a real frame, so the
    // footer stops spinning and the popup appears without needing a tab switch.
    // Android renders on a vsync ticker and never hit this, so keep it web-only.
    if (kIsWeb) WidgetsBinding.instance.scheduleForcedFrame();
    if (_popupShown || !_successAnimationDone || !_orderPushReceived) return;
    if (!mounted) return;
    _popupShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _OrderConfirmedDialog(isDark: isDark),
      ).then((_) {
        if (!mounted) return;
        setState(() => step = 2);
      });
    });
  }

  // WEB FIX: every milestone on this page is driven by a Timer, and Dart's
  // Timer compiles to setTimeout on web. Chrome throttles setTimeout in hidden
  // tabs (and stops the frame pump entirely), so when the Paytm redirect brings
  // the app back while the user is still looking at another tab, this page
  // mounts in the background and its timers simply do not run — the footer was
  // still spinning long after the 10s fallback should have released it.
  //
  // On resume, work out from wall-clock time what should already have happened
  // and apply it immediately instead of waiting for the throttled timers to
  // catch up. Wall clock is unaffected by throttling; the Timers stay in place
  // for the normal foreground case.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _catchUpDelayedMilestones();
  }

  void _catchUpDelayedMilestones() {
    if (!mounted) return;
    final elapsed = DateTime.now().difference(_mountedAt);

    if (elapsed >= _successAnimationDelay && !_successAnimationDone) {
      setState(() {
        step = 1;
        _successAnimationDone = true;
      });
      _checkCtrl.forward();
    }
    if (elapsed >= _pushFallbackDelay && !_orderPushReceived) {
      setState(() => _orderPushReceived = true);
    }
    _maybeShowConfirmationPopup();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _checkScale = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);

    NotificationService.lastOrderPushOrderId.addListener(_onOrderPush);
    // The push may have arrived before this page mounted (webhook path sends
    // it as soon as the payment is captured) — check the retained value now.
    _onOrderPush();
    // FCM delivery has no latency guarantee (Doze, OEM battery savers, campus
    // Wi-Fi NAT timeouts) — don't spin forever if it's very late or the app
    // was briefly backgrounded and the foreground listener missed it.
    // FIX: 60s was far too long as a visible wait. The order is already created
    // and returned by confirmOrder before this page is pushed — widget.order is
    // proof of it — so the push is only corroboration, never the source of
    // truth. The server drains its notification outbox on a 5s tick, so a
    // healthy push lands well inside 10s and the popup still waits for it;
    // anything slower now releases the loader instead of stranding the user.
    _pushFallbackTimer = Timer(_pushFallbackDelay, () {
      if (mounted && !_orderPushReceived) {
        setState(() => _orderPushReceived = true);
        // FIX 2026-07-21: fallback must also release the popup so it can never
        // hang waiting for a push that was dropped.
        _maybeShowConfirmationPopup();
      }
    });

    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => step = 1);
      _checkCtrl.forward();
      // FIX 2026-07-21: After the success animation plays, arm the popup —
      // it now appears only once the order-created signal has also arrived
      // (see _maybeShowConfirmationPopup), keeping the loader visible until
      // the popup shows. If the push already landed, this shows it right away.
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        // FIX 2026-07-21: setState (not a bare assignment) so a frame is
        // scheduled. _maybeShowConfirmationPopup shows the dialog via
        // addPostFrameCallback, which only runs after a rendered frame — when
        // the push already arrived the scheduler is otherwise idle, so the
        // popup would hang until an unrelated repaint (screen touch, pulling
        // down the notification shade). Marking the tree dirty flushes it.
        setState(() => _successAnimationDone = true);
        _maybeShowConfirmationPopup();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.lastOrderPushOrderId.removeListener(_onOrderPush);
    _pushFallbackTimer?.cancel();
    _checkCtrl.dispose();
    super.dispose();
  }

  void _goToHome() {
    for (final item in globalCartItems) {
      final qty = item["qty"] as int;
      for (int i = 0; i < qty; i++) { CartModel.remove(item["id"]); }
    }
    globalCartItems.clear();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => CafeteriaPage(toggleTheme: () {})),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subText = isDark ? Colors.white60 : const Color(0xFF6B7280);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _goToHome(); },
      child: Scaffold(
        backgroundColor: bg,
        appBar: step == 2 ? _appBar(cardColor) : null,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child)),
              child: _buildUI(cardColor, textColor, subText),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 14),
            child: _orderCreationFooter(subText),
          ),
        ),
      ),
    );
  }

  /// One-liner at the bottom: "Order is being created" + small loader until
  /// the "Order Placed" FCM push for this order arrives, then a green check.
  Widget _orderCreationFooter(Color subText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _orderPushReceived
          ? [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 15),
              const SizedBox(width: 6),
              const Text(
                'Order created',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF22C55E),
                ),
              ),
            ]
          : [
              Text(
                'Order is being created',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: subText),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(color: _primaryBlue, strokeWidth: 2),
              ),
            ],
    );
  }

  PreferredSizeWidget _appBar(Color cardColor) {
    return AppBar(
      backgroundColor: cardColor,
      elevation: 0,
      iconTheme: const IconThemeData(color: _primaryBlue),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goToHome),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (widget.order["tokenNumber"]?.toString() ?? '').isNotEmpty
              ? 'Token #${widget.order["tokenNumber"]}  •  Order #${widget.order["orderId"] ?? ""}'
              : 'Order #${widget.order["orderId"] ?? ""}',
            style: const TextStyle(color: _primaryBlue, fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 14)),
          Text(widget.order["cafeteriaName"]?.toString() ?? "Cafeteria", style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Inter')),
        ],
      ),
    );
  }

  Widget _buildUI(Color cardColor, Color textColor, Color subText) {
    if (step == 0) return _processingUI(cardColor);
    if (step == 1) return _successUI(cardColor, textColor);
    return _orderPageUI(cardColor, textColor, subText);
  }

  Widget _processingUI(Color cardColor) {
    return Center(
      key: const ValueKey("processing"),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(22),
                child: CircularProgressIndicator(color: _primaryBlue, strokeWidth: 3),
              ),
            ),
            const SizedBox(height: 28),
            const Text('Processing Payment', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 22, color: _primaryBlue)),
            const SizedBox(height: 8),
            Text('Please wait while we confirm your payment...', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: isDark ? Colors.white54 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _successUI(Color cardColor, Color textColor) {
    return Center(
      key: const ValueKey("success"),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF16A34A)]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
              ),
            ),
            const SizedBox(height: 28),
            const Text('Payment Successful!', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF22C55E))),
            const SizedBox(height: 10),
            Text('Your order has been confirmed and\nthe vendor is being notified.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: isDark ? Colors.white54 : Colors.grey.shade600, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _orderPageUI(Color cardColor, Color textColor, Color subText) {
    final items = widget.order["items"] as List<dynamic>? ?? [];
    final status = widget.order["status"]?.toString() ?? "Pending";
    final pickupRaw = widget.order["pickupTime"]?.toString() ?? "";
    final pickupDt = DateTime.tryParse(pickupRaw);
    String pickupLabel = '';
    if (pickupDt != null) {
      final h = pickupDt.hour % 12 == 0 ? 12 : pickupDt.hour % 12;
      final m = pickupDt.minute.toString().padLeft(2, '0');
      final p = pickupDt.hour < 12 ? 'AM' : 'PM';
      pickupLabel = '$h:$m $p';
    }

    return ListView(
      key: const ValueKey("order"),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        // Status hero
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0F4CFF), Color(0xFF3B6FFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: _primaryBlue.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Order Confirmed', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Order #${widget.order["orderId"] ?? ""} • ${_statusLabel(status)}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                    if ((widget.order["tokenNumber"]?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: Text('TOKEN #${widget.order["tokenNumber"]}',
                          style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: 1.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Progress card
        _card(cardColor, Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Order Progress', textColor),
            _progressRow('Payment Confirmed', true, textColor, isFirst: true),
            _progressRow('Vendor Preparing', status == 'Preparing' || status == 'Ready' || status == 'Completed', textColor),
            _progressRow('Ready to Pickup', status == 'Ready' || status == 'Completed', textColor, isLast: true),
          ],
        )),
        const SizedBox(height: 16),
        // Pickup info
        if (pickupLabel.isNotEmpty)
          _card(cardColor, Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.access_time_rounded, color: _primaryBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pickup By', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: subText)),
                  Text(pickupLabel, style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: _primaryBlue)),
                ],
              ),
            ],
          )),
        if (pickupLabel.isNotEmpty) const SizedBox(height: 16),
        // Items card
        _card(cardColor, Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('${items.length} Item${items.length == 1 ? "" : "s"}', textColor),
            ...items.map((item) {
              final m = item as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(child: Text('${m["name"] ?? "Item"}', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor))),
                    Text('x${m["qty"] ?? 1}', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: subText)),
                    const SizedBox(width: 16),
                    Text('₹${m["price"] ?? 0}', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 14, color: textColor)),
                  ],
                ),
              );
            }),
            Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Item Total', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 15, color: textColor)),
                Text('₹${widget.order["itemTotal"] ?? widget.order["total"] ?? "—"}',
                  style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: _primaryBlue)),
              ],
            ),
          ],
        )),
        const SizedBox(height: 16),
        // Pickup location card
        _card(cardColor, Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(widget.order["location"]?.toString() ?? "Pickup counter",
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor)),
            ),
          ],
        )),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: _goToHome,
            child: const Text('Back to Home', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    const map = {'Pending': 'Awaiting Vendor', 'Preparing': 'Being Prepared', 'Ready': 'Ready for Pickup', 'Completed': 'Completed'};
    return map[status] ?? status;
  }

  Widget _card(Color cardColor, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String t, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(t, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 15, color: c)),
    );
  }

  Widget _progressRow(String label, bool done, Color textColor, {bool isFirst = false, bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          if (!isFirst) Container(width: 2, height: 16, color: done ? _primaryBlue.withValues(alpha: 0.3) : Colors.grey.shade300),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _primaryBlue : Colors.transparent,
              border: Border.all(color: done ? _primaryBlue : Colors.grey.shade400, width: 2),
            ),
            child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
          if (!isLast) Container(width: 2, height: 32, color: done ? _primaryBlue.withValues(alpha: 0.3) : Colors.grey.shade300),
        ]),
        const SizedBox(width: 14),
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 4 : 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
            Text(done ? 'Completed' : 'Pending', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: done ? _primaryBlue : Colors.grey)),
          ]),
        ),
      ],
    );
  }
}

class _OrderConfirmedDialog extends StatelessWidget {
  final bool isDark;
  const _OrderConfirmedDialog({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F4CFF).withValues(alpha: 0.15),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF0F4CFF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF0F4CFF),
                size: 52,
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 500.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 24),
            Text(
              'Order Confirmed!',
              style: TextStyle(
                fontSize: 24,
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            )
                .animate()
                .fadeIn(delay: 200.ms, duration: 300.ms)
                .slideY(begin: 0.3, end: 0, delay: 200.ms, duration: 300.ms),
            const SizedBox(height: 12),
            Text(
              'Your order is placed. Check notifications for pickup updates.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            )
                .animate()
                .fadeIn(delay: 350.ms, duration: 300.ms),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F4CFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'View Order Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 500.ms, duration: 300.ms)
                .slideY(begin: 0.2, end: 0, delay: 500.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
