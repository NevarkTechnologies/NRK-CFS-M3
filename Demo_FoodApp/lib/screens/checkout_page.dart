import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'success_page.dart';
import 'detail_page.dart';
import 'cart_page.dart';
import '../model/cart_model.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../services/razorpay_helper.dart';
import '../services/paytm_helper.dart';
import '../services/fee_service.dart';
// CODEX EDITS: Durable payment recovery across UPI redirects and process death.
import '../services/pending_payment_service.dart';

class CheckoutPage extends StatefulWidget {
  final List<OrderItem>? items;
  final String? cafeteriaName;
  final String? cafeId;
  final String? pickupLocation;
  final bool isReorder;
  const CheckoutPage({
    super.key,
    this.items,
    this.cafeteriaName,
    this.cafeId,
    this.pickupLocation,
    this.isReorder = false,
  });
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

// CODEX EDITS: Observe app resume so returning from a UPI app always reconciles
// against Razorpay through the backend, even if the SDK callback is lost.
class _CheckoutPageState extends State<CheckoutPage>
    with WidgetsBindingObserver {
  final Color primaryColor = const Color(0xFF0F4CFF);

  // Selected payment gateway — Paytm is the preferred option and auto-selected.
  String selectedGateway = 'paytm';
  bool isSubmitting = false;
  TimeOfDay? _pickupTime;

  // No _currentOrder field — the DB order is only created after payment succeeds.
  Map<String, dynamic>? _razorpayOrder;
  String? _razorpayKeyId; // Received from server — never hardcoded client-side
  // Paytm checkout payload from the server (orderId, txnToken, mid, ...).
  Map<String, dynamic>? _paytmOrder;

  // True from the moment Razorpay checkout opens until a terminal outcome:
  // SuccessPage navigation, payment failure, or recovery giving up. Drives the
  // full-screen loader shown when the user returns from an external UPI app.
  bool _awaitingPayment = false;
  // CODEX EDITS: Guards prevent lifecycle, webhook recovery, and SDK callbacks
  // from navigating twice or issuing overlapping reconciliation requests.
  bool _isReconcilingPayment = false;
  bool _paymentTerminalHandled = false;
  Timer? _resumeReconcileTimer;

  void _setAwaitingPayment(bool value) {
    if (mounted && _awaitingPayment != value) {
      setState(() => _awaitingPayment = value);
    }
  }

  String get _pickupTimeLabel {
    if (_pickupTime == null) return 'Set Pickup Time';
    final h = _pickupTime!.hourOfPeriod == 0 ? 12 : _pickupTime!.hourOfPeriod;
    final m = _pickupTime!.minute.toString().padLeft(2, '0');
    final period = _pickupTime!.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  /// ISO-8601 string for today's date + chosen time, sent to backend.
  String get _pickupTimeISO {
    if (_pickupTime == null) return '';
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      _pickupTime!.hour,
      _pickupTime!.minute,
    ).toIso8601String();
  }

  // Pickup must fall inside a same-day window served by the backend (MongoDB
  // app_configs 'pickup_window', fetched with the fees on checkout open;
  // defaults 11:00 AM – 1:30 PM). The original clock dial picker is kept —
  // the window is enforced on the picked value here and again server-side at
  // payment initiation.
  int get _pickupStartMinutes => FeeService.pickupStartMinutes;
  int get _pickupEndMinutes => FeeService.pickupEndMinutes;

  Future<void> _selectPickupTime() async {
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    if (nowMinutes >= _pickupEndMinutes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pickup is available between ${FeeService.pickupStartLabel} and ${FeeService.pickupEndLabel}. Today\'s window has closed.',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Original 15-minute-rounded suggestion, clamped into the pickup window so
    // the dial opens on a selectable time.
    int suggestedMinutes = now.hour * 60 + ((now.minute ~/ 15 + 1) * 15);
    if (suggestedMinutes < _pickupStartMinutes) {
      suggestedMinutes = _pickupStartMinutes;
    }
    if (suggestedMinutes > _pickupEndMinutes) {
      suggestedMinutes = _pickupEndMinutes;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime:
          _pickupTime ??
          TimeOfDay(
            hour: (suggestedMinutes ~/ 60) % 24,
            minute: suggestedMinutes % 60,
          ),
      helpText: 'SELECT PICKUP TIME',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: const Color(0xFF0F4CFF),
                  brightness: Theme.of(context).brightness,
                ).copyWith(
                  primary: const Color(0xFF0F4CFF),
                  onPrimary: Colors.white,
                  surface: isDark ? const Color(0xFF0F172A) : Colors.white,
                  onSurface: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              dialBackgroundColor: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFE8F0FF),
              dialHandColor: const Color(0xFF0F4CFF),
              dialTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : isDark
                    ? Colors.white70
                    : const Color(0xFF0F172A),
              ),
              hourMinuteColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF0F4CFF)
                    : isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE8F0FF),
              ),
              hourMinuteTextColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : isDark
                    ? Colors.white70
                    : const Color(0xFF0F172A),
              ),
              entryModeIconColor: const Color(0xFF0F4CFF),
              helpTextStyle: const TextStyle(
                color: Color(0xFF0F4CFF),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
      },
    );
    if (picked == null) return;
    // Reject times in the past (same-day only comparison).
    final pickedMinutes = picked.hour * 60 + picked.minute;
    if (pickedMinutes <= nowMinutes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pickup Time Must Be Today and Later Than Current Time.',
            ),
            backgroundColor: Colors.redAccent,
            duration: Duration(milliseconds: 1000),
          ),
        );
      }
      return;
    }
    // Enforce the configured pickup window on the picked value.
    if (pickedMinutes < _pickupStartMinutes ||
        pickedMinutes > _pickupEndMinutes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pickup Time Must Be Between ${FeeService.pickupStartLabel} and ${FeeService.pickupEndLabel}.',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _pickupTime = picked);
  }

  double get _itemTotal {
    if (widget.isReorder && widget.items != null) {
      return widget.items!.fold(0.0, (s, i) => s + i.price * i.quantity);
    }
    return globalCartItems.fold(
      0.0,
      (s, i) => s + (i["price"] as num) * (i["qty"] as int),
    );
  }

  // Fees are DB-driven per gateway (fee_configs collection) and re-fetched on
  // every checkout open, so direct MongoDB edits reflect here in real time.
  GatewayFees get _fees => FeeService.feesFor(selectedGateway);
  double get _platformFee => _fees.platformFeeFor(_itemTotal);
  double get _convenienceFee => _fees.convenienceFee;
  double get _grandTotal => _itemTotal + _platformFee + _convenienceFee;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    // CODEX EDITS: Wallet selection has its own non-failure callback.
    initRazorpay(
      _handleRazorpaySuccess,
      _handleRazorpayError,
      onExternalWallet: _handleExternalWallet,
    );
    initPaytm(_handlePaytmResult, _handlePaytmError);
    _loadFees();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // CODEX EDITS: Reconcile when Checkout is reopened after process death.
      _restorePendingPayment();
    });
  }

  Future<void> _loadFees() async {
    await FeeService.refresh(force: true);
    if (!mounted) return;
    setState(() {
      // If the selected gateway was disabled in the DB, fall back to the
      // first active one so the user can still pay.
      final active = FeeService.activeGateways.map((g) => g.gateway).toList();
      if (active.isNotEmpty && !active.contains(selectedGateway)) {
        selectedGateway = active.first;
      }
    });
  }

  @override
  void dispose() {
    // CODEX EDITS: Release lifecycle/debounce resources before SDK callbacks.
    WidgetsBinding.instance.removeObserver(this);
    _resumeReconcileTimer?.cancel();
    disposeRazorpay();
    disposePaytm();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_awaitingPayment ||
        _paymentTerminalHandled) {
      return;
    }
    // CODEX EDITS: Let the Razorpay plugin deliver its native result first;
    // reconciliation then covers missing/late callbacks without racing it.
    _resumeReconcileTimer?.cancel();
    _resumeReconcileTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_paymentTerminalHandled) {
        _reconcilePendingPayment(pollAttempts: 3, showPendingMessage: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final background = isDark
        ? const Color(0xFF020617)
        : const Color(0xFFF4F6F9);

    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;

    final textColor = isDark ? Colors.white : Colors.black;

    return PopScope(
      // Block back navigation while a payment is being finalized — popping the
      // page here would orphan the SuccessPage navigation.
      canPop: !_awaitingPayment,
      child: Stack(
        children: [
          _buildScaffold(background, cardColor, textColor),
          if (_awaitingPayment) _paymentLoaderOverlay(cardColor, textColor),
        ],
      ),
    );
  }

  /// Full-screen barrier shown from checkout open until SuccessPage or a
  /// terminal failure — covers the bare checkout page seen after returning
  /// from an external UPI app while the payment is still being verified.
  Widget _paymentLoaderOverlay(Color cardColor, Color textColor) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 18),
                  Text(
                    'Completing your payment…',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please don\'t close the app',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScaffold(Color background, Color cardColor, Color textColor) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text("Checkout"),
        backgroundColor: cardColor,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: primaryColor),
        titleTextStyle: TextStyle(
          color: primaryColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  if (widget.isReorder && widget.items != null) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 20,
                        left: 20,
                        right: 20,
                        bottom: 60,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFE8F0FF),
                        image: DecorationImage(
                          image: const AssetImage('assets/bg.jpg'),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            isDark
                                ? const Color(0xFF0F172A).withValues(alpha: 0.9)
                                : const Color(
                                    0xFFF0F6FF,
                                  ).withValues(alpha: 0.85),
                            BlendMode.srcATop,
                          ),
                        ),
                      ),
                    ),
                  ],
                  _orderSummaryCard(cardColor, textColor),
                  _pickupTimeCard(cardColor, textColor),
                  _paymentMethodCard(cardColor, textColor),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: (isSubmitting || _pickupTime == null)
                        ? null
                        : _handlePayment,
                    child: Text(
                      isSubmitting
                          ? "Placing Order..."
                          : _pickupTime == null
                          ? "Set Pickup Time to Continue"
                          : "Pay  ₹${_grandTotal.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickupTimeCard(Color cardColor, Color textColor) {
    final bool set = _pickupTime != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: set
              ? primaryColor.withValues(alpha: 0.5)
              : Colors.redAccent.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black54
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _selectPickupTime,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (set ? primaryColor : Colors.redAccent).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    color: set ? primaryColor : Colors.redAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pickup Time',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        set
                            ? _pickupTimeLabel
                            : 'Required · ${FeeService.pickupStartLabel} – ${FeeService.pickupEndLabel}',
                        style: TextStyle(
                          fontSize: 13,
                          color: set ? primaryColor : Colors.redAccent,
                          fontWeight: set ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: set ? primaryColor : Colors.redAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Payment method selector — Paytm is listed first and pre-selected as the
  /// preferred gateway; Razorpay remains available. Gateways disabled in the
  /// fee_configs collection disappear from this list automatically.
  Widget _paymentMethodCard(Color cardColor, Color textColor) {
    final gateways = FeeService.activeGateways;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black54
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              "Payment Method",
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          ...gateways.map((g) => _gatewayTile(g.gateway, textColor)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _gatewayTile(String gateway, Color textColor) {
    final bool selected = selectedGateway == gateway;
    final bool preferred = gateway == FeeService.preferredGateway;
    final bool locked = isSubmitting || _awaitingPayment;
    final title = gateway == 'paytm' ? 'Paytm' : 'Razorpay';
    final subtitle = gateway == 'paytm'
        ? 'UPI · Cards · Wallet · NetBanking'
        : 'UPI · Cards · NetBanking';
    return InkWell(
      onTap: locked || selected
          ? null
          : () => setState(() => selectedGateway = gateway),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? primaryColor
                  : (isDark ? Colors.white38 : Colors.black26),
              size: 22,
            ),
            const SizedBox(width: 12),
            Icon(
              gateway == 'paytm'
                  ? Icons.account_balance_wallet_rounded
                  : Icons.bolt_rounded,
              color: selected
                  ? primaryColor
                  : (isDark ? Colors.white54 : Colors.black45),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            if (preferred)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Preferred',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _orderSummaryCard(Color cardColor, Color textColor) {
    final subColor = isDark ? Colors.white60 : Colors.black54;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black54
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Order Summary",
            style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            "Item Total",
            "₹${_itemTotal.toStringAsFixed(2)}",
            textColor,
          ),
          const SizedBox(height: 8),
          _summaryRow(
            _fees.platformFeeLabel,
            "₹${_platformFee.toStringAsFixed(2)}",
            subColor,
          ),
          const SizedBox(height: 8),
          _summaryRow(
            "Convenience Fee",
            "₹${_convenienceFee.toStringAsFixed(2)}",
            subColor,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(),
          ),
          _summaryRow(
            "Total",
            "₹${_grandTotal.toStringAsFixed(2)}",
            textColor,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) {
    final style = TextStyle(
      color: color,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 15 : 14,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }

  void _showUnavailableDialog(List<String> names) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Items Unavailable'),
        content: Text(
          'These Items Are No Longer Available:\n\n${names.join(', ')}\n\nRemove Them From Your Cart and Try Again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Update Cart'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePayment() async {
    if (isSubmitting) return;
    setState(() => isSubmitting = true);

    // CODEX EDITS: Resolve or safely reopen an existing Razorpay order before
    // validating a new cart or creating another chargeable order.
    try {
      final pending = await PendingPaymentService.loadForCurrentUser();
      if (pending != null) {
        // Gateway the pending session belongs to (Paytm ids are PTM-prefixed).
        final pendingGateway = pending.razorpayOrderId.startsWith('PTM')
            ? 'paytm'
            : 'razorpay';
        _setAwaitingPayment(true);
        final result = await _reconcilePendingPayment(
          pollAttempts: 1,
          showPendingMessage: false,
        );
        if (_paymentTerminalHandled) {
          if (mounted) setState(() => isSubmitting = false);
          return;
        }
        final state = result?['state']?.toString();
        if (state != 'expired' && pendingGateway != selectedGateway) {
          // The user explicitly chose the other gateway and reconciliation
          // found no captured payment on the old session. Abandon the local
          // pointer (the server session stays auditable, and a late capture
          // is still recovered by the gateway callback/webhook) and fall
          // through to a fresh payment with the selected gateway.
          await PendingPaymentService.clear(
            expectedOrderId: pending.razorpayOrderId,
          );
          _paytmOrder = null;
          _razorpayOrder = null;
          _razorpayKeyId = null;
          _setAwaitingPayment(false);
        } else if (state != 'expired') {
          // Same gateway — resume the existing session instead of creating a
          // second chargeable order.
          if (_paytmOrder != null &&
              (_paytmOrder?['txnToken']?.toString().isNotEmpty ?? false)) {
            _setAwaitingPayment(true);
            await _openPaytmCheckout();
          } else if (_razorpayOrder != null &&
              (_razorpayKeyId?.isNotEmpty ?? false)) {
            _setAwaitingPayment(true);
            await _openRazorpayCheckout();
          } else {
            _setAwaitingPayment(false);
            _showPaymentPending();
          }
          if (mounted) setState(() => isSubmitting = false);
          return;
        }
      }
    } catch (_) {
      _setAwaitingPayment(false);
      _showPaymentPending();
      if (mounted) setState(() => isSubmitting = false);
      return;
    }

    final orderItems = _orderItems();
    if (orderItems.isEmpty) {
      setState(() => isSubmitting = false);
      _showError("Your Cart is Empty");
      return;
    }

    // Client-side guard before charging the user
    if (!widget.isReorder) {
      try {
        final ids = globalCartItems.map((e) => e["id"].toString()).toList();
        if (ids.isNotEmpty) {
          final result = await ApiService.checkMenuAvailability(ids);
          final unavailable = result.entries
              .where((e) => (e.value as Map)['available'] == false)
              .map((e) => (e.value as Map)['name']?.toString() ?? e.key)
              .toList();
          if (unavailable.isNotEmpty && mounted) {
            setState(() => isSubmitting = false);
            _showUnavailableDialog(unavailable);
            return;
          }
        }
      } catch (_) {
        // Network error — proceed; server also validates inside initiatePayment
      }
    }

    try {
      // Step 1: server computes totals from the DB fee config, creates the
      // gateway order (Paytm or Razorpay), and stashes the cart server-side.
      // No DB order is written here.
      final data = await ApiService.initiatePayment(
        customerName: AppSession.name,
        customerEmail: AppSession.email,
        userId: AppSession.userId.isEmpty ? null : AppSession.userId,
        cafeId: widget.cafeId,
        cafeteriaName: _cafeteriaName(),
        items: orderItems,
        location: widget.pickupLocation ?? "Pickup Counter",
        pickupTime: _pickupTimeISO,
        gateway: selectedGateway,
        channel: kIsWeb ? 'web' : 'app',
      );

      if (data['gateway']?.toString() == 'paytm' && data['paytmOrder'] is Map) {
        _paytmOrder = Map<String, dynamic>.from(data['paytmOrder'] as Map);
        _razorpayOrder = null;
        _razorpayKeyId = null;
        // CODEX EDITS: Persist before opening checkout so immediate process
        // death or app switching cannot orphan the payment.
        await PendingPaymentService.save(
          _paytmOrder?['orderId']?.toString() ?? '',
        );
        _setAwaitingPayment(true);
        await _openPaytmCheckout();
      } else {
        final razorpayOrder = data['razorpayOrder'];
        if (razorpayOrder is! Map) {
          // Never blind-cast the server payload — a missing order must surface
          // as a readable message, not a Null type-cast error.
          throw Exception(
            data['message']?.toString() ??
                'Payment could not be started. Please try again.',
          );
        }
        _razorpayOrder = Map<String, dynamic>.from(razorpayOrder);
        _razorpayKeyId = data['razorpayKeyId']?.toString();
        _paytmOrder = null;
        // CODEX EDITS: Persist before opening native Checkout so immediate
        // process death or UPI switching cannot orphan the payment.
        await PendingPaymentService.save(
          _razorpayOrder?['id']?.toString() ?? '',
        );
        _setAwaitingPayment(true);
        await _openRazorpayCheckout();
      }
    } catch (error) {
      _setAwaitingPayment(false);
      _showError(error.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  String _cafeteriaName() {
    if (widget.cafeteriaName != null && widget.cafeteriaName!.isNotEmpty) {
      return widget.cafeteriaName!;
    }
    if (globalCartItems.isNotEmpty) {
      return globalCartItems.first["cafeteriaName"]?.toString() ??
          "Campus Cafeteria";
    }
    return "Campus Cafeteria";
  }

  List<Map<String, dynamic>> _orderItems() {
    if (widget.isReorder && widget.items != null) {
      return widget.items!
          .map(
            (item) => {
              "name": item.name,
              "qty": item.quantity,
              "price": item.price,
            },
          )
          .toList();
    }

    return globalCartItems
        .map(
          (item) => {
            "id": item["id"],
            "name": item["name"],
            "qty": item["qty"],
            "price": item["price"],
            "image": item["image"],
          },
        )
        .toList();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  // CODEX EDITS: Every SDK error is indeterminate until the authenticated
  // backend checks Razorpay. No message-text matching or false terminal failure.
  Future<void> _handleRazorpayError(Map<String, dynamic> sdkError) async {
    if (_paymentTerminalHandled) return;
    _setAwaitingPayment(true);
    // CODEX EDITS 2026-07-09 11:22:21 IST: Reconcile cancellation/errors
    // silently first; only then decide whether to show resume, expire, or
    // user-abandon options.
    final result = await _reconcilePendingPayment(
      sdkError: sdkError,
      pollAttempts: 6,
      showPendingMessage: false,
    );
    if (!mounted || _paymentTerminalHandled) return;
    final state = result?['state']?.toString();
    if (state == 'expired') {
      _showError('Payment session expired. Please tap Pay again.');
      return;
    }
    if (_isUserCancelledPayment(sdkError)) {
      _showPaymentCancelledPending();
    } else {
      _showPaymentPending();
    }
  }

  // Paytm SDK finished and returned a result map. The map is never trusted —
  // the backend's Transaction Status reconciliation decides the real outcome.
  Future<void> _handlePaytmResult(Map<String, dynamic> result) async {
    if (_paymentTerminalHandled) return;
    _setAwaitingPayment(true);
    await _reconcilePendingPayment(pollAttempts: 6, showPendingMessage: true);
  }

  // Paytm SDK errors (cancel, back-press, network) are indeterminate until the
  // backend checks the Transaction Status API — mirrors the Razorpay handler.
  Future<void> _handlePaytmError(Map<String, dynamic> sdkError) async {
    if (_paymentTerminalHandled) return;
    _setAwaitingPayment(true);
    final result = await _reconcilePendingPayment(
      sdkError: sdkError,
      pollAttempts: 4,
      showPendingMessage: false,
    );
    if (!mounted || _paymentTerminalHandled) return;
    final state = result?['state']?.toString();
    if (state == 'expired') {
      // Terminal for this Paytm order (failed or window over) — the pending
      // pointer is already cleared, so the next Pay starts a fresh payment.
      _paytmOrder = null;
      _razorpayOrder = null;
      _razorpayKeyId = null;
      _setAwaitingPayment(false);
      _showError('Payment did not complete. Please tap Pay to try again.');
      return;
    }
    if (_isUserCancelledPayment(sdkError)) {
      _showPaymentCancelledPending();
    } else {
      _showPaymentPending();
    }
  }

  // CODEX EDITS: Selecting an external wallet is a continuation, not failure.
  void _handleExternalWallet(String walletName) {
    if (!mounted || _paymentTerminalHandled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Continue payment in $walletName'),
        backgroundColor: primaryColor,
      ),
    );
  }

  // CODEX EDITS: Restore and reconcile a payment whenever Checkout itself is
  // reopened. The backend returns checkoutOrder for safe same-order retry.
  Future<void> _restorePendingPayment() async {
    if (!mounted || _paymentTerminalHandled) return;
    final pending = await PendingPaymentService.loadForCurrentUser();
    if (!mounted || pending == null) return;
    _setAwaitingPayment(true);
    await _reconcilePendingPayment(pollAttempts: 1, showPendingMessage: true);
  }

  // CODEX EDITS: Single reconciliation gate shared by error, resume, reopen,
  // confirm failure, and retry paths.
  Future<Map<String, dynamic>?> _reconcilePendingPayment({
    Map<String, dynamic>? sdkError,
    int pollAttempts = 1,
    bool showPendingMessage = false,
  }) async {
    if (_isReconcilingPayment || _paymentTerminalHandled) return null;
    _isReconcilingPayment = true;
    Map<String, dynamic>? latest;
    try {
      for (var attempt = 0; attempt < pollAttempts; attempt++) {
        latest = await PendingPaymentService.reconcile(
          sdkError: attempt == 0 ? sdkError : null,
        );
        if (!mounted || _paymentTerminalHandled) return latest;
        if (latest == null) break;

        final state = latest['state']?.toString();
        if (state == 'captured' && latest['order'] is Map) {
          await _finishSuccessfulPayment(
            Map<String, dynamic>.from(latest['order'] as Map),
          );
          return latest;
        }
        if (state == 'expired') {
          _setAwaitingPayment(false);
          if (showPendingMessage) {
            _showError(
              'The previous payment session expired. No confirmed payment was found.',
            );
          }
          return latest;
        }

        // Preserve the server-returned order/key so Pay retries this exact
        // Razorpay order instead of charging through a new one.
        final checkoutOrder = latest['checkoutOrder'];
        if (checkoutOrder is Map) {
          _razorpayOrder = Map<String, dynamic>.from(checkoutOrder);
        }
        final returnedKey = latest['razorpayKeyId']?.toString();
        if (returnedKey != null && returnedKey.isNotEmpty) {
          _razorpayKeyId = returnedKey;
        }
        // Paytm sessions return their own resumable checkout payload (same
        // orderId + txnToken, valid for the 15-minute active window).
        final paytmCheckout = latest['paytmCheckout'];
        if (paytmCheckout is Map) {
          _paytmOrder = Map<String, dynamic>.from(paytmCheckout);
        }

        if (attempt + 1 < pollAttempts) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (mounted && !_paymentTerminalHandled) {
        _setAwaitingPayment(false);
        if (showPendingMessage) _showPaymentPending();
      }
      return latest;
    } catch (error) {
      if (mounted && !_paymentTerminalHandled) {
        _setAwaitingPayment(false);
        if (showPendingMessage) _showPaymentPending();
      }
      return latest;
    } finally {
      _isReconcilingPayment = false;
    }
  }

  // CODEX EDITS 2026-07-09 11:22:21 IST: Razorpay cancellation is still
  // reconciled first, but after no capture is found the user may explicitly
  // abandon this local pending pointer and start a fresh cart payment.
  bool _isUserCancelledPayment(Map<String, dynamic> sdkError) {
    final code = sdkError['code']?.toString();
    final message = sdkError['message']?.toString().toLowerCase() ?? '';
    final nested = sdkError['error'];
    final nestedReason = nested is Map
        ? (nested['reason'] ?? nested['error_reason'] ?? '')
              .toString()
              .toLowerCase()
        : '';
    return code == '2' ||
        message.contains('cancel') ||
        nestedReason.contains('cancel');
  }

  // CODEX EDITS 2026-07-09 11:22:21 IST: This action only clears the client
  // resume token. The backend session remains auditable/reconcilable, and any
  // truly captured payment can still be recovered by webhook/reconcile.
  void _showPaymentCancelledPending() {
    if (!mounted) return;
    final pendingOrderId =
        _paytmOrder?['orderId']?.toString() ?? _razorpayOrder?['id']?.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Payment cancelled. We verified no payment capture yet.',
        ),
        backgroundColor: const Color(0xFFF59E0B),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Start new',
          textColor: Colors.white,
          onPressed: () {
            unawaited(
              PendingPaymentService.clear(expectedOrderId: pendingOrderId),
            );
            _razorpayOrder = null;
            _razorpayKeyId = null;
            _paytmOrder = null;
            _setAwaitingPayment(false);
          },
        ),
      ),
    );
  }

  // CODEX EDITS: Pending is deliberately neutral and instructs against a
  // second charge while webhook/API confirmation is still in flight.
  void _showPaymentPending() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Payment is still being verified. Do not start a new payment; tap Pay to safely resume this same order.',
        ),
        backgroundColor: Color(0xFFF59E0B),
        duration: Duration(seconds: 6),
      ),
    );
  }

  // CODEX EDITS: Exactly-once UI completion protects against simultaneous SDK,
  // lifecycle, and webhook reconciliation results.
  Future<void> _finishSuccessfulPayment(Map<String, dynamic> order) async {
    if (_paymentTerminalHandled) return;
    _paymentTerminalHandled = true;
    _resumeReconcileTimer?.cancel();
    final providerOrderId = order['payment'] is Map
        ? (order['payment'] as Map)['providerOrderId']?.toString()
        : (_paytmOrder?['orderId']?.toString() ??
              _razorpayOrder?['id']?.toString());
    await PendingPaymentService.clear(expectedOrderId: providerOrderId);
    globalCartItems.clear();
    CartModel.clear();
    await saveCart();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SuccessPage(order: order)),
    );
  }

  Future<void> _handleRazorpaySuccess(Map<String, dynamic> response) async {
    if (_paymentTerminalHandled) return;
    try {
      // Step 2: server verifies HMAC signature, retrieves server-side cart,
      // and creates the DB order only now — after confirmed payment.
      final order = await ApiService.confirmOrder(
        razorpayOrderId: response['orderId']?.toString() ?? '',
        razorpayPaymentId: response['paymentId']?.toString() ?? '',
        razorpaySignature: response['signature']?.toString() ?? '',
      );

      // CODEX EDITS: Share exactly-once completion with every recovery path.
      await _finishSuccessfulPayment(order);
    } catch (error) {
      // CODEX EDITS: Confirmation transport errors are reconciled, never shown
      // as payment failures after Razorpay has emitted success.
      await _reconcilePendingPayment(
        sdkError: {
          'code': 'confirm_transport_error',
          'message': error.toString().replaceFirst('Exception: ', ''),
        },
        pollAttempts: 6,
        showPendingMessage: true,
      );
    }
  }

  Future<void> _openRazorpayCheckout() async {
    if (_razorpayOrder == null) return;
    await openRazorpayCheckout(
      _razorpayOrder!,
      AppSession.email,
      keyId: _razorpayKeyId,
    );
  }

  Future<void> _openPaytmCheckout() async {
    if (_paytmOrder == null) return;
    await openPaytmCheckout(_paytmOrder!);
  }
}
