import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import 'vendor_page_wrapper.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  String? loadError;

  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();
    loadOrders();
  }

  Future<void> loadOrders() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final data = await ApiService.getOrders(cafeId: AppSession.cafe?["_id"]?.toString());
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
      "customer": order["customerName"] ?? "Customer",
      "status": order["status"] ?? "Pending",
      "total": order["total"] ?? 0,
      "items": order["items"] ?? [],
      "location": order["location"] ?? "Pickup counter",
      "cafeteriaName": order["cafeteriaName"] ?? "Cafeteria",
    };
  }

  void sortOrders() {
    orders.sort((a, b) {
      if (a["status"] == "Completed") return 1;
      if (b["status"] == "Completed") return -1;
      return 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    sortOrders();
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return VendorPageWrapper(
      pageTitle: "Order Management",
      selectedMenuIndex: 1,
      toggleTheme: () {},
      child: Scaffold(
        backgroundColor: bgColor,
        body: RefreshIndicator(
          onRefresh: loadOrders,
          child: _buildBody(cardColor, textColor, subText, isDark),
        ),
      ),
    );
  }

  Widget _buildBody(Color cardColor, Color textColor, Color subText, bool isDark) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: primaryBlue));
    }

    if (loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text("Could not load orders", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(loadError!, style: TextStyle(color: subText)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: loadOrders, child: const Text("Retry")),
        ],
      );
    }

    if (orders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.shopping_bag_outlined, size: 72, color: subText),
          const SizedBox(height: 12),
          Center(child: Text("No orders yet", style: TextStyle(color: subText, fontWeight: FontWeight.w600))),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        return buildOrderCard(orders[index], cardColor, textColor, subText, isDark)
            .animate()
            .fade(delay: (100 * index).ms)
            .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic);
      },
    );
  }

  Widget buildOrderCard(Map<String, dynamic> order, Color cardColor,
      Color textColor, Color subText, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Order #${order["id"]}",
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: textColor)),
              statusChip(order["status"]),
            ],
          ),
          const SizedBox(height: 8),
          Text("Customer: ${order["customer"]}",
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  color: subText,
                  fontSize: 14)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              thickness: 1.5,
            ),
          ),
          Column(
            children: order["items"].map<Widget>((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                        child: Text("${item["name"]}  x${item["qty"]}",
                            style: TextStyle(
                                fontFamily: 'Inter',
                                color: textColor,
                                fontWeight: FontWeight.w500))),
                    Text("₹${item["price"]}",
                        style: TextStyle(
                            fontFamily: 'Nunito',
                            color: textColor,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 18, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(order["location"],
                      style: TextStyle(
                          fontFamily: 'Inter',
                          color: subText,
                          fontWeight: FontWeight.w500))),
            ],
          ),
          const SizedBox(height: 20),
          buildButtons(order),
        ],
      ),
    );
  }

  /// ✅ UPDATED BUTTON LOGIC
  Widget buildButtons(Map<String, dynamic> order) {
    String status = order["status"];

    if (status == "Pending") {
      return Row(
        children: [
          Expanded(
              child: _actionBtn("Accept", Colors.green,
                  () => _setOrderStatus(order, "Preparing"))),
          const SizedBox(width: 12),
          Expanded(
            child: _actionBtn("Reject", Colors.redAccent, () {
              bool undoPressed = false;
              setState(() {
                order["status"] = "Rejected";
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("Order Rejected"),
                  action: SnackBarAction(
                    label: "UNDO",
                    onPressed: () {
                      undoPressed = true;
                      setState(() {
                        order["status"] = "Pending";
                      });
                    },
                  ),
                ),
              );
              ApiService.updateOrderStatus(order["orderId"] ?? order["id"], "Rejected");
              /// AUTO REMOVE
              Future.delayed(const Duration(seconds: 5), () {
                if (!undoPressed && mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  setState(() {
                    orders.remove(order);
                  });
                }
              });
            }),
          ),
        ],
      );
    }

    if (status == "Preparing") {
      return SizedBox(
          width: double.infinity,
          child: _actionBtn("Mark as Ready", const Color(0xFF0F4CFF),
              () => _setOrderStatus(order, "Ready")));
    }

    if (status == "Ready") {
      return SizedBox(
          width: double.infinity,
          child: _actionBtn("Mark as Picked Up", Colors.teal,
              () => _setOrderStatus(order, "Completed")));
    }

    if (status == "Completed") {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16)),
        child: const Center(
            child: Text("Order Completed successfully",
                style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.green,
                    fontWeight: FontWeight.bold))),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.bold,
              fontSize: 15)),
    );
  }

  Future<void> _setOrderStatus(Map<String, dynamic> order, String status) async {
    final previousStatus = order["status"];
    setState(() => order["status"] = status);

    try {
      await ApiService.updateOrderStatus(order["orderId"] ?? order["id"], status);
      await loadOrders();
    } catch (error) {
      if (!mounted) return;
      setState(() => order["status"] = previousStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst("Exception: ", "")),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget statusChip(String status) {
    Color color;
    switch (status) {
      case "Pending":
        color = Colors.orange;
        break;
      case "Preparing":
        color = const Color(0xFF0F4CFF);
        break;
      case "Ready":
        color = Colors.teal;
        break;
      case "Rejected":
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              fontFamily: 'Inter',
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );
  }
}
