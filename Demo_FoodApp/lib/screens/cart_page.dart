import 'package:flutter/material.dart';
import 'checkout_page.dart';
import 'cafeteria_page.dart'; 
import '../model/cart_model.dart'; 
import 'package:lottie/lottie.dart';

List<Map<String, dynamic>> globalCartItems = [];

// ─── Coupon Model ────────────────────────────────────────────────────────────
enum CouponType { flat, percent }

class CouponDef {
  final String code;
  final CouponType type;
  final double value;
  final double minOrder;

  const CouponDef({
    required this.code,
    required this.type,
    required this.value,
    required this.minOrder,
  });

  String get description {
    String offer = type == CouponType.flat
        ? '₹${value.toInt()} OFF'
        : '${value.toInt()}% OFF';
    return minOrder > 0 ? '$offer above ₹${minOrder.toInt()}' : offer;
  }
}

const List<CouponDef> _availableCoupons = [
  CouponDef(code: 'SAVE50',     type: CouponType.flat,    value: 50,  minOrder: 399),
  CouponDef(code: 'FIRST20',    type: CouponType.percent, value: 20,  minOrder: 199),
  CouponDef(code: 'WELCOME100', type: CouponType.flat,    value: 100, minOrder: 499),
];
// ─────────────────────────────────────────────────────────────────────────────

