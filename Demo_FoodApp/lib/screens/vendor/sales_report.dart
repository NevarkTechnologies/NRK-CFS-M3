import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_service.dart';
import '../../services/session.dart';
import '../../utils/csv_export.dart';
import '../../utils/excel_export.dart';        // ← NEW
import 'vendor_data.dart';
import 'vendor_page_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The rest of the state variables and logic are unchanged.
// Only _downloadExcelReport() is new, and the toolbar buttons are updated.
// ─────────────────────────────────────────────────────────────────────────────

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  List<Map<String, dynamic>> allOrders = [];
  List<Map<String, dynamic>> filteredOrders = [];
  double totalRevenue = 0;
  int totalOrders = 0;
  double averageOrderValue = 0;
  List<Map<String, dynamic>> recentOrders = [];
  List<Map<String, dynamic>> topItems = [];
  Map<String, int> categorySales = {};
  List<FlSpot> revenueSpots = [];
  List<String> revenueLabels = [];
  List<BarChartGroupData> barGroups = [];
  List<String> barLabels = [];
  List<PieChartSectionData> pieSections = [];
  String selectedRange = '30 Days';
  final TextEditingController timeController = TextEditingController(
    text: '30 Days',
  );
  List<double> hourlyOrders = List.filled(24, 0);
  Map<String, double> pieData = {};

  @override
  void initState() {
    super.initState();
    loadSalesReport();
  }

  Future<void> loadSalesReport() async {
    try {
      setState(() => isLoading = true);
      final data = await ApiService.getOrders(cafeId: AppSession.cafeId);
      if (!mounted) return;

      allOrders = data;
      filteredOrders = _filterOrders(data);

      totalOrders = filteredOrders.length;
      totalRevenue = filteredOrders.fold<double>(
        0,
        (sum, order) =>
            sum +
            (order['total'] is num
                ? (order['total'] as num).toDouble()
                : double.tryParse(order['total']?.toString() ?? '0') ?? 0),
      );
      averageOrderValue = totalOrders == 0 ? 0 : totalRevenue / totalOrders;

      final itemCounts = <String, Map<String, dynamic>>{};
      categorySales.clear();

      for (final order in filteredOrders) {
        final items = (order['items'] as List<dynamic>?) ?? [];
        for (final rawItem in items) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          final name = item['name']?.toString() ?? 'Unknown';
          final qty = item['qty'] is num
              ? (item['qty'] as num).toInt()
              : int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          final price = item['price'] is num
              ? (item['price'] as num).toDouble()
              : double.tryParse(item['price']?.toString() ?? '0') ?? 0;
          final category = item['category']?.toString().trim() ?? 'Others';

          itemCounts[name] ??= {'name': name, 'qty': 0, 'revenue': 0.0};
          itemCounts[name]!['qty'] = (itemCounts[name]!['qty'] as int) + qty;
          itemCounts[name]!['revenue'] =
              (itemCounts[name]!['revenue'] as double) + price * qty;
          categorySales[category] = (categorySales[category] ?? 0) + qty;
        }
      }

      final sortedTopItems = itemCounts.values.toList()
        ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));

      final ordered = filteredOrders
          .map((o) => Map<String, dynamic>.from(o))
          .toList()
        ..sort((a, b) {
          final aDate =
              DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
              DateTime.now();
          final bDate =
              DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
              DateTime.now();
          return aDate.compareTo(bDate);
        });

      recentOrders = ordered;
      topItems = sortedTopItems
          .take(5)
          .map((i) => {
                'name': i['name'],
                'qty': i['qty'],
                'revenue': i['revenue'],
              })
          .toList();

      _prepareChartData(ordered);
      setState(() => isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    final duration =
        _parseTimeRange(timeController.text) ?? const Duration(days: 30);
    final now = DateTime.now();
    return orders.where((order) {
      final date = DateTime.tryParse(order['createdAt']?.toString() ?? '');
      if (date == null) return false;
      return date.isAfter(now.subtract(duration));
    }).toList();
  }

  Duration? _parseTimeRange(String raw) {
    final normalized = raw.trim().toLowerCase();
    final match = RegExp(
      r'^(\d+)\s*(days?|hrs?|hours?|mins?|minutes?|secs?|seconds?)$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final value = int.tryParse(match.group(1) ?? '') ?? 0;
    final unit = match.group(2) ?? '';
    if (unit.startsWith('day')) return Duration(days: value);
    if (unit.startsWith('hr') || unit.startsWith('hour')) return Duration(hours: value);
    if (unit.startsWith('min')) return Duration(minutes: value);
    if (unit.startsWith('sec')) return Duration(seconds: value);
    return null;
  }

  void _prepareChartData(List<Map<String, dynamic>> orders) {
    revenueSpots = [];
    revenueLabels = [];
    barGroups = [];
    barLabels = [];
    pieSections = [];
    hourlyOrders = List.filled(24, 0);
    pieData = {};

    final sorted = [...orders];
    sorted.sort((a, b) {
      final aDate =
          DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime.now();
      final bDate =
          DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime.now();
      return aDate.compareTo(bDate);
    });

    for (var i = 0; i < sorted.length; i++) {
      final order = sorted[i];
      final createdAt =
          DateTime.tryParse(order['createdAt']?.toString() ?? '') ??
          DateTime.now();
      final total = order['total'] is num
          ? (order['total'] as num).toDouble()
          : double.tryParse(order['total']?.toString() ?? '0') ?? 0;

      revenueSpots.add(FlSpot(i.toDouble(), total));
      revenueLabels.add(
        '${createdAt.month}/${createdAt.day} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
      );
      hourlyOrders[createdAt.hour] += 1;

      if (order['items'] != null) {
        for (var item in order['items']) {
          final itemName = item['name'] ?? 'Unknown';
          final qty = item['qty'] ?? 1;
          pieData[itemName] = (pieData[itemName] ?? 0) + qty.toDouble();
        }
      }
    }

    final buckets = <String, int>{};
    for (final order in sorted) {
      final createdAt =
          DateTime.tryParse(order['createdAt']?.toString() ?? '') ??
          DateTime.now();
      final key = selectedRange.contains('Hr')
          ? '${createdAt.hour}:00'
          : selectedRange.contains('Min')
              ? '${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}'
              : '${createdAt.month}/${createdAt.day}';
      buckets[key] = (buckets[key] ?? 0) + 1;
    }

    barLabels = buckets.keys.toList();
    barGroups = barLabels.asMap().entries.map((entry) {
      final value = buckets[entry.value] ?? 0;
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: value.toDouble(),
            color: primaryBlue,
            width: 18,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      );
    }).toList();
  }

  // ── CSV download (unchanged) ──────────────────────────────────────────────
  Future<void> _downloadCsvReport() async {
    if (filteredOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders available to export.')),
      );
      return;
    }

    final rows = <List<dynamic>>[
      ['Order ID', 'Customer', 'Amount', 'Status', 'Created At'],
    ];
    for (final order in filteredOrders) {
      rows.add([
        order['orderId'] ?? order['_id'] ?? '',
        order['customerName'] ?? '',
        order['total']?.toString() ?? '',
        order['status'] ?? '',
        order['createdAt'] ?? '',
      ]);
    }

    final csvData =
        rows.map((row) => row.map((cell) => '"$cell"').join(',')).join('\n');
    final fileName = 'sales-report-${DateTime.now().millisecondsSinceEpoch}.csv';

    try {
      final savedPath = await saveCsvFile(fileName, csvData);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('CSV exported: $savedPath')));
    } catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('CSV export failed: $error')));
    }
  }

  // ── Excel download (NEW) ──────────────────────────────────────────────────
  Future<void> _downloadExcelReport() async {
    if (filteredOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders available to export.')),
      );
      return;
    }

    final fileName =
        'sales-report-${DateTime.now().millisecondsSinceEpoch}.xlsx';

    try {
      final savedPath = await saveExcelReport(fileName, filteredOrders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel exported: $savedPath')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel export failed: $error')),
      );
    }
  }

  String formatRupees(double amount) {
    final rounded = amount.round();
    return '₹${rounded.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (match) => ',',
        )}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return VendorPageWrapper(
      pageTitle: 'Sales Reports',
      selectedMenuIndex: 4,
      toggleTheme: () {},
      child: Scaffold(
        backgroundColor: bgColor,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double availableWidth = constraints.maxWidth;
              bool isMobile = MediaQuery.of(context).size.width < 850;
              double cardWidth = isMobile
                  ? (availableWidth - 16) / 2
                  : (availableWidth - 32) / 3;
              double halfWidth =
                  isMobile ? availableWidth : (availableWidth - 16) / 2;

              // ── Shared toolbar actions ────────────────────────────────────
              Widget dropdownWidget = Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primaryBlue.withOpacity(0.25)),
                ),
                child: DropdownButton<String>(
                  value: selectedRange,
                  elevation: 4,
                  underline: const SizedBox(),
                  items: ['30 Days', '24 Hrs', '12 Hrs', '60 Min', '30 Sec', 'Custom']
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(
                              option,
                              style: TextStyle(
                                  color: textColor, fontWeight: FontWeight.bold),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedRange = value;
                      timeController.text = value;
                    });
                    loadSalesReport();
                  },
                ),
              );

              Widget customTextField = SizedBox(
                width: isMobile ? availableWidth - 24 : 180,
                child: TextField(
                  controller: timeController,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    hintText: '50 Hrs, 7 Days, 30 Min, 15 Sec',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onSubmitted: (_) {
                    setState(() => selectedRange = 'Custom');
                    loadSalesReport();
                  },
                ),
              );

              // CSV button
              Widget csvButton = ElevatedButton.icon(
                onPressed: _downloadCsvReport,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('CSV',
                    style: TextStyle(
                        fontFamily: 'Nunito', fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              );

              // Excel button (NEW)
              Widget excelButton = ElevatedButton.icon(
                onPressed: _downloadExcelReport,
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text('Excel',
                    style: TextStyle(
                        fontFamily: 'Nunito', fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D6F42), // Excel green
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              );

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // ── Toolbar ───────────────────────────────────────────
                    isMobile
    ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Track ${VendorData.displayName}'s performance",
            style: TextStyle(
              fontFamily: 'Inter',
              color: subText,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 16),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.6,
            children: [
              dropdownWidget,
              customTextField,
              csvButton,
              excelButton,
            ],
          ),
        ],
      )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Track ${VendorData.displayName}'s performance",
                                style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: subText,
                                    fontSize: 14),
                              ),
                              Row(
                                children: [
                                  dropdownWidget,
                                  const SizedBox(width: 10),
                                  customTextField,
                                  const SizedBox(width: 10),
                                  csvButton,
                                  const SizedBox(width: 8),
                                  excelButton,
                                ],
                              ),
                            ],
                          ),

                    const SizedBox(height: 20),

                    // ── Summary cards ─────────────────────────────────────
                    if (isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          InteractiveScale(
                            onTap: () {},
                            child: _topCard(formatRupees(totalRevenue),
                                "Total Revenue", "+0%", cardColor, textColor,
                                subText, isDark, cardWidth),
                          ),
                          InteractiveScale(
                            onTap: () {},
                            child: _topCard(totalOrders.toString(),
                                "Total Orders", "+0%", cardColor, textColor,
                                subText, isDark, cardWidth),
                          ),
                          InteractiveScale(
                            onTap: () {},
                            child: _topCard(formatRupees(averageOrderValue),
                                "Avg Order Value", "+0%", cardColor, textColor,
                                subText, isDark, cardWidth),
                          ),
                        ],
                      ),

                    const SizedBox(height: 20),

                    // ── Charts ────────────────────────────────────────────
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: halfWidth,
                          child: InteractiveScale(
                            onTap: () {},
                            child: _hourlyOrdersChart(cardColor, textColor, isDark),
                          ),
                        ),
                        SizedBox(
                          width: halfWidth,
                          child: InteractiveScale(
                            onTap: () {},
                            child: _pieChart(cardColor, textColor, isDark),
                          ),
                        ),
                      ],
                    )
                        .animate()
                        .fade(delay: 200.ms)
                        .slideY(begin: 0.1, curve: Curves.easeOutCubic),

                    const SizedBox(height: 20),

                    // ── Transactions ──────────────────────────────────────
                    InteractiveScale(
                      onTap: () {},
                      child: _transactionsTable(
                          cardColor, textColor, subText, isDark),
                    )
                        .animate()
                        .fade(delay: 400.ms)
                        .slideY(begin: 0.1, curve: Curves.easeOutCubic),

                    const SizedBox(height: 50),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Widgets (unchanged) ───────────────────────────────────────────────────

  Widget _topCard(String value, String title, String growth, Color card,
      Color text, Color sub, bool isDark, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: text),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  fontFamily: 'Inter',
                  color: sub,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.trending_up_rounded,
                    color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(growth,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pieChart(Color card, Color text, bool isDark) {
    return _box(
      'Top Selling Items',
      card,
      text,
      isDark,
      SizedBox(
        height: 300,
        child: PieChart(
          PieChartData(
            sections: pieData.entries
                .map((e) => PieChartSectionData(
                      value: e.value,
                      title: '${e.key}\n${e.value.toInt()}',
                      radius: 90,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _hourlyOrdersChart(Color card, Color text, bool isDark) {
    return _box(
      'Orders by Time',
      card,
      text,
      isDark,
      SizedBox(
        height: 300,
        child: BarChart(
          BarChartData(
            maxY: hourlyOrders.reduce((a, b) => a > b ? a : b) + 2,
            titlesData: FlTitlesData(
              topTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true, reservedSize: 45, interval: 2),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() % 3 != 0)
                      return const SizedBox.shrink();
                    return Transform.rotate(
                      angle: -0.5,
                      child: Text('${value.toInt()}h',
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            barGroups: hourlyOrders
                .asMap()
                .entries
                .map((e) => BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(toY: e.value, width: 10)
                      ],
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _transactionsTable(
      Color card, Color text, Color subText, bool isDark) {
    return _box(
      'Recent Transactions',
      card,
      text,
      isDark,
      recentOrders.isEmpty
          ? Center(
              child: Text('No recent transactions yet',
                  style: TextStyle(color: text)))
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: recentOrders.length,
              separatorBuilder: (_, __) => Divider(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                final order = recentOrders[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    order['orderId']?.toString() ?? 'Unknown',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: text),
                  ),
                  subtitle: Text(
                    order['customerName']?.toString() ?? 'Customer',
                    style: TextStyle(fontFamily: 'Inter', color: subText),
                  ),
                  trailing: Text(
                    formatRupees(((order['total'] as num?) ?? 0)
                        .toDouble()
                        .round()
                        .toDouble()),
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: text),
                  ),
                );
              },
            ),
    );
  }

  Widget _box(
      String title, Color card, Color text, bool isDark, Widget child) {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: text)),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class InteractiveScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const InteractiveScale(
      {super.key, required this.child, required this.onTap});
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
        child: InkWell(
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onHover: (h) => setState(() => isHovered = h),
          onHighlightChanged: (h) => setState(() => isPressed = h),
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}