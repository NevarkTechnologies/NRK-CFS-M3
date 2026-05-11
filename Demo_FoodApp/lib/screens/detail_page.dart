import 'package:flutter/material.dart';
import '../model/favorite_model.dart';
import 'checkout_page.dart';
import 'cart_page.dart';
import 'cafeteria_page.dart';
import 'profile_page.dart';
import '../services/api_service.dart';
import '../services/session.dart';

class OrderItem {
  final String name;
  final double price;
  final int quantity;
  OrderItem({required this.name, required this.price, required this.quantity});
}

class DetailPage extends StatefulWidget {
  final String title;

  const DetailPage({super.key, required this.title});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool isEdit = false;
  bool isSaving = false;
  Map<String, int> cartItems = {};
  bool isOrderLoading = false;
  String? orderLoadingError;
  List<Map<String, dynamic>> orders = [];

  late final TextEditingController name;
  late final TextEditingController email;

  late final TextEditingController street1;
  late final TextEditingController street2;
  late final TextEditingController district;
  late final TextEditingController state;
  late final TextEditingController country;
  late final TextEditingController pincode;

  late final TextEditingController card;

  final Color primary = const Color(0xFF0F4CFF);

  @override
  void initState() {
    super.initState();
    final address = AppSession.address;
    name = TextEditingController(text: AppSession.name);
    email = TextEditingController(text: AppSession.email);
    street1 = TextEditingController(text: address["street1"]?.toString() ?? "");
    street2 = TextEditingController(text: address["street2"]?.toString() ?? "");
    district = TextEditingController(text: address["district"]?.toString() ?? "");
    state = TextEditingController(text: address["state"]?.toString() ?? "");
    country = TextEditingController(text: address["country"]?.toString() ?? "India");
    pincode = TextEditingController(text: address["pincode"]?.toString() ?? "");
    card = TextEditingController(text: AppSession.paymentLabel);

    if (widget.title == "Order Details") {
      _loadUserOrders();
    }
  }

  Future<void> _loadUserOrders() async {
    setState(() {
      isOrderLoading = true;
      orderLoadingError = null;
    });

    try {
      final data = await ApiService.getOrders(customerEmail: AppSession.email);
      if (!mounted) return;
      setState(() {
        orders = data;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        orderLoadingError = error.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (!mounted) return;
      setState(() {
        isOrderLoading = false;
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    street1.dispose();
    street2.dispose();
    district.dispose();
    state.dispose();
    country.dispose();
    pincode.dispose();
    card.dispose();
    super.dispose();
  }

  void _handleReorder(BuildContext context, List<OrderItem> items, String cafeteriaName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          items: items,
          cafeteriaName: cafeteriaName,
          isReorder: true,
        ),
      ),
    );
  }

  Future<void> _handleEditButton() async {
    if (!isEdit) {
      setState(() => isEdit = true);
      return;
    }

    if (AppSession.userId.isEmpty) {
      setState(() => isEdit = false);
      return;
    }

    setState(() => isSaving = true);
    try {
      final updated = await ApiService.updateUser(AppSession.userId, {
        "name": name.text.trim(),
        "email": email.text.trim(),
        "address": {
          "street1": street1.text.trim(),
          "street2": street2.text.trim(),
          "district": district.text.trim(),
          "state": state.text.trim(),
          "country": country.text.trim(),
          "pincode": pincode.text.trim(),
        },
        "paymentLabel": card.text.trim(),
      });
      AppSession.setUser(updated);
      if (!mounted) return;
      setState(() => isEdit = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated")),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst("Exception: ", "")),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                                blurRadius: 25,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            child: _buildContent(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_hasEditableContent())
                        SizedBox(
                          width: 280,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: isSaving ? null : _handleEditButton,
                            child: Text(
                              isSaving ? "Saving..." : (isEdit ? "Save Changes" : "Edit"),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 2, 
        isDark: isDark,
        toggleTheme: () {},
      ),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (widget.title) {
      case "Personal Info":
        return Column(
          children: [
            _field("Name", name),
            const SizedBox(height: 16),
            _field("Email", email),
          ],
        );

      case "Saved Addresses":
        return Column(
          children: [
            _field("Street 1", street1),
            const SizedBox(height: 16),
            _field("Street 2", street2),
            const SizedBox(height: 16),
            _field("District", district),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field("State", state)),
                const SizedBox(width: 12),
                Expanded(child: _field("Country", country)),
              ],
            ),
            const SizedBox(height: 16),
            _field("Pincode", pincode),
          ],
        );

      case "Payment Methods":
        return Column(
          children: [
            const Icon(Icons.credit_card, size: 60, color: Colors.grey),
            const SizedBox(height: 20),
            _field("Card Number", card),
          ],
        );

      case "Favorite Items":
        final favorites = FavoriteModel.favorites;
        if (favorites.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                "No favorite items",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: favorites.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400, 
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 104, // Added more breathing room for the card
              ),
              itemBuilder: (context, index) {
                final item = favorites[index];
                final cartIndex = globalCartItems.indexWhere((e) => e["name"] == item["name"]);
                final qty = cartIndex != -1 ? globalCartItems[cartIndex]["qty"] : 0;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white, // Matched home page elevated card color
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), // Matched home page shadow
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Builder(
                          builder: (context) {
                            final imageUrl = item["image"]?.toString().trim() ?? '';
                            if (imageUrl.isEmpty) {
                              return const SizedBox(width: 65, height: 65);
                            }
                            return Image.network(
                              imageUrl,
                              width: 65,
                              height: 65,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(width: 65, height: 65),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item["name"],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item["category"],
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "₹ ${item["price"]}",
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      qty == 0
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  final existingIndex = globalCartItems.indexWhere((e) => e["name"] == item["name"]);
                                  if (existingIndex != -1) {
                                    globalCartItems[existingIndex]["qty"] += 1;
                                  } else {
                                    globalCartItems.add({...item, "qty": 1});
                                  }
                                });
                              },
                              child: const Text("ADD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: primary.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    constraints: const BoxConstraints(),
                                    icon: Icon(Icons.remove, color: primary, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        final index = globalCartItems.indexWhere((e) => e["name"] == item["name"]);
                                        if (index != -1) {
                                          if (globalCartItems[index]["qty"] > 1) {
                                            globalCartItems[index]["qty"] -= 1;
                                          } else {
                                            globalCartItems.removeAt(index);
                                          }
                                        }
                                      });
                                    },
                                  ),
                                  Text(qty.toString(), style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                                  IconButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    constraints: const BoxConstraints(),
                                    icon: Icon(Icons.add, color: primary, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        final index = globalCartItems.indexWhere((e) => e["name"] == item["name"]);
                                        if (index != -1) {
                                          globalCartItems[index]["qty"] += 1;
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )
                    ],
                  ),
                );
              },
            );
          },
        );

      case "Order Details":
        if (isOrderLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (orderLoadingError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Text(
                orderLoadingError!,
                style: TextStyle(color: isDark ? Colors.redAccent : Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (orders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Text(
                'No orders found yet. Place an order from the cafeteria to see order history here.',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loadUserOrders,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh orders'),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
            ...orders.map((order) => _buildOrderCardFromApi(order, isDark)).toList(),
          ],
        );

      default:
        return const Center(child: Text("No Data"));
    }
  }

  Widget _field(String label, TextEditingController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      enabled: isEdit,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _orderCard({
    required String imageUrl,
    required String cafeteriaName,
    required String pickupLocation,
    required String orderId,
    required String orderDate,
    required String pickupTime,
    required String itemsSummary,
    required String total,
    required List<OrderItem> itemsList,
    required double itemTotalSum,
    required double tax,
    required double billTotal,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white : Colors.black;
    final greyText = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(imageUrl, width: 70, height: 70, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cafeteriaName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                    const SizedBox(height: 4),
                    Text(pickupLocation, style: TextStyle(color: greyText, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text("ORDER #$orderId | $orderDate", style: TextStyle(color: greyText, fontSize: 12)),
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        GestureDetector(
                          onTap: () => _openDetailsSidebar(context, imageUrl, orderId, cafeteriaName, pickupLocation, orderDate, pickupTime, itemsList, itemTotalSum, tax, billTotal, isDark),
                          child: Text("VIEW DETAILS", style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Ready for Pickup", style: TextStyle(color: greyText, fontSize: 13)),
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade300),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(itemsSummary, style: TextStyle(fontSize: 14, color: textColor))),
              const SizedBox(width: 16),
              Text("Total Paid: $total", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            onPressed: () => _handleReorder(context, itemsList, cafeteriaName),
            child: const Text("REORDER", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCardFromApi(Map<String, dynamic> order, bool isDark) {
    final itemsList = ((order['items'] as List<dynamic>?) ?? []).map((item) {
      final itemMap = Map<String, dynamic>.from(item as Map);
      return OrderItem(
        name: itemMap['name']?.toString() ?? '',
        price: double.tryParse(itemMap['price']?.toString() ?? '0') ?? 0,
        quantity: int.tryParse(itemMap['qty']?.toString() ?? itemMap['quantity']?.toString() ?? '1') ?? 1,
      );
    }).toList();

    final createdAt = DateTime.tryParse(order['createdAt']?.toString() ?? '') ?? DateTime.now();
    final orderDate = '${createdAt.day}/${createdAt.month}/${createdAt.year}, ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    final pickupTime = '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    final itemsSummary = itemsList.map((item) => '${item.name} x ${item.quantity}').join(', ');
    final double itemTotalSum = itemsList.fold(0.0, (sum, item) => sum + item.price * item.quantity);
    final double tax = itemTotalSum * 0.05;
    final double billTotal = itemTotalSum + tax;
    final status = order['status']?.toString() ?? 'Pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/cafes/cafe1.jpg', width: 70, height: 70, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order['cafeteriaName']?.toString() ?? 'Cafeteria',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 4),
                    Text(order['location']?.toString() ?? 'Pickup counter',
                        style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('ORDER #${order['orderId']} • $orderDate',
                        style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 12)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildOrderStatusChip(status),
                        const SizedBox(width: 12),
                        Text(status, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade300),
          ),
          Text(itemsSummary, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total: ₹${billTotal.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _openDetailsSidebar(
                  context,
                  'assets/cafes/cafe1.jpg',
                  order['orderId']?.toString() ?? '',
                  order['cafeteriaName']?.toString() ?? 'Cafeteria',
                  order['location']?.toString() ?? 'Pickup counter',
                  orderDate,
                  pickupTime,
                  itemsList,
                  itemTotalSum,
                  tax,
                  billTotal,
                  isDark,
                  status,
                ),
                child: const Text('VIEW DETAILS'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusChip(String status) {
    Color color;
    switch (status) {
      case 'Pending':
        color = Colors.orange;
        break;
      case 'Preparing':
        color = const Color(0xFF0F4CFF);
        break;
      case 'Ready':
        color = Colors.teal;
        break;
      case 'Completed':
        color = Colors.green;
        break;
      case 'Rejected':
        color = Colors.redAccent;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(12)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _openDetailsSidebar(BuildContext context, String imageUrl, String orderId, String cafeteriaName, String pickupLocation, String orderDate, String pickupTime, List<OrderItem> itemsList, double itemTotalSum, double tax, double billTotal, bool isDark, [String status = 'Pending']) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Order Details",
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 10,
            child: Container(
              width: 450,
              height: double.infinity,
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              child: _buildSidebarContent(context, imageUrl, orderId, cafeteriaName, pickupLocation, orderDate, pickupTime, itemsList, itemTotalSum, tax, billTotal, isDark, status),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildSidebarContent(BuildContext context, String imageUrl, String orderId, String cafeteriaName, String pickupLocation, String orderDate, String pickupTime, List<OrderItem> itemsList, double itemTotalSum, double tax, double billTotal, bool isDark, String status) {
    final textColor = isDark ? Colors.white : Colors.black;
    final subText = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Text("Order #$orderId", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset(imageUrl, width: 120, height: 120, fit: BoxFit.cover)),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cafeteriaName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                  Text(pickupLocation, style: TextStyle(color: subText, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        color: status == 'Pending'
                            ? Colors.orange
                            : status == 'Preparing'
                                ? primary
                                : status == 'Ready'
                                    ? Colors.teal
                                    : status == 'Completed'
                                        ? Colors.green
                                        : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(status,
                          style: TextStyle(
                              color: status == 'Pending'
                                  ? Colors.orange
                                  : status == 'Preparing'
                                      ? primary
                                      : status == 'Ready'
                                          ? Colors.teal
                                          : status == 'Completed'
                                              ? Colors.green
                                              : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 24),
          Text("Order Progress", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 16),
          _progress("Payment Confirmed", true, textColor),
          _progress("Preparing Food", status == 'Preparing' || status == 'Ready' || status == 'Completed', textColor),
          _progress("Ready to Pickup", status == 'Ready' || status == 'Completed', textColor, isLast: true),

          const SizedBox(height: 24),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 24),
          Text("Pickup Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
          const SizedBox(height: 12),
          Text("John Doe (Employee ID: 12345)", style: TextStyle(color: subText, fontSize: 14)),
          const SizedBox(height: 12),
          Text("Pickup By: $pickupTime, $orderDate", style: TextStyle(color: subText, fontSize: 13)),
          const SizedBox(height: 24),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 24),
          Text("${itemsList.length} ITEMS", style: TextStyle(color: subText, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Column(children: itemsList.map((item) => _billRow("${item.name} x ${item.quantity}", "₹ ${item.price.toStringAsFixed(2)}", textColor)).toList()),
          const SizedBox(height: 24),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 20),
          _billRow("Item Total", "₹ ${itemTotalSum.toStringAsFixed(2)}", textColor, isBold: true),
          const SizedBox(height: 12),
          _billRow("Taxes (5% GST)", "₹ ${tax.toStringAsFixed(2)}", subText),
          const SizedBox(height: 24),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Paid Via UPI", style: TextStyle(color: subText, fontSize: 14)),
              Row(
                children: [
                  Text("BILL TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                  const SizedBox(width: 16),
                  Text("₹ ${billTotal.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                ],
              )
            ],
          ),
        ],
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
        )
      ],
    );
  }

  Widget _billRow(String title, String amount, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: color, fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(amount, style: TextStyle(color: color, fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }

  bool _hasEditableContent() {
    return widget.title == "Personal Info" || widget.title == "Saved Addresses" || widget.title == "Payment Methods";
  }
}