class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>>? cartItems;
  final VoidCallback? toggleTheme;

  const CartPage({super.key, this.cartItems, this.toggleTheme});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  TextEditingController couponController = TextEditingController();

  // ─── Coupon state (replaces old couponApplied + discount) ────────────────
  CouponDef? _appliedCoupon;
  String _couponError = "";

  int get _discountAmount {
    if (_appliedCoupon == null) return 0;
    final total = getTotal().toDouble();
    if (total < _appliedCoupon!.minOrder) return 0;
    if (_appliedCoupon!.type == CouponType.flat) {
      return _appliedCoupon!.value.toInt();
    } else {
      return (total * _appliedCoupon!.value / 100).floor();
    }
  }

  void _applyCoupon() {
    final code = couponController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _couponError = "Please enter a coupon code");
      return;
    }

    CouponDef? found;
    try {
      found = _availableCoupons.firstWhere((c) => c.code == code);
    } catch (_) {
      found = null;
    }

    if (found == null) {
      setState(() {
        _couponError = "Invalid coupon code";
        _appliedCoupon = null;
      });
      return;
    }

    if (getTotal() < found.minOrder) {
      setState(() {
        _couponError =
            "Minimum order ₹${found!.minOrder.toInt()} required for ${found.code}";
        _appliedCoupon = null;
      });
      return;
    }

    setState(() {
      _appliedCoupon = found;
      _couponError = "";
    });
    FocusScope.of(context).unfocus();
  }

  void _removeCoupon() {
    setState(() {
      _appliedCoupon = null;
      _couponError = "";
      couponController.clear();
    });
  }
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      globalCartItems = widget.cartItems!;
    }
  }

  int getTotal() {
    return globalCartItems.fold(0, (sum, item) => sum + ((item["price"] as int) * (item["qty"] as int)));
  }

  int getFinalTotal() {
    int total = getTotal() + 3;
    return total - _discountAmount;
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: background,
      extendBody: true, 
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                      ...globalCartItems.map((item) => _buildCartItemCard(item, isDark, cardColor, textColor, subTextColor)),
                      const SizedBox(height: 16),
                      _buildCouponSection(isDark, cardColor, textColor, subTextColor),
                      const SizedBox(height: 24),
                      _buildBillDetails(isDark, cardColor, textColor, subTextColor),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 58),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CheckoutPage(
                              cafeteriaName: globalCartItems.first["cafeteriaName"]?.toString(),
                              cafeId: globalCartItems.first["cafeId"]?.toString(),
                              pickupLocation: globalCartItems.first["location"]?.toString(),
                            ),
                          ),
                        ),
                        child: const Text("Continue to Checkout", style: TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ],
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
            color: Colors.black.withOpacity(isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
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
                      MaterialPageRoute(builder: (_) => CafeteriaPage(toggleTheme: widget.toggleTheme ?? () {})),
                      (route) => false,
                    );
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : primaryBlue, size: 20),
                ),
              ),
              const SizedBox(width: 44),
            ],
          ),
          Text(
            "My Cart",
            style: TextStyle(fontSize: 18, fontFamily: 'Nunito', fontWeight: FontWeight.w900, color: textColor, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(Map<String, dynamic> item, bool isDark, Color cardColor, Color textColor, Color subTextColor) {
    final imageValue = item["image"]?.toString() ?? '';
    Widget imageWidget;
    if (imageValue.isEmpty) {
      imageWidget = Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      );
    } else if (imageValue.startsWith('http') || imageValue.startsWith('data:')) {
      imageWidget = Image.network(imageValue, height: 80, width: 80, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      ));
    } else {
      imageWidget = Image.asset(imageValue, height: 80, width: 80, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(
        color: Colors.grey.shade200,
        height: 80,
        width: 80,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 32),
      ));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: imageWidget),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["name"],
                  style: TextStyle(fontFamily: 'Nunito', color: textColor, fontWeight: FontWeight.w900, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text("₹${item["price"]}", style: TextStyle(fontFamily: 'Inter', color: subTextColor, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Container(
                  height: 32,
                  width: 100,
                  decoration: BoxDecoration(
                    color: primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryBlue.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InkWell(onTap: () => updateQty(item, -1), child: Icon(Icons.remove, size: 16, color: primaryBlue)),
                      Text("${item["qty"]}", style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: primaryBlue)),
                      InkWell(onTap: () => updateQty(item, 1), child: Icon(Icons.add, size: 16, color: primaryBlue)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
            ),
            onPressed: () => setState(() {
              for (int i = 0; i < item["qty"]; i++) {
                CartModel.remove(item["id"]);
              }
              globalCartItems.remove(item);
            }),
          )
        ],
      ),
    );
  }

  Widget _buildCouponSection(bool isDark, Color cardColor, Color textColor, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Applied state ──────────────────────────────────────────────
          if (_appliedCoupon != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _appliedCoupon!.code,
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontFamily: 'Nunito'),
                        ),
                        Text(
                          "You save ₹$_discountAmount",
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontFamily: 'Inter'),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _removeCoupon,
                    child: const Icon(Icons.close, color: Colors.green, size: 20),
                  ),
                ],
              ),
            )

          // ── Input state ────────────────────────────────────────────────
          else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.local_offer_outlined, color: primaryBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: couponController,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: textColor, fontFamily: 'Inter', fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "Enter coupon code",
                      hintStyle: TextStyle(color: subTextColor, fontFamily: 'Inter', fontWeight: FontWeight.w400),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _applyCoupon(),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _applyCoupon,
                  child: const Text("Apply", style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            // Error
            if (_couponError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _couponError,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Inter'),
                ),
              ),
            ],

            // Available coupons list
            const SizedBox(height: 12),
            Text(
              "Available Coupons",
              style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 8),
            ..._availableCoupons.map((c) {
              final eligible = getTotal() >= c.minOrder;
              return GestureDetector(
                onTap: eligible
                    ? () {
                        couponController.text = c.code;
                        _applyCoupon();
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: eligible ? primaryBlue.withOpacity(0.35) : Colors.grey.withOpacity(0.2),
                    ),
                    color: eligible ? primaryBlue.withOpacity(0.05) : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: eligible ? primaryBlue.withOpacity(0.12) : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          c.code,
                          style: TextStyle(
                            color: eligible ? primaryBlue : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          c.description,
                          style: TextStyle(
                            color: eligible ? textColor : Colors.grey,
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      Text(
                        eligible
                            ? "TAP TO APPLY"
                            : c.minOrder > 0
                                ? "Need ₹${c.minOrder.toInt()}+"
                                : "Not eligible",
                        style: TextStyle(
                          color: eligible ? primaryBlue : Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildBillDetails(bool isDark, Color cardColor, Color textColor, Color subTextColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Bill Details", style: TextStyle(fontFamily: 'Nunito', color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          _billRow("Item Total", getTotal(), subTextColor, textColor),
          _billRow("Platform Fee", 3, subTextColor, textColor),
          if (_appliedCoupon != null) _billRow("Discount", -_discountAmount, Colors.green, Colors.green),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: isDark ? Colors.white12 : Colors.grey.shade200, thickness: 1.5),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total Pay", style: TextStyle(fontFamily: 'Nunito', color: textColor, fontSize: 16, fontWeight: FontWeight.w900)),
              Text("₹${getFinalTotal()}", style: TextStyle(fontFamily: 'Inter', color: textColor, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _billRow(String title, int amount, Color titleColor, Color amountColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontFamily: 'Inter', color: titleColor, fontWeight: FontWeight.w500, fontSize: 14)),
          Text("₹$amount", style: TextStyle(fontFamily: 'Inter', color: amountColor, fontWeight: FontWeight.w700, fontSize: 14)),
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
          const SizedBox(height: 20),
          Text(
            "Your cart is empty",
            style: TextStyle(fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.bold, color: subTextColor),
          ),
          const SizedBox(height: 8),
          Text(
            "Add items from cafeterias to see them here.",
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: subTextColor.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}