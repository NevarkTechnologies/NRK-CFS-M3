import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_service.dart';
import '../../services/session.dart';
import '../../utils/csv_export.dart';
import '../../utils/excel_export.dart'; // ← NEW
import 'vendor_data.dart';
import 'vendor_page_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The rest of the state variables and logic are unchanged.
// Only _downloadExcelReport() is new, and the toolbar buttons are updated.
// ─────────────────────────────────────────────────────────────────────────────

class SalesReportPage extends StatefulWidget {
  final VoidCallback toggleTheme;

  const SalesReportPage({super.key, required this.toggleTheme});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  static const _filterOptions = [
    'All Time',
    'Today',
    'Yesterday',
    '15 Days',
    '1 Month',
  ];
  static const _chartColors = [
    Color(0xFF0F4CFF),
    Colors.teal,
    Colors.orange,
    Colors.purple,
    Color(0xFFEC4899),
    Colors.green,
    Colors.cyan,
    Colors.amber,
  ];

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
  String selectedRange = '1 Month';
  List<double> hourlyOrders = List.filled(24, 0);
  Map<String, double> pieData = {};
  String revenueGrowth = '0%';
  String ordersGrowth = '0%';
  String averageGrowth = '0%';

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
        (sum, order) => sum + _orderAmount(order),
      );
      averageOrderValue = totalOrders == 0 ? 0 : totalRevenue / totalOrders;
      _prepareGrowth(data);

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

      final ordered =
          filteredOrders.map((o) => Map<String, dynamic>.from(o)).toList()
            ..sort((a, b) {
              final aDate =
                  _createdAt(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  _createdAt(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

      recentOrders = ordered;
      topItems = sortedTopItems
          .take(5)
          .map(
            (i) => {
              'name': i['name'],
              'qty': i['qty'],
              'revenue': i['revenue'],
            },
          )
          .toList();

      _prepareChartData(ordered);
      setState(() => isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filterOrders(List<Map<String, dynamic>> orders) {
    final range = _selectedRangeBounds();
    if (range == null) return orders;
    return orders.where((o) {
      final d = _createdAt(o);
      return d != null && !d.isBefore(range.start) && d.isBefore(range.end);
    }).toList();
  }

  // CODEX EDITS: Centralized IST parsing keeps filters, charts, growth,
  // and the transaction list consistent for the selected sales period.
  DateTime? _createdAt(Map<String, dynamic> order) {
    final parsed = DateTime.tryParse(order['createdAt']?.toString() ?? '');
    return parsed?.toUtc().add(const Duration(hours: 5, minutes: 30));
  }

  double _orderAmount(Map<String, dynamic> order) {
    final raw = order['itemTotal'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  DateTimeRange? _selectedRangeBounds() {
    final now = DateTime.now();
    switch (selectedRange) {
      case 'All Time':
        return null;
      case 'Today':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case 'Yesterday':
        final todayStart = DateTime(now.year, now.month, now.day);
        return DateTimeRange(
          start: todayStart.subtract(const Duration(days: 1)),
          end: todayStart,
        );
      case '15 Days':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 15)),
          end: now,
        );
      case '1 Month':
      default:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
    }
  }

  DateTimeRange? _previousRangeBounds() {
    final current = _selectedRangeBounds();
    if (current == null) return null;
    final span = current.end.difference(current.start);
    return DateTimeRange(
      start: current.start.subtract(span),
      end: current.start,
    );
  }

  void _prepareGrowth(List<Map<String, dynamic>> orders) {
    final previous = _previousRangeBounds();
    if (previous == null) {
      revenueGrowth = 'All time';
      ordersGrowth = 'All time';
      averageGrowth = 'All time';
      return;
    }

    final previousOrders = orders.where((o) {
      final d = _createdAt(o);
      return d != null &&
          !d.isBefore(previous.start) &&
          d.isBefore(previous.end);
    }).toList();
    final previousRevenue = previousOrders.fold<double>(
      0,
      (sum, order) => sum + _orderAmount(order),
    );
    final previousAverage = previousOrders.isEmpty
        ? 0.0
        : previousRevenue / previousOrders.length;

    revenueGrowth = _growthLabel(totalRevenue, previousRevenue);
    ordersGrowth = _growthLabel(
      totalOrders.toDouble(),
      previousOrders.length.toDouble(),
    );
    averageGrowth = _growthLabel(averageOrderValue, previousAverage);
  }

  String _growthLabel(double current, double previous) {
    if (previous == 0) return current == 0 ? '0%' : '+100%';
    final growth = ((current - previous) / previous) * 100;
    final sign = growth > 0 ? '+' : '';
    return '$sign${growth.toStringAsFixed(growth.abs() >= 10 ? 0 : 1)}%';
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
      final createdAt = _createdAt(order) ?? DateTime.now();
      final total = order['itemTotal'] is num
          ? (order['itemTotal'] as num).toDouble()
          : double.tryParse(order['itemTotal']?.toString() ?? '0') ?? 0;

      revenueSpots.add(FlSpot(i.toDouble(), total));
      revenueLabels.add(
        '${createdAt.month}/${createdAt.day} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
      );
      hourlyOrders[createdAt.hour] += 1;

      if (order['items'] != null) {
        for (var item in order['items']) {
          final itemName = item['name']?.toString() ?? 'Unknown';
          final qty = item['qty'] is num
              ? (item['qty'] as num).toDouble()
              : double.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          pieData[itemName] = (pieData[itemName] ?? 0) + qty;
        }
      }
    }

    final sortedPie = pieData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    pieData = {for (final entry in sortedPie.take(6)) entry.key: entry.value};
    final others = sortedPie.skip(6).fold<double>(0, (sum, e) => sum + e.value);
    if (others > 0) pieData['Others'] = others;

    final buckets = <String, int>{};
    if (selectedRange == 'Today' || selectedRange == 'Yesterday') {
      for (var hour = 0; hour < 24; hour++) {
        buckets['${hour.toString().padLeft(2, '0')}:00'] = 0;
      }
      for (final order in sorted) {
        final createdAt = _createdAt(order) ?? DateTime.now();
        final key = '${createdAt.hour.toString().padLeft(2, '0')}:00';
        buckets[key] = (buckets[key] ?? 0) + 1;
      }
    } else {
      for (final order in sorted) {
        final createdAt = _createdAt(order) ?? DateTime.now();
        final key = selectedRange == 'All Time'
            ? '${createdAt.month}/${createdAt.year}'
            : '${createdAt.day}/${createdAt.month}';
        buckets[key] = (buckets[key] ?? 0) + 1;
      }
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

  // ── CSV download ──────────────────────────────────────────────────────────
  Future<void> _downloadCsvReport() async {
    if (filteredOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders available to export.')),
      );
      return;
    }

    final rows = <List<dynamic>>[
      [
        'Order ID',
        'Token',
        'Customer',
        'Items',
        'Item Total (₹)',
        'Status',
        'Date',
        'Time',
      ],
    ];
    for (final order in filteredOrders) {
      final items = ((order['items'] as List<dynamic>?) ?? [])
          .map((i) => '${i['name']} x${i['qty'] ?? 1}')
          .join(' | ');
      // CODEX EDITS: Export MongoDB UTC timestamps as IST date/time.
      final createdAt = _createdAt(order);
      final dateStr = createdAt != null
          ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
          : '';
      final timeStr = createdAt != null
          ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
          : '';
      final amount = (order['itemTotal'] is num)
          ? (order['itemTotal'] as num).toStringAsFixed(2)
          : (double.tryParse(order['itemTotal']?.toString() ?? '0') ?? 0)
                .toStringAsFixed(2);

      rows.add([
        order['orderId'] ?? order['_id'] ?? '',
        order['tokenNumber'] ?? '',
        order['customerName'] ?? '',
        items,
        amount,
        order['status'] ?? '',
        dateStr,
        timeStr,
      ]);
    }

    final csvData = rows
        .map((row) => row.map((cell) => '"$cell"').join(','))
        .join('\n');
    final now = DateTime.now();
    final fileName =
        'benchbites-report-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';

    try {
      final savedPath = await saveCsvFile(fileName, csvData);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV saved: $savedPath')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV export failed: $error')));
    }
  }

  // ── Excel download ────────────────────────────────────────────────────────
  Future<void> _downloadExcelReport() async {
    if (filteredOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders available to export.')),
      );
      return;
    }

    final now = DateTime.now();
    final fileName =
        'benchbites-report-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';

    try {
      final savedPath = await saveExcelReport(fileName, filteredOrders);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel saved: $savedPath')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel export failed: $error')));
    }
  }

  String formatRupees(double amount) {
    final rounded = amount.round();
    return '₹${rounded.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';
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
      toggleTheme: widget.toggleTheme,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double availableWidth = constraints.maxWidth.clamp(
                0,
                double.infinity,
              );
              bool isMobile = MediaQuery.of(context).size.width < 850;
              double cardWidth =
                  (isMobile
                          ? (availableWidth - 16) / 2
                          : (availableWidth - 32) / 3)
                      .clamp(120.0, 400.0);
              double halfWidth = isMobile
                  ? availableWidth
                  : ((availableWidth - 16) / 2).clamp(200.0, double.infinity);

              // ── Shared toolbar actions ────────────────────────────────────
              Widget dropdownWidget = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: primaryBlue.withValues(alpha: 0.25),
                  ),
                ),
                child: DropdownButton<String>(
                  value: selectedRange,
                  elevation: 4,
                  underline: const SizedBox(),
                  dropdownColor: cardColor,
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  items: _filterOptions
                      .map(
                        (option) => DropdownMenuItem(
                          value: option,
                          child: Text(option),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedRange = value);
                    loadSalesReport();
                  },
                ),
              );

              // CSV button
              Widget csvButton = ElevatedButton.icon(
                onPressed: _downloadCsvReport,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text(
                  'CSV',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              );

              // Excel button (NEW)
              Widget excelButton = ElevatedButton.icon(
                onPressed: _downloadExcelReport,
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text(
                  'Excel',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D6F42), // Excel green
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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

                              const SizedBox(height: 12),

                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                alignment: WrapAlignment.start,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  dropdownWidget,
                                  csvButton,
                                  excelButton,
                                ],
                              ),
                            ],
                          )
                        : Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              Text(
                                "Track ${VendorData.displayName}'s performance",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: subText,
                                  fontSize: 14,
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  dropdownWidget,
                                  csvButton,
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
                            child: _topCard(
                              formatRupees(totalRevenue),
                              "Total Revenue",
                              revenueGrowth,
                              cardColor,
                              textColor,
                              subText,
                              isDark,
                              cardWidth,
                            ),
                          ),
                          InteractiveScale(
                            onTap: () {},
                            child: _topCard(
                              totalOrders.toString(),
                              "Total Orders",
                              ordersGrowth,
                              cardColor,
                              textColor,
                              subText,
                              isDark,
                              cardWidth,
                            ),
                          ),
                          InteractiveScale(
                            onTap: () {},
                            child: _topCard(
                              formatRupees(averageOrderValue),
                              "Avg Order Value",
                              averageGrowth,
                              cardColor,
                              textColor,
                              subText,
                              isDark,
                              cardWidth,
                            ),
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
                                child: _hourlyOrdersChart(
                                  cardColor,
                                  textColor,
                                  isDark,
                                ),
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
                            cardColor,
                            textColor,
                            subText,
                            isDark,
                          ),
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

  Widget _topCard(
    String value,
    String title,
    String growth,
    Color card,
    Color text,
    Color sub,
    bool isDark,
    double width,
  ) {
    final isNegative = growth.startsWith('-');
    final isNeutral = growth == '0%' || growth == 'All time';
    final growthColor = isNeutral
        ? sub
        : isNegative
        ? Colors.redAccent
        : Colors.green;
    final growthIcon = isNeutral
        ? Icons.remove_rounded
        : isNegative
        ? Icons.trending_down_rounded
        : Icons.trending_up_rounded;
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
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: text,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              color: sub,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: growthColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(growthIcon, color: growthColor, size: 14),
                const SizedBox(width: 4),
                Text(
                  growth,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: growthColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pieChart(Color card, Color text, bool isDark) {
    final keys = pieData.keys.toList();
    return _box(
      'Top Selling Items',
      card,
      text,
      isDark,
      pieData.isEmpty
          ? Center(
              child: Text('No data', style: TextStyle(color: text)),
            )
          : Column(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 34,
                      sections: keys.asMap().entries.map((entry) {
                        final color =
                            _chartColors[entry.key % _chartColors.length];
                        final val = pieData[entry.value]!;
                        return PieChartSectionData(
                          value: val,
                          title: '${val.toInt()}',
                          radius: 70,
                          color: color,
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: keys.asMap().entries.map((entry) {
                    final color = _chartColors[entry.key % _chartColors.length];
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              entry.value,
                              style: TextStyle(fontSize: 11, color: text),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }

  Widget _hourlyOrdersChart(Color card, Color text, bool isDark) {
    final maxOrders = barGroups.fold<double>(
      0,
      (max, group) =>
          group.barRods.first.toY > max ? group.barRods.first.toY : max,
    );
    final labelEvery = barLabels.length <= 8
        ? 1
        : (barLabels.length / 6).ceil();
    return _box(
      'Orders by Time',
      card,
      text,
      isDark,
      SizedBox(
        height: 300,
        child: BarChart(
          BarChartData(
            maxY: maxOrders + 2,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxOrders <= 6 ? 1 : null,
              getDrawingHorizontalLine: (_) => FlLine(
                color: isDark ? Colors.white10 : Colors.black12,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: maxOrders <= 6 ? 1 : null,
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 ||
                        index >= barLabels.length ||
                        index % labelEvery != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        barLabels[index],
                        style: TextStyle(fontSize: 10, color: text),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: barGroups,
          ),
        ),
      ),
    );
  }

  Widget _transactionsTable(
    Color card,
    Color text,
    Color subText,
    bool isDark,
  ) {
    return _box(
      'Orders in $selectedRange',
      card,
      text,
      isDark,
      recentOrders.isEmpty
          ? Center(
              child: Text(
                'No orders in this period',
                style: TextStyle(color: text),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              // CODEX EDITS: The selected-period order list can be long; use
              // the card's bounded viewport instead of measuring every row.
              primary: false,
              itemCount: recentOrders.length,
              separatorBuilder: (_, _) => Divider(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                final order = recentOrders[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order['orderId']?.toString() ?? 'Unknown',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              order['customerName']?.toString() ?? 'Customer',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: subText,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatRupees(
                          ((order['itemTotal'] as num?) ?? 0)
                              .toDouble()
                              .round()
                              .toDouble(),
                        ),
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: text,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _box(String title, Color card, Color text, bool isDark, Widget child) {
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
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: text,
            ),
          ),
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
