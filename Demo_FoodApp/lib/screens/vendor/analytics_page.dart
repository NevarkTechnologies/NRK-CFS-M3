import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import 'vendor_data.dart';
import 'vendor_page_wrapper.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  int totalOrders = 0;
  int revenue = 0;
  int uniqueCustomers = 0;
  List<double> weeklyRevenue = [];
  List<int> weeklyOrders = [];
  List<Map<String, dynamic>> topItems = [];

  @override
  void initState() {
    super.initState();
    loadAnalytics();
  }

  Future<void> loadAnalytics() async {
    try {
      final data = await ApiService.getVendorDashboard(AppSession.vendorId);
      if (!mounted) return;

      final orders = ((data['recentOrders'] as List<dynamic>?) ?? []).map((order) => Map<String, dynamic>.from(order as Map)).toList();
      final customers = <String>{};
      final itemCounts = <String, Map<String, dynamic>>{};
      final revenuePerDay = <String, double>{};
      final ordersPerDay = <String, int>{};

      for (final order in orders) {
        final customer = order['customerName']?.toString().trim();
        if (customer != null && customer.isNotEmpty) {
          customers.add(customer);
        }

        final createdAt = order['createdAt'];
        DateTime date;
        try {
          date = DateTime.parse(createdAt?.toString() ?? '');
        } catch (_) {
          date = DateTime.now();
        }
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        revenuePerDay[key] = (revenuePerDay[key] ?? 0) + (order['total'] is num ? (order['total'] as num).toDouble() : double.tryParse(order['total']?.toString() ?? '0') ?? 0);
        ordersPerDay[key] = (ordersPerDay[key] ?? 0) + 1;

        final items = (order['items'] as List<dynamic>?) ?? [];
        for (final itemRaw in items) {
          final item = Map<String, dynamic>.from(itemRaw as Map);
          final itemName = item['name']?.toString() ?? 'Unknown';
          final count = item['qty'] is num ? (item['qty'] as num).toInt() : int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          final price = item['price'] is num ? (item['price'] as num).toDouble() : double.tryParse(item['price']?.toString() ?? '0') ?? 0;
          itemCounts[itemName] ??= {'name': itemName, 'orders': 0, 'revenue': 0.0};
          itemCounts[itemName]!['orders'] = (itemCounts[itemName]!['orders'] as int) + count;
          itemCounts[itemName]!['revenue'] = (itemCounts[itemName]!['revenue'] as double) + price * count;
        }
      }

      final sortedItems = itemCounts.values.toList()..sort((a, b) => (b['orders'] as int).compareTo(a['orders'] as int));
      final last7Days = List.generate(7, (index) {
        final day = DateTime.now().subtract(Duration(days: 6 - index));
        return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      });

      setState(() {
        totalOrders = (data['totalOrders'] as num?)?.toInt() ?? 0;
        revenue = (data['revenue'] as num?)?.toInt() ?? 0;
        uniqueCustomers = customers.length;
        weeklyRevenue = last7Days.map((key) => revenuePerDay[key] ?? 0).toList();
        weeklyOrders = last7Days.map((key) => ordersPerDay[key] ?? 0).toList();
        topItems = sortedItems.take(5).map((item) => {
              'name': item['name'],
              'orders': item['orders'],
              'revenue': item['revenue'],
            }).toList();
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  String formatRupees(int amount) {
    return '₹${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    final averageOrderValue = totalOrders > 0 ? (revenue / totalOrders).round() : 0;

    return VendorPageWrapper(
      pageTitle: 'Analytics',
      selectedMenuIndex: 2,
      toggleTheme: () {},
      child: Scaffold(
        backgroundColor: bgColor,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double availableWidth = constraints.maxWidth;
              bool isMobile = MediaQuery.of(context).size.width < 850;
              double cardWidth = isMobile ? (availableWidth - 16) / 2 : (availableWidth - 48) / 4;
              double graphWidth = isMobile ? availableWidth : (availableWidth - 16) / 2;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Track ${VendorData.displayName}'s performance",
                      style: TextStyle(fontFamily: 'Inter', color: subText, fontSize: 14),
                    ).animate().fade(duration: 300.ms),
                    const SizedBox(height: 20),
                    if (isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          InteractiveScale(onTap: () {}, child: buildCard(formatRupees(revenue), 'Revenue', Icons.currency_rupee, Colors.green, cardColor, textColor, subText, isDark, cardWidth)),
                          InteractiveScale(onTap: () {}, child: buildCard(totalOrders.toString(), 'Orders', Icons.shopping_bag, primaryBlue, cardColor, textColor, subText, isDark, cardWidth)),
                          InteractiveScale(onTap: () {}, child: buildCard(formatRupees(averageOrderValue), 'Avg Order', Icons.show_chart, Colors.orange, cardColor, textColor, subText, isDark, cardWidth)),
                          InteractiveScale(onTap: () {}, child: buildCard(uniqueCustomers.toString(), 'Customers', Icons.people, Colors.teal, cardColor, textColor, subText, isDark, cardWidth)),
                        ],
                      ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(width: graphWidth, child: InteractiveScale(onTap: () {}, child: buildRevenueGraph(cardColor, textColor, isDark))),
                        SizedBox(width: graphWidth, child: InteractiveScale(onTap: () {}, child: buildOrdersGraph(cardColor, textColor, isDark))),
                      ],
                    ).animate().fade(delay: 200.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 20),
                    InteractiveScale(onTap: () {}, child: buildTopItems(cardColor, textColor, subText, isDark)).animate().fade(delay: 400.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget buildCard(String value, String title, IconData icon, Color color, Color card, Color text, Color sub, bool isDark, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Color.fromRGBO(color.red, color.green, color.blue, 0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(height: 16),
          Text(value, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 22, color: text)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: sub), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget buildRevenueGraph(Color card, Color text, bool isDark) {
    final maxValue = weeklyRevenue.isNotEmpty ? weeklyRevenue.reduce((a, b) => a > b ? a : b) : 1;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly Revenue', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: text)),
          const SizedBox(height: 20),
          if (weeklyRevenue.every((value) => value == 0))
            Text('No revenue data yet', style: TextStyle(color: Color.fromRGBO(text.red, text.green, text.blue, 0.7), fontFamily: 'Inter'))
          else
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: weeklyRevenue.map((value) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: maxValue > 0 ? (value / maxValue) * 140 : 0,
                      decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(6)),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildOrdersGraph(Color card, Color text, bool isDark) {
    final maxValue = weeklyOrders.isNotEmpty ? weeklyOrders.reduce((a, b) => a > b ? a : b) : 1;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly Orders', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: text)),
          const SizedBox(height: 20),
          if (weeklyOrders.every((value) => value == 0))
            Text('No order data yet', style: TextStyle(color: Color.fromRGBO(text.red, text.green, text.blue, 0.7), fontFamily: 'Inter'))
          else
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: weeklyOrders.map((value) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: maxValue > 0 ? (value / maxValue) * 140 : 0,
                      decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(6)),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildTopItems(Color card, Color text, Color sub, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Selling Items', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: text)),
          const SizedBox(height: 16),
          if (topItems.isEmpty)
            Text('No sales data yet', style: TextStyle(color: sub, fontFamily: 'Inter'))
          else
            Column(
              children: topItems.map((item) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name'].toString(), style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold, fontSize: 16, color: text)),
                  subtitle: Text('${item['orders']} sold', style: TextStyle(fontFamily: 'Inter', color: sub)),
                  trailing: Text(formatRupees((item['revenue'] as double).round()), style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: text)),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class InteractiveScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const InteractiveScale({super.key, required this.child, required this.onTap});
  @override
  State<InteractiveScale> createState() => _InteractiveScaleState();
}

class _InteractiveScaleState extends State<InteractiveScale> {
  bool isHovered = false, isPressed = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isPressed ? 0.95 : (isHovered ? 1.02 : 1.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(focusColor: Colors.transparent, hoverColor: Colors.transparent, highlightColor: Colors.transparent, splashColor: Colors.transparent, onHover: (h) => setState(() => isHovered = h), onHighlightChanged: (h) => setState(() => isPressed = h), onTap: widget.onTap, child: widget.child),
      ),
    );
  }
}
