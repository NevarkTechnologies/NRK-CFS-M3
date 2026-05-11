import 'dart:async';

import 'package:flutter/material.dart';

import '../model/cart_model.dart';
import 'cafeteria_page.dart';
import 'cart_page.dart';

class SuccessPage extends StatefulWidget {
  final Map<String, dynamic> order;

  const SuccessPage({super.key, required this.order});

  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage> {
  int step = 0;
  final Color primary = const Color(0xFF0F4CFF);

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => step = 1);

      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => step = 2);
      });
    });
  }

  void _goToHome() {
    for (final item in globalCartItems) {
      final qty = item["qty"] as int;
      for (int i = 0; i < qty; i++) {
        CartModel.remove(item["id"]);
      }
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
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subText = isDark ? Colors.white70 : Colors.black87;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _goToHome();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: step == 2 ? _appBar(cardColor) : null,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _buildUI(cardColor, textColor, subText),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(Color cardColor) {
    return AppBar(
      backgroundColor: cardColor,
      elevation: 0,
      iconTheme: IconThemeData(color: primary),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _goToHome,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order #${widget.order["orderId"] ?? ""}", style: TextStyle(color: primary)),
          Text(
            widget.order["cafeteriaName"]?.toString() ?? "Cafeteria",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
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
    return _centerCard(
      key: const ValueKey("processing"),
      cardColor: cardColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primary),
          const SizedBox(height: 20),
          Text("Processing Payment...", style: TextStyle(color: primary, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _successUI(Color cardColor, Color textColor) {
    return _centerCard(
      key: const ValueKey("success"),
      cardColor: cardColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 100),
          const SizedBox(height: 20),
          Text(
            "Payment Successful",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _orderPageUI(Color cardColor, Color textColor, Color subText) {
    final items = widget.order["items"] as List<dynamic>? ?? [];
    final total = widget.order["total"]?.toString() ?? "0";
    final status = widget.order["status"]?.toString() ?? "Pending";

    return ListView(
      key: const ValueKey("order"),
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(status),
        const SizedBox(height: 20),
        _cardWrapper(
          cardColor: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title("Order Progress", textColor),
              _progress("Payment Confirmed", true, textColor),
              _progress("Preparing Food", ["Preparing", "Ready", "Completed"].contains(status), textColor),
              _progress("Ready to Pickup", ["Ready", "Completed"].contains(status), textColor, isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _cardWrapper(
          cardColor: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title("Order Items", textColor),
              ...items.map((item) {
                final map = item as Map<String, dynamic>;
                return _item(
                  map["name"]?.toString() ?? "Item",
                  "Rs ${map["price"] ?? 0}",
                  map["qty"]?.toString() ?? "1",
                  textColor,
                );
              }),
              Divider(color: subText),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                  Text("Rs $total", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _cardWrapper(
          cardColor: cardColor,
          child: Row(
            children: [
              Icon(Icons.location_on, color: subText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.order["location"]?.toString() ?? "Pickup counter",
                  style: TextStyle(color: textColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusCard(String status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, primary.withOpacity(0.7)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Order Confirmed",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text("Current status: $status", style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _cardWrapper({required Widget child, required Color cardColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _centerCard({required Widget child, required Key key, required Color cardColor}) {
    return Center(
      key: key,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black54 : Colors.black.withOpacity(0.08),
              blurRadius: 20,
            ),
          ],
        ),
        child: SizedBox(height: 280, child: child),
      ),
    );
  }

  Widget _title(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
      ),
    );
  }

  Widget _progress(String title, bool done, Color textColor, {bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? primary : Colors.transparent,
                border: Border.all(color: done ? primary : Colors.grey, width: 2),
              ),
              child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
            if (!isLast) Container(width: 2, height: 40, color: Colors.grey),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
            Text(done ? "Completed" : "Pending", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _item(String name, String price, String qty, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$name (x$qty)", style: TextStyle(color: textColor)),
          Text(price, style: TextStyle(color: textColor)),
        ],
      ),
    );
  }
}
