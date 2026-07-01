import 'package:flutter/material.dart';
import 'success_page.dart';
import 'detail_page.dart';
import 'cart_page.dart';
import '../model/cart_model.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../services/razorpay_helper.dart';

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

class _CheckoutPageState extends State<CheckoutPage> {
  final Color primaryColor = const Color(0xFF0F4CFF);

  String selectedMethod = "";
  bool isSubmitting = false;
  final TextEditingController upiController = TextEditingController();
  TimeOfDay? _pickupTime;

  // No _currentOrder field — the DB order is only created after payment succeeds.
  Map<String, dynamic>? _razorpayOrder;
  String? _razorpayKeyId; // Received from server — never hardcoded client-side

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
    return DateTime(now.year, now.month, now.day, _pickupTime!.hour, _pickupTime!.minute).toIso8601String();
  }

  Future<void> _selectPickupTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _pickupTime ??
          TimeOfDay(hour: now.hour, minute: (now.minute ~/ 15 + 1) * 15 % 60),
      helpText: 'SELECT PICKUP TIME',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
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
    final nowMinutes = now.hour * 60 + now.minute;
    final pickedMinutes = picked.hour * 60 + picked.minute;
    if (pickedMinutes <= nowMinutes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pickup Time Must Be Today and Later Than Current Time.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }
    // Warn if pickup is more than 4 hours away
    final diffMinutes = pickedMinutes - nowMinutes;
    if (diffMinutes > 240) {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: const Color(0xFF0F4CFF).withValues(alpha: 0.25)),
            ),
            title: Row(
              children: [
                Icon(Icons.schedule_rounded, color: const Color(0xFF0F4CFF), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Confirm Pickup Time',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            content: Text(
              'Your selected pickup time is more than 4 hours from now. Please ensure this is intentional — canteen staff will prepare your order based on this time.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                height: 1.55,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F4CFF),
                  side: const BorderSide(color: Color(0xFF0F4CFF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Change Time', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F4CFF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      );
      if (confirm != true) return;
    }

    setState(() => _pickupTime = picked);
  }

  double get _itemTotal {
    if (widget.isReorder && widget.items != null) {
      return widget.items!.fold(0.0, (s, i) => s + i.price * i.quantity);
    }
    return globalCartItems.fold(0.0, (s, i) => s + (i["price"] as num) * (i["qty"] as int));
  }

  double get _platformFee => double.parse((_itemTotal * 0.03).toStringAsFixed(2));
  double get _convenienceFee => 1.5;
  double get _grandTotal => _itemTotal + _platformFee + _convenienceFee;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    selectedMethod = "upi";
    initRazorpay(_handleRazorpaySuccess, _handleRazorpayError);
  }

  @override
  void dispose() {
    disposeRazorpay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background =
        isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);

    final cardColor =
        isDark ? const Color(0xFF0F172A) : Colors.white;

    final textColor = isDark ? Colors.white : Colors.black;

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
            bottom: 60 
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE8F0FF),
            image: DecorationImage(
              image: const AssetImage('assets/bg.jpg'), 
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                isDark ? const Color(0xFF0F172A).withValues(alpha: 0.9) : const Color(0xFFF0F6FF).withValues(alpha: 0.85), 
                BlendMode.srcATop
              ),
            ),
          ),
        ),
    ],
                  _orderSummaryCard(cardColor, textColor),
                  _pickupTimeCard(cardColor, textColor),
                  _section("UPI", "upi", _upiUI(), cardColor, textColor),
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
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))
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
                    onPressed: (isSubmitting || _pickupTime == null) ? null : _handlePayment,
                    child: Text(
                      isSubmitting ? "Placing Order..." : _pickupTime == null ? "Set Pickup Time to Continue" : "Pay  ₹${_grandTotal.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          color: set ? primaryColor.withValues(alpha: 0.5) : Colors.redAccent.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [BoxShadow(color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
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
                    color: (set ? primaryColor : Colors.redAccent).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.access_time_rounded, color: set ? primaryColor : Colors.redAccent, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pickup Time', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        set ? _pickupTimeLabel : 'Required - Tap to Set',
                        style: TextStyle(fontSize: 13, color: set ? primaryColor : Colors.redAccent, fontWeight: set ? FontWeight.w600 : FontWeight.normal),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: set ? primaryColor : Colors.redAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String value, Widget child, Color cardColor, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          )
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _upiUI() {
    return Row(
      children: [
        Icon(Icons.verified, color: primaryColor, size: 18),
        const SizedBox(width: 8),
        Text(
          "via Razorpay",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
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
        boxShadow: [BoxShadow(color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Summary", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 12),
          _summaryRow("Item Total", "₹${_itemTotal.toStringAsFixed(2)}", textColor),
          const SizedBox(height: 8),
          _summaryRow("Platform Fee (3%)", "₹${_platformFee.toStringAsFixed(2)}", subColor),
          const SizedBox(height: 8),
          _summaryRow("Convenience Fee", "₹${_convenienceFee.toStringAsFixed(2)}", subColor),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          _summaryRow("Total", "₹${_grandTotal.toStringAsFixed(2)}", textColor, bold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool bold = false}) {
    final style = TextStyle(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 15 : 14);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
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
      // Step 1: server computes totals, creates Razorpay order, stashes cart.
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
      );

      _razorpayOrder = Map<String, dynamic>.from(data['razorpayOrder'] as Map);
      _razorpayKeyId = data['razorpayKeyId']?.toString();
      await _openRazorpayCheckout();
    } catch (error) {
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
      return globalCartItems.first["cafeteriaName"]?.toString() ?? "Campus Cafeteria";
    }
    return "Campus Cafeteria";
  }

  List<Map<String, dynamic>> _orderItems() {
    if (widget.isReorder && widget.items != null) {
      return widget.items!
          .map((item) => {
                "name": item.name,
                "qty": item.quantity,
                "price": item.price,
              })
          .toList();
    }

    return globalCartItems
        .map((item) => {
              "id": item["id"],
              "name": item["name"],
              "qty": item["qty"],
              "price": item["price"],
              "image": item["image"],
            })
        .toList();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _handleRazorpayError(String? message) {
  final errorMessage =
      (message == null ||
       message.trim().isEmpty ||
       message.trim().toLowerCase() == 'undefined' ||
       message.trim().toLowerCase() == 'null')
          ? 'Try again'
          : message;

  _showError('Payment failed: $errorMessage');
}

  Future<void> _handleRazorpaySuccess(Map<String, dynamic> response) async {
    try {
      // Step 2: server verifies HMAC signature, retrieves server-side cart,
      // and creates the DB order only now — after confirmed payment.
      final order = await ApiService.confirmOrder(
        razorpayOrderId: response['orderId']?.toString() ?? '',
        razorpayPaymentId: response['paymentId']?.toString() ?? '',
        razorpaySignature: response['signature']?.toString() ?? '',
      );

      if (!mounted) return;
      // Clear cart now that order is placed
      globalCartItems.clear();
      CartModel.clear();
      await saveCart();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SuccessPage(order: order)),
      );
    } catch (error) {
      _showError('Payment verification error: ${error.toString().replaceFirst("Exception: ", "")}');
    }
  }

  // --- THIS IS THE ONLY CHANGED METHOD ---
  Future<void> _openRazorpayCheckout() async {
    if (_razorpayOrder == null) return;

    // Grab the UPI ID from the text field
    String? enteredUpiId = upiController.text.trim();
    if (enteredUpiId.isEmpty) {
      enteredUpiId = null;
    }

    // Pass the upiId to the razorpay helper
    await openRazorpayCheckout(
      _razorpayOrder!,
      AppSession.email,
      keyId: _razorpayKeyId,
      upiId: enteredUpiId,
    );
  }
}

