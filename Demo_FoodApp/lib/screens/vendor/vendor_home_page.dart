import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'analytics_page.dart';
import '../login_page.dart';
import '../about_page.dart';
import 'menu_page.dart';
import 'settings_page.dart';
import 'sales_report.dart';
import 'order_page.dart';
import 'vendor_data.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';

class VendorHomePage extends StatefulWidget {
  final VoidCallback toggleTheme;

  const VendorHomePage({super.key, required this.toggleTheme});

  @override
  State<VendorHomePage> createState() => _VendorHomePageState();
}

class _VendorHomePageState extends State<VendorHomePage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  int selectedIndex = 0;

  int totalOrders = 0;
  int revenue = 0;
  int activeOrders = 0;
  int completed = 0;
  List<Map<String, dynamic>> recentOrders = [];
  bool isDashboardLoading = true;

  bool get _requiresBusinessDetails => !VendorData.isBusinessDetailsComplete;

  @override
  void initState() {
    super.initState();
    loadDashboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_requiresBusinessDetails) {
        _promptCompleteBusinessDetails();
      }
    });
  }

  Future<void> loadDashboard() async {
    try {
      final data = await ApiService.getVendorDashboard(AppSession.vendorId);
      if (!mounted) return;
      setState(() {
        totalOrders = (data["totalOrders"] as num?)?.toInt() ?? 0;
        revenue = (data["revenue"] as num?)?.toInt() ?? 0;
        activeOrders = (data["activeOrders"] as num?)?.toInt() ?? 0;
        completed = (data["completed"] as num?)?.toInt() ?? 0;
        recentOrders = ((data["recentOrders"] as List<dynamic>?) ?? [])
            .map((order) => Map<String, dynamic>.from(order as Map))
            .toList();
        isDashboardLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isDashboardLoading = false);
    }
  }

  String formatRupees(int amount) {
    return "₹${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ",")}";
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 850;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isMobile ? buildDrawer(textColor, cardColor, isDark) : null,
      appBar: isMobile
          ? AppBar(
              backgroundColor: cardColor,
              elevation: 0,
              iconTheme: IconThemeData(color: primaryBlue),
              title: Text(
                VendorData.displayName,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile) buildSidebar(textColor, cardColor, isDark),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: buildDashboard(
                  isMobile,
                  cardColor,
                  textColor,
                  subText,
                  isDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmLogout() {
    return showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Do you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      await AppSession.clear();
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(toggleTheme: widget.toggleTheme),
      ),
      (route) => false,
    );
  }

  void _promptCompleteBusinessDetails() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Complete Business Details'),
            content: const Text(
              'Please complete your restaurant profile in Settings before using other vendor pages.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(toggleTheme: widget.toggleTheme),
                    ),
                  );
                },
                child: const Text('Go to Settings'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildSidebar(Color textColor, Color cardColor, bool isDark) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Builder(builder: (context) {
                  final src = VendorData.displayImage;
                  Widget imgChild;
                  if (src.startsWith('data:image/')) {
                    final b64 = src.split(',').last;
                    imgChild = Image.memory(base64Decode(b64), fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.storefront_rounded, color: primaryBlue, size: 28));
                  } else if (src.isNotEmpty) {
                    imgChild = Image.network(src, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.storefront_rounded, color: primaryBlue, size: 28));
                  } else {
                    imgChild = Icon(Icons.storefront_rounded, color: primaryBlue, size: 28);
                  }
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imgChild,
                  );
                }),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        VendorData.displayName,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        VendorData.displayCuisine.isNotEmpty ? VendorData.displayCuisine : 'Vendor Portal',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              thickness: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                buildMenu(
                  Icons.dashboard_rounded,
                  "Dashboard",
                  0,
                  textColor,
                  isDark,
                ),
                buildMenu(
                  Icons.shopping_bag_rounded,
                  "Orders",
                  1,
                  textColor,
                  isDark,
                ),
                buildMenu(
                  Icons.insights_rounded,
                  "Analytics",
                  2,
                  textColor,
                  isDark,
                ),
                buildMenu(
                  Icons.restaurant_menu_rounded,
                  "Menu",
                  3,
                  textColor,
                  isDark,
                ),
                buildMenu(
                  Icons.bar_chart_rounded,
                  "Reports",
                  4,
                  textColor,
                  isDark,
                ),
                buildMenu(
                  Icons.settings_rounded,
                  "Settings",
                  5,
                  textColor,
                  isDark,
                ),
                buildMenu(Icons.info_outline_rounded, "About Us", 6, textColor, isDark),
                buildMenu(Icons.logout_rounded, "Logout", 7, textColor, isDark),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GestureDetector(
              onTap: widget.toggleTheme,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : const Color(0xFFF4F6F9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: const Color(0xFF0F4CFF), size: 22),
                    const SizedBox(width: 16),
                    Text(isDark ? 'Light Mode' : 'Dark Mode',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDrawer(Color textColor, Color cardColor, bool isDark) {
    return Drawer(
      backgroundColor: cardColor,
      child: buildSidebar(textColor, cardColor, isDark),
    );
  }

  Widget buildMenu(
    IconData icon,
    String title,
    int index,
    Color textColor,
    bool isDark,
  ) {
    bool isSelected = selectedIndex == index;
    bool isLogout = title == "Logout";
    bool isAbout = title == "About Us";
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InteractiveScale(
        onTap: () {
          if (MediaQuery.of(context).size.width < 850) Navigator.pop(context);
          if (isLogout) {
            _confirmLogout().then((yes) {
              if (yes == true) _logout();
            });
            return;
          }
          if (isAbout) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage()));
            return;
          }
          if (_requiresBusinessDetails && title != "Settings") {
            showDialog<void>(
              context: context,
              builder: (_) {
                return AlertDialog(
                  title: const Text('Complete Business Details'),
                  content: const Text(
                    'Please update your restaurant profile in Settings before using other vendor pages.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
            );
            return;
          }
          setState(() => selectedIndex = index);
          Future.delayed(const Duration(milliseconds: 150), () {
            Widget page;
            if (title == "Orders") {
              page = OrdersPage(toggleTheme: widget.toggleTheme);
            } else if (title == "Analytics") {
              page = AnalyticsPage(toggleTheme: widget.toggleTheme);
            } else if (title == "Menu") {
              page = MenuPage(toggleTheme: widget.toggleTheme);
            } else if (title == "Reports") {
              page = SalesReportPage(toggleTheme: widget.toggleTheme);
            } else if (title == "Settings") {
              page = SettingsPage(toggleTheme: widget.toggleTheme);
            } else {
              page = VendorHomePage(toggleTheme: widget.toggleTheme);
            }

            Navigator.push(context, MaterialPageRoute(builder: (_) => page));
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? (isLogout ? Colors.redAccent : primaryBlue)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : isLogout
                    ? Colors.redAccent
                    : (isDark ? Colors.white54 : Colors.grey.shade600),
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : isLogout
                      ? Colors.redAccent
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDashboard(
    bool isMobile,
    Color cardColor,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    int crossAxis = isMobile ? 2 : 4;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.05,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Overview",
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            VendorData.displayName.isNotEmpty
                                ? "Here is ${VendorData.displayName}'s summary today."
                                : "Here is your summary today.",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: subText,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IconButton(
                        icon: Icon(
                          isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          color: primaryBlue,
                        ),
                        onPressed: widget.toggleTheme,
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fade(duration: 400.ms)
              .slideY(begin: -0.1, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 32),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxis,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: isMobile ? 1.1 : 1.4,
            ),
            itemCount: 4,
            itemBuilder: (context, index) {
              final data = [
                [
                  "$totalOrders",
                  "Total Orders",
                  Icons.shopping_bag_rounded,
                  Colors.orange,
                  AnalyticsPage(toggleTheme: widget.toggleTheme),
                ],
                [
                  formatRupees(revenue),
                  "Total Revenue",
                  Icons.account_balance_wallet_rounded,
                  Colors.green,
                  SalesReportPage(toggleTheme: widget.toggleTheme),
                ],
                [
                  "$activeOrders",
                  "Active Orders",
                  Icons.outdoor_grill_rounded,
                  primaryBlue,
                  OrdersPage(toggleTheme: widget.toggleTheme),
                ],
                [
                  "$completed",
                  "Completed",
                  Icons.check_circle_rounded,
                  Colors.teal,
                  AnalyticsPage(toggleTheme: widget.toggleTheme),
                ],
              ];
              return InteractiveScale(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => data[index][4] as Widget,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.05,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (data[index][3] as Color).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(data[index][2] as IconData, color: data[index][3] as Color, size: 20),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            data[index][0] as String,
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data[index][1] as String,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: subText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  )
                  .animate()
                  .fade(delay: (100 * index).ms)
                  .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic);
            },
          ),

          const SizedBox(height: 32),
          Text(
            "Recent Orders",
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ).animate().fade(delay: 400.ms),
          const SizedBox(height: 16),
          buildOrdersTable(cardColor, textColor, subText, isDark)
              .animate()
              .fade(delay: 500.ms)
              .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget buildOrdersTable(
    Color cardColor,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    final orders = recentOrders.isEmpty
        ? <Map<String, dynamic>>[]
        : recentOrders
              .map(
                (order) => {
                  "id": order["orderId"] ?? "",
                  "name": order["customerName"] ?? "Not set yet",
                  "amount": order["itemTotal"] != null
                      ? "Rs ${order["itemTotal"]}"
                      : "Not set yet",
                  "status": order["status"] ?? "Not set yet",
                  "items": order["items"] ?? [],
                },
              )
              .toList();
    // Removed commented demo orders.

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orders.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
          itemBuilder: (context, index) {
            final order = orders[index];
            return InteractiveScale(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VendorOrderDetailsPage(order: order),
                ),
              ),
              child: buildOrderRow(
                order["id"] as String,
                order["name"] as String,
                order["amount"] as String,
                order["status"] as String,
                textColor,
                subText,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildOrderRow(
    String id,
    String name,
    String amount,
    String status,
    Color textColor,
    Color subText,
  ) {
    Color statusColor;
    Color statusBg;
    switch (status) {
      case "Pending":
        statusColor = Colors.orange;
        statusBg = Colors.orange.withValues(alpha: 0.15);
        break;
      case "Preparing":
        statusColor = primaryBlue;
        statusBg = primaryBlue.withValues(alpha: 0.15);
        break;
      case "Ready":
        statusColor = Colors.teal;
        statusBg = Colors.teal.withValues(alpha: 0.15);
        break;
      default:
        statusColor = Colors.grey;
        statusBg = Colors.grey.withValues(alpha: 0.15);
    }
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  id,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: subText,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: statusColor, letterSpacing: 0.5),
                ),
              ),
            ],
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
  bool isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => isPressed = true),
      onTapUp: (_) {
        setState(() => isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => isPressed = false),
      child: AnimatedScale(
        scale: isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class VendorOrderDetailsPage extends StatefulWidget {
  final Map<String, dynamic> order;

  const VendorOrderDetailsPage({super.key, required this.order});

  @override
  State<VendorOrderDetailsPage> createState() => _VendorOrderDetailsPageState();
}

class _VendorOrderDetailsPageState extends State<VendorOrderDetailsPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  late String currentStatus;

  @override
  void initState() {
    super.initState();
    currentStatus = widget.order["status"];
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);
    Color subText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryBlue),
        title: Text(
          "Order Details",
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Order #${widget.order['id']}",
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: textColor,
                        ),
                      ),
                      _buildStatusChip(currentStatus),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Customer: ${widget.order['name']}",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: subText,
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Divider(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                      thickness: 1.5,
                    ),
                  ),

                  Text(
                    "Order Items",
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ...((widget.order['items'] as List<dynamic>?) ?? []).map((
                    item,
                  ) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "${item['name']}  x${item['qty']}",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                          ),
                          Text(
                            "₹${item['price']}",
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total Amount",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          color: subText,
                        ),
                      ),
                      Text(
                        widget.order['amount'],
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: primaryBlue,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                  _buildActionButtons(),
                ],
              ),
            ).animate().fade().slideY(begin: 0.1, curve: Curves.easeOutCubic),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    Color bg;
    switch (status) {
      case "Pending":
        color = Colors.orange;
        bg = Colors.orange.withValues(alpha: 0.15);
        break;
      case "Preparing":
        color = primaryBlue;
        bg = primaryBlue.withValues(alpha: 0.15);
        break;
      case "Ready":
        color = Colors.teal;
        bg = Colors.teal.withValues(alpha: 0.15);
        break;
      case "Rejected":
        color = Colors.red;
        bg = Colors.red.withValues(alpha: 0.15);
        break;
      default:
        color = Colors.grey;
        bg = Colors.grey.withValues(alpha: 0.15);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          status.toUpperCase(),
          style: TextStyle(
          fontFamily: 'Inter',
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    ));
  }

  Widget _buildActionButtons() {
    if (currentStatus == "Pending") {
      return Row(
        children: [
          Expanded(
            child: _btn(
              "Accept",
              Colors.green,
              () => setState(() => currentStatus = "Preparing"),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _btn(
              "Reject",
              Colors.redAccent,
              () => setState(() => currentStatus = "Rejected"),
            ),
          ),
        ],
      );
    } else if (currentStatus == "Preparing") {
      return SizedBox(
        width: double.infinity,
        child: _btn(
          "Mark as Ready to Pickup",
          primaryBlue,
          () => setState(() => currentStatus = "Ready"),
        ),
      );
    } else if (currentStatus == "Ready") {
      return SizedBox(
        width: double.infinity,
        child: _btn(
          "Mark as Picked Up",
          Colors.teal,
          () => setState(() => currentStatus = "Completed"),
        ),
      );
    } else if (currentStatus == "Completed") {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            "Order Completed",
            style: TextStyle(
              fontFamily: 'Inter',
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text(
          "Order Rejected",
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _btn(String title, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      onPressed: onTap,
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}
