import 'package:flutter/material.dart';
import 'success_page.dart';
import 'detail_page.dart';
import 'cart_page.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../services/razorpay_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

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
  String selectedUPIApp = "";
  String selectedWallet = "";
  String selectedBank = "";
  bool isSubmitting = false;
  Future<void> launchUPIApp({
  required String upiId,
  required String name,
  required double amount,
}) async {

  Uri uri = Uri.parse(
    "upi://pay?pa=$upiId&pn=$name&am=$amount&cu=INR"
  );

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  } else {
    _showError("UPI app not found");
  }
}

  final TextEditingController upiController = TextEditingController();

  Map<String, dynamic>? _currentOrder;
  Map<String, dynamic>? _razorpayOrder;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
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
                isDark ? const Color(0xFF0F172A).withOpacity(0.9) : const Color(0xFFF0F6FF).withOpacity(0.85), 
                BlendMode.srcATop
              ),
            ),
          ),
        ),
    ],
                  _section("UPI", "upi", _upiUI(), cardColor, textColor, isAvailable: true),
                  _section("Wallets", "wallet", _walletUI(), cardColor, textColor, isAvailable: false),
                  _section("Net Banking", "bank", _bankUI(), cardColor, textColor, isAvailable: false),
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
                      isSubmitting ? "Placing Order..." : "Pay Now",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

  Widget _section(String title, String value, Widget child, Color cardColor, Color textColor, {bool isAvailable = true}) {
    bool isSelected = selectedMethod == value;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
          )
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: TextStyle(
                color: isAvailable ? textColor : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            subtitle: isAvailable 
                ? null 
                : const Text("Currently unavailable", style: TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: isAvailable 
                ? Icon(
                    isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: textColor,
                  ) 
                : const Icon(Icons.block, color: Colors.grey, size: 16),
            onTap: isAvailable ? () {
              setState(() {
                selectedMethod = isSelected ? "" : value;
              });
            } : null,
          ),
          if (isSelected && isAvailable)
            Padding(
              padding: const EdgeInsets.all(14),
              child: child,
            )
        ],
      ),
    );
  }

  Widget _upiUI() {
    final textColor = isDark ? Colors.white : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Pay using UPI Apps",
            style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _upiApp("GPay", "assets/gpay.jpg"),
            _upiApp("PhonePe", "assets/phonepe.jpg"),
            _upiApp("Paytm", "assets/paytm.jpg"),
          ],
        ),
      ],
    );
  }

  Widget _upiApp(String name, String imagePath) {
    bool isSelected = selectedUPIApp == name;

    return GestureDetector(
     onTap: () async {
  setState(() {
    selectedUPIApp = name;
  });

  double totalAmount = widget.items != null
      ? widget.items!.fold(
          0.0,
          (sum, item) => sum + (item.price * item.quantity),
        ).toDouble()
      : globalCartItems.fold(
          0.0,
          (sum, item) =>
              sum + ((item["price"] as num) * (item["qty"] as int)),
        );

  await launchUPIApp(
    upiId: "yourupi@oksbi",
    name: "LunchTime",
    amount: totalAmount,
  );
},
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? primaryColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: ClipOval(
                child: Image.asset(
                  imagePath,
                  width: 48, // Increased to perfectly fit the CircleAvatar diameter
                  height: 48, // Increased to perfectly fit the CircleAvatar diameter
                  fit: BoxFit.cover, // Changed from contain to cover to eliminate whitespace
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.account_balance_wallet, color: primaryColor);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black))
        ],
      ),
    );
  }

  Widget _walletUI() {
    return Column(
      children: [
        _walletTile("Paytm"),
        _walletTile("PhonePe"),
        _walletTile("Amazon Pay"),
      ],
    );
  }

  Widget _walletTile(String name) {
    final textColor = isDark ? Colors.white : Colors.black;

    return ListTile(
      title: Text(name, style: TextStyle(color: textColor)),
      trailing: Radio(
        value: name,
        groupValue: selectedWallet,
        activeColor: primaryColor,
        onChanged: (value) {
          setState(() {
            selectedWallet = value.toString();
          });
        },
      ),
    );
  }

  Widget _bankUI() {
    return DropdownButtonFormField<String>(
      initialValue: selectedBank.isEmpty ? null : selectedBank,
      hint: const Text("Select Bank"),
      items: ["HDFC", "ICICI", "SBI", "Axis"]
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList(),
      onChanged: (value) {
        setState(() {
          selectedBank = value!;
        });
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F6F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
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
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerName': AppSession.name,
          'customerEmail': AppSession.email,
          'userId': AppSession.userId.isEmpty ? null : AppSession.userId,
          'cafeId': widget.cafeId,
          'cafeteriaName': _cafeteriaName(),
          'items': orderItems,
          'payment': {
            'method': 'Online',
            'provider': 'Razorpay',
            'status': 'Pending',
          },
          'location': widget.pickupLocation ?? "Pickup counter",
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        _currentOrder = data['order'];
        _razorpayOrder = data['razorpayOrder'];

        if (_razorpayOrder != null) {
          await _openRazorpayCheckout();
        } else {
          // Fallback if no razorpay order
          if (_currentOrder != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => SuccessPage(order: _currentOrder!)),
            );
          }
        }
      } else {
        _showError(data['message'] ?? 'Failed to place order');
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
                  color: const Color(0xFF0F4CFF).withOpacity(0.16),
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
      final verifyResponse = await http.post(
        Uri.parse('${ApiService.baseUrl}/payment/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_order_id': response['orderId'],
          'razorpay_payment_id': response['paymentId'],
          'razorpay_signature': response['signature'],
        }),
      );

      if (verifyResponse.statusCode == 200) {
        if (_currentOrder != null) {
          await http.patch(
            Uri.parse('${ApiService.baseUrl}/orders/${_currentOrder!['orderId']}/payment'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transactionId': response['paymentId'],
              'status': 'Paid',
            }),
          );
        }

        if (!mounted || _currentOrder == null) return;
        await _showOrderPlacedPopup();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => SuccessPage(order: _currentOrder!)),
        );
      } else {
        _showError('Payment verification failed');
      }
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