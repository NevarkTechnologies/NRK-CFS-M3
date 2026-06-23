import 'package:flutter/material.dart';
import 'success_page.dart';
import 'detail_page.dart';
import 'cart_page.dart';
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

  Map<String, dynamic>? _currentOrder;
  Map<String, dynamic>? _razorpayOrder;

  double get _itemTotal {
    if (widget.isReorder && widget.items != null) {
      return widget.items!.fold(0.0, (s, i) => s + i.price * i.quantity);
    }
    return globalCartItems.fold(0.0, (s, i) => s + (i["price"] as num) * (i["qty"] as int));
  }

  double get _platformFee => double.parse((_itemTotal * 0.03).toStringAsFixed(2));
  double get _grandTotal => _itemTotal + _platformFee;

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
                  _couponsCard(cardColor, textColor),
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
                    onPressed: isSubmitting ? null : _handlePayment,
                    child: Text(
                      isSubmitting ? "Placing Order..." : "Pay  ₹${_grandTotal.toStringAsFixed(2)}",
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

  Widget _couponsCard(Color cardColor, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(Icons.local_offer_outlined, color: primaryColor),
          title: Text("Available Coupons", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                "No coupons available at the moment.",
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePayment() async {
    if (selectedMethod.isEmpty) {
      setState(() => selectedMethod = "upi");
    }

    final orderItems = _orderItems();
    if (orderItems.isEmpty) {
      _showError("Your cart is empty");
      return;
    }

    setState(() => isSubmitting = true);
    try {
      final data = await ApiService.createOrderForPayment(
        customerName: AppSession.name,
        customerEmail: AppSession.email,
        userId: AppSession.userId.isEmpty ? null : AppSession.userId,
        cafeId: widget.cafeId,
        cafeteriaName: _cafeteriaName(),
        items: orderItems,
        location: widget.pickupLocation ?? "Pickup counter",
      );

      _currentOrder = Map<String, dynamic>.from(data['order'] as Map);
      final razorpayOrder = data['razorpayOrder'];
      _razorpayOrder = razorpayOrder is Map
          ? Map<String, dynamic>.from(razorpayOrder)
          : null;

      if (_razorpayOrder != null) {
        await _openRazorpayCheckout();
      } else {
        if (_currentOrder != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => SuccessPage(order: _currentOrder!)),
          );
        }
      }
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

  Future<void> _showOrderPlacedPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4CFF).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.check_circle_outline, color: Color(0xFF0F4CFF), size: 30),
              ),
              const SizedBox(width: 12),
              Text('Order Confirmed', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
            ],
          ),
          content: Text(
            'Your payment was successful and your order has been placed. Check notifications for updates.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _handleRazorpayError(String message) {
    _showError('Payment failed: $message');
  }

  Future<void> _handleRazorpaySuccess(Map<String, dynamic> response) async {
    try {
      await ApiService.verifyRazorpayPayment(
        orderId: response['orderId']?.toString() ?? '',
        paymentId: response['paymentId']?.toString() ?? '',
        signature: response['signature']?.toString() ?? '',
      );

      if (_currentOrder != null) {
        _currentOrder = await ApiService.updateOrderPayment(
          orderId: _currentOrder!['orderId']?.toString() ?? '',
          transactionId: response['paymentId']?.toString() ?? '',
          status: 'Paid',
          razorpayOrderId: response['orderId']?.toString() ?? '',
          razorpaySignature: response['signature']?.toString() ?? '',
        );
      }

      if (!mounted || _currentOrder == null) return;
      await _showOrderPlacedPopup();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SuccessPage(order: _currentOrder!)),
      );
    } catch (error) {
      _showError('Payment verification error: $error');
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
      upiId: enteredUpiId, 
    );
  }
}
