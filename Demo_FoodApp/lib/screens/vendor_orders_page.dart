import 'package:flutter/material.dart';

class VendorOrdersPage extends StatefulWidget {
  @override
  State<VendorOrdersPage> createState() => _VendorOrdersPageState();
}

class _VendorOrdersPageState extends State<VendorOrdersPage> {
  String selectedFilter = "All";
  int navIndex = 1; // 👈 Orders selected by default

  List<Map<String, dynamic>> orders = [
    {
      "id": "ORD123456",
      "customer": "Student #12345",
      "items": ["Pizza", "Burger"],
      "total": 271,
      "status": "Pending",
      "time": "5 min ago"
    },
    {
      "id": "ORD123457",
      "customer": "Student #12346",
      "items": ["Pepperoni Pizza"],
      "total": 189,
      "status": "Preparing",
      "time": "12 min ago"
    },
    {
      "id": "ORD123458",
      "customer": "Student #12347",
      "items": ["Salad", "Smoothie"],
      "total": 159,
      "status": "Ready",
      "time": "15 min ago"
    },
    {
      "id": "ORD123459",
      "customer": "Student #12348",
      "items": ["Cake"],
      "total": 69,
      "status": "Completed",
      "time": "1 hour ago"
    },
  ];

  List<String> filters = ["All", "Pending", "Preparing", "Ready", "Completed"];

  @override
  Widget build(BuildContext context) {
    final filteredOrders = selectedFilter == "All"
        ? orders
        : orders.where((o) => o["status"] == selectedFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Orders"),
        backgroundColor: Colors.blue,
      ),

      /// 🔽 BODY
      body: Column(
        children: [

          /// 🔥 FILTER CHIPS
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              children: filters.map((f) {
                final isSelected = f == selectedFilter;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => selectedFilter = f);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          /// 📦 ORDER CARDS
          Expanded(
            child: ListView.builder(
              itemCount: filteredOrders.length,
              itemBuilder: (context, index) {
                final order = filteredOrders[index];
                return _orderCard(order);
              },
            ),
          ),
        ],
      ),

      /// 🔻 BOTTOM NAVIGATION (🔥 ADDED)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,

        onTap: (index) {
          setState(() => navIndex = index);

          /// 👉 TEMP NAVIGATION (you can replace later)
          if (index == 0) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text("Dashboard")));
          } else if (index == 1) {
            // already here
          } else if (index == 2) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text("Menu Page")));
          } else if (index == 3) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text("Profile Page")));
          }
        },

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: "Dashboard",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: "Orders",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: "Menu",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }

  /// 🔥 ORDER CARD
  Widget _orderCard(Map<String, dynamic> order) {
    Color statusColor;

    switch (order["status"]) {
      case "Pending":
        statusColor = Colors.orange;
        break;
      case "Preparing":
        statusColor = Colors.blue;
        break;
      case "Ready":
        statusColor = Colors.green;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order["id"],
                  style: const TextStyle(fontWeight: FontWeight.bold)),

              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order["status"],
                  style: TextStyle(color: statusColor),
                ),
              )
            ],
          ),

          const SizedBox(height: 8),

          Text("👤 ${order["customer"]}"),
          Text("🍽 ${order["items"].join(", ")}"),

          const SizedBox(height: 6),

          Text("💰 ₹${order["total"]}"),
          Text("⏱ ${order["time"]}"),

          const SizedBox(height: 12),

          _buildActions(order),
        ],
      ),
    );
  }

  /// 🎯 BUTTON LOGIC
  Widget _buildActions(Map<String, dynamic> order) {
    switch (order["status"]) {
      case "Pending":
        return Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green),
                onPressed: () {
                  setState(() {
                    order["status"] = "Preparing";
                  });
                },
                child: const Text("Accept"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red),
                onPressed: () {
                  setState(() {
                    orders.remove(order);
                  });
                },
                child: const Text("Reject"),
              ),
            ),
          ],
        );

      case "Preparing":
        return ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          onPressed: () {
            setState(() {
              order["status"] = "Ready";
            });
          },
          child: const Text("Mark Ready"),
        );

      case "Ready":
        return ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: () {
            setState(() {
              order["status"] = "Completed";
            });
          },
          child: const Text("Complete"),
        );

      default:
        return const Text(
          "Order Completed",
          style: TextStyle(color: Colors.grey),
        );
    }
  }
}
