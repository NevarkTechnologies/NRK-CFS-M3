import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'checkout_page.dart';
import 'cafeteria_page.dart';
import '../model/cart_model.dart';
import '../services/api_service.dart';
import 'package:lottie/lottie.dart';
import 'dart:convert';

List<Map<String, dynamic>> globalCartItems = [];
final ValueNotifier<int> cartCountNotifier = ValueNotifier(0);
String _cartUserId = '';

String _cartKey() => 'cart_items_$_cartUserId';

Future<void> saveCart() async {
  if (_cartUserId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cartKey(), jsonEncode(globalCartItems));
    cartCountNotifier.value = globalCartItems.fold(
      0,
      (s, i) => s + (i["qty"] as int? ?? 1),
    );
  } catch (_) {}
}

Future<void> loadCart(String userId) async {
  _cartUserId = userId;
  globalCartItems = [];
  CartModel.clear();
  cartCountNotifier.value = 0;
  if (userId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_cartKey());
    if (str != null) {
      final decoded = jsonDecode(str) as List<dynamic>;
      globalCartItems = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      cartCountNotifier.value = globalCartItems.fold(
        0,
        (s, i) => s + (i["qty"] as int? ?? 1),
      );
      // Sync CartModel so home page qty counters reflect persisted cart
      CartModel.clear();
      for (final item in globalCartItems) {
        final id = item["id"]?.toString() ?? '';
        final qty = item["qty"] as int? ?? 1;
        if (id.isNotEmpty) {
          for (int i = 0; i < qty; i++) {
            CartModel.add(id);
          }
        }
      }
    }
  } catch (_) {}
}

void clearCart() {
  globalCartItems = [];
  CartModel.clear();
  cartCountNotifier.value = 0;
  _cartUserId = '';
}

class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>>? cartItems;
  final VoidCallback? toggleTheme;

  const CartPage({super.key, this.cartItems, this.toggleTheme});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  final TextEditingController _couponController = TextEditingController();
  String _couponError = "";
  Set<String> _unavailableIds = {};

  void _applyCoupon() {
    final code = _couponController.text.trim();
    if (code.isEmpty) {
      setState(() => _couponError = "Please enter a coupon code");
      return;
    }
    setState(() => _couponError = "Invalid coupon code");
    FocusScope.of(context).unfocus();
  }

  @override
  void initState() {
    super.initState();
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      globalCartItems = widget.cartItems!;
    }
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    if (globalCartItems.isEmpty) return;
    try {
      final ids = globalCartItems.map((e) => e["id"].toString()).toList();
      final result = await ApiService.checkMenuAvailability(ids);
      final bad = <String>{};
      result.forEach((id, info) {
        if ((info as Map)['available'] == false) bad.add(id);
      });
      if (mounted) setState(() => _unavailableIds = bad);
    } catch (_) {}
  }

  num getTotal() {
    return globalCartItems.fold<num>(
      0,
      (sum, item) => sum + ((item["price"] as num) * (item["qty"] as int)),
    );
  }

  double get _platformFee =>
      double.parse((getTotal() * 0.03).toStringAsFixed(2));
  double get _convenienceFee => 1.5;

  double getFinalTotal() {
    return getTotal().toDouble() + _platformFee + _convenienceFee;
  }

  void updateQty(Map<String, dynamic> item, int delta) {
    setState(() {
      item["qty"] += delta;

      if (delta > 0) {
        CartModel.add(item["id"]);
      } else {
        CartModel.remove(item["id"]);
      }

      if (item["qty"] <= 0) {
        globalCartItems.remove(item);
      }
    });
    saveCart();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF020617)
        : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        // Builder so MediaQuery reflects the Scaffold's extendBody adjustment:
        // padding.bottom here equals the floating nav bar's full overlap
        // (pill height + margin + system inset).
        child: Builder(
          builder: (context) => SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(isDark, cardColor, textColor),
                      const SizedBox(height: 24),

                      if (globalCartItems.isEmpty)
                        _buildEmptyCart(subTextColor)
                      else ...[
                        ...globalCartItems.map(
                          (item) => _buildCartItemCard(
                            item,
                            isDark,
                            cardColor,
                            textColor,
                            subTextColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildCouponSection(
                          isDark,
                          cardColor,
                          textColor,
                          subTextColor,
                        ),
                        const SizedBox(height: 24),
                        _buildBillDetails(
                          isDark,
                          cardColor,
                          textColor,
                          subTextColor,
                        ),
                        const SizedBox(height: 24),
                        if (_unavailableIds.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              "Remove unavailable items before checking out",
                              style: const TextStyle(
                                color: Colors.red,
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _unavailableIds.isEmpty
                                ? primaryBlue
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _unavailableIds.isEmpty
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CheckoutPage(
                                      cafeteriaName: globalCartItems
                                          .first["cafeteriaName"]
                                          ?.toString(),
                                      cafeId: globalCartItems.first["cafeId"]
                                          ?.toString(),
                                      pickupLocation: globalCartItems
                                          .first["location"]
                                          ?.toString(),
                                    ),
                                  ),
                                )
                              : null,
                          child: const Text(
                            "Continue to Checkout",
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 1,
        isDark: isDark,
        toggleTheme: widget.toggleTheme ?? () {},
      ),
    );
  }

  Widget _buildTopBar(bool isDark, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CafeteriaPage(
                          toggleTheme: widget.toggleTheme ?? () {},
                        ),
                      ),
                      (route) => false,
                    );
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white : primaryBlue,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 44),
            ],
          ),
          Text(
            "My Cart",
            style: TextStyle(
              fontSize: 18,
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(
    Map<String, dynamic> item,
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    final itemId = item["id"]?.toString() ?? '';
    final bool isUnavailable = _unavailableIds.contains(itemId);
    final imageValue = item["image"]?.toString() ?? '';

    Widget imageWidget;

    if (imageValue.isEmpty) {
      imageWidget = Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      );
    } else if (imageValue.startsWith('data:image')) {
      try {
        final bytes = base64Decode(imageValue.split(',').last);

        imageWidget = Image.memory(
          bytes,
          height: 80,
          width: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return Container(
              color: Colors.grey.shade200,
              height: 80,
              width: 80,
              child: const Icon(Icons.fastfood),
            );
          },
        );
      } catch (_) {
        imageWidget = Container(
          color: Colors.grey.shade200,
          height: 80,
          width: 80,
          child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
        );
      }
    } else if (imageValue.startsWith('http')) {
      imageWidget = Image.network(
        imageValue,
        height: 80,
        width: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: Colors.grey.shade200,
          height: 80,
          width: 80,
          child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
        ),
      );
    } else {
      imageWidget = Image.asset(
        imageValue,
        height: 80,
        width: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: Colors.grey.shade200,
          height: 80,
          width: 80,
          child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: imageWidget,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["name"],
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "₹${item["price"]}",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: subTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isUnavailable) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      "No longer available",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  height: 32,
                  width: 100,
                  decoration: BoxDecoration(
                    color: primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: primaryBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InkWell(
                        onTap: () => updateQty(item, -1),
                        child: Icon(Icons.remove, size: 16, color: primaryBlue),
                      ),
                      Text(
                        "${item["qty"]}",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                      InkWell(
                        onTap: () => updateQty(item, 1),
                        child: Icon(Icons.add, size: 16, color: primaryBlue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 20,
              ),
            ),
            onPressed: () {
              setState(() {
                CartModel.delete(item["id"]);
                _unavailableIds.remove(item["id"]);
                globalCartItems.remove(item);
              });
              saveCart();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCouponSection(
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_offer_outlined,
              color: primaryBlue,
              size: 20,
            ),
          ),
          title: Text(
            "Have a coupon?",
            style: TextStyle(
              fontFamily: 'Nunito',
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: "Enter coupon code",
                            hintStyle: TextStyle(
                              color: subTextColor,
                              fontFamily: 'Inter',
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _applyCoupon(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onPressed: _applyCoupon,
                        child: const Text(
                          "Apply",
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_couponError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _couponError,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillDetails(
    bool isDark,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Bill Details",
            style: TextStyle(
              fontFamily: 'Nunito',
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _billRow("Item Total", getTotal(), subTextColor, textColor),
          _billRow("Platform Fee (3%)", _platformFee, subTextColor, textColor),
          _billRow("Convenience Fee", _convenienceFee, subTextColor, textColor),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              thickness: 1.5,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Pay",
                style: TextStyle(
                  fontFamily: 'Nunito',
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                "₹${getFinalTotal().toStringAsFixed(2)}",
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _billRow(
    String title,
    num amount,
    Color titleColor,
    Color amountColor,
  ) {
    final display = amount is int ? "$amount" : amount.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              color: titleColor,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          Text(
            "₹$display",
            style: TextStyle(
              fontFamily: 'Inter',
              color: amountColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              SizedBox(
                height: 180,
                child: Lottie.asset(
                  'assets/Cart icon.json',
                  fit: BoxFit.contain,
                ),
              ),
              Container(
                height: 30,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "Your Cart Is Empty",
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: subTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Add Items from Menu Now !",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: subTextColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
