import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'analytics_page.dart';
import 'menu_page.dart';
import 'settings_page.dart';
import 'sales_report.dart';
import 'order_page.dart';
import 'vendor_home_page.dart';
import 'vendor_data.dart';
class VendorPageWrapper extends StatefulWidget {
  final Widget child;
  final String pageTitle;
  final int selectedMenuIndex;
  final VoidCallback toggleTheme;

  const VendorPageWrapper({
    super.key,
    required this.child,
    required this.pageTitle,
    required this.selectedMenuIndex,
    required this.toggleTheme,
  });

  @override
  State<VendorPageWrapper> createState() => _VendorPageWrapperState();
}

class _VendorPageWrapperState extends State<VendorPageWrapper> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  late int selectedIndex;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.selectedMenuIndex;
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
                widget.pageTitle,
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
            Expanded(child: widget.child)
          ],
        ),
      ),
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
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 20,
            offset: const Offset(4, 0),
          )
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
  width: 56,
  height: 56,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    color: primaryBlue.withOpacity(0.1),
  ),
  clipBehavior: Clip.antiAlias,
  child: VendorData.displayImage.isNotEmpty
      ? Image.network(
          VendorData.displayImage,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.storefront_rounded,
            color: primaryBlue,
            size: 28,
          ),
        )
      : Icon(
          Icons.storefront_rounded,
          color: primaryBlue,
          size: 28,
        ),
),
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
                        VendorData.displayCuisine,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textColor.withOpacity(0.6),
                        ),
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
                buildMenu(Icons.dashboard_rounded, "Dashboard", 0, textColor, isDark),
                buildMenu(Icons.shopping_bag_rounded, "Orders", 1, textColor, isDark),
                buildMenu(Icons.insights_rounded, "Analytics", 2, textColor, isDark),
                buildMenu(Icons.restaurant_menu_rounded, "Menu", 3, textColor, isDark),
                buildMenu(Icons.bar_chart_rounded, "Reports", 4, textColor, isDark),
                buildMenu(Icons.settings_rounded, "Settings", 5, textColor, isDark),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: InteractiveScale(
              onTap: () {
                if (MediaQuery.of(context).size.width < 850) Navigator.pop(context);
                Navigator.pushNamed(context, '/login');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
                    const SizedBox(width: 12),
                    const Text(
                      "Logout",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
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

  Widget buildMenu(IconData icon, String title, int index, Color textColor, bool isDark) {
    bool isSelected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InteractiveScale(
        onTap: () {
          setState(() => selectedIndex = index);
          if (MediaQuery.of(context).size.width < 850) Navigator.pop(context);
          Future.delayed(const Duration(milliseconds: 150), () {
            Widget page;
            if (title == "Orders") page = const OrdersPage();
            else if (title == "Analytics") page = const AnalyticsPage();
            else if (title == "Menu") page = MenuPage(toggleTheme: widget.toggleTheme);
            else if (title == "Reports") page = const SalesReportPage();
            else if (title == "Settings") page = const SettingsPage();
            else page = VendorHomePage(toggleTheme: widget.toggleTheme);

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => page),
            );
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.white
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
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ),
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
