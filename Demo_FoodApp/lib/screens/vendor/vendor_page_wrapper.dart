import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../model/favorite_model.dart';
import '../cart_page.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'analytics_page.dart';
import '../login_page.dart';
import '../about_page.dart';
import 'menu_page.dart';
import 'settings_page.dart';
import 'sales_report.dart';
import 'order_page.dart';
import 'vendor_home_page.dart';
import 'vendor_data.dart';
import '../../services/session.dart';
import '../../services/api_service.dart';
import '../../widgets/smooth_marquee_text.dart';

class VendorPageWrapper extends StatefulWidget {
  final Widget child;
  final String pageTitle;
  final int selectedMenuIndex;
  final VoidCallback toggleTheme;
  final List<Widget>? trailingActions;

  const VendorPageWrapper({
    super.key,
    required this.child,
    required this.pageTitle,
    required this.selectedMenuIndex,
    required this.toggleTheme,
    this.trailingActions,
  });

  @override
  State<VendorPageWrapper> createState() => _VendorPageWrapperState();
}

class _VendorPageWrapperState extends State<VendorPageWrapper> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  late int selectedIndex;
  int _pendingOrderCount = 0;
  Timer? _orderPollTimer;

  bool get _requiresBusinessDetails => !VendorData.isBusinessDetailsComplete;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.selectedMenuIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_requiresBusinessDetails && selectedIndex != 5) {
        _promptCompleteBusinessDetails();
      }
    });
    _pollPendingOrders();
    _orderPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollPendingOrders(),
    );
  }

  @override
  void dispose() {
    _orderPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollPendingOrders() async {
    final cafeId = AppSession.cafe?['_id']?.toString();
    if (cafeId == null || cafeId.isEmpty) return;
    try {
      final orders = await ApiService.getOrders(
        cafeId: cafeId,
        status: 'Pending',
      );
      if (mounted) setState(() => _pendingOrderCount = orders.length);
    } catch (_) {}
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
                      builder: (_) =>
                          SettingsPage(toggleTheme: widget.toggleTheme),
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

  Future<bool?> _confirmLogout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF081F47);
    final subText = isDark ? Colors.white60 : const Color(0xFF6B7280);

    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Confirm Logout',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to log out?\nYour session data will be cleared.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: subText,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryBlue,
                      side: BorderSide(
                        color: primaryBlue.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Logout',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      clearCart();
      FavoriteModel.clear();
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
              actions: [
                if (widget.trailingActions != null) ...widget.trailingActions!,
                if (_pendingOrderCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.notifications_active_rounded,
                            color: primaryBlue,
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrdersPage(toggleTheme: widget.toggleTheme),
                            ),
                          ),
                          tooltip:
                              '$_pendingOrderCount pending order${_pendingOrderCount > 1 ? 's' : ''}',
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$_pendingOrderCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile) buildSidebar(textColor, cardColor, isDark),
            Expanded(child: widget.child),
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
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: primaryBlue.withValues(alpha: 0.1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Builder(
                    builder: (context) {
                      final src = VendorData.displayImage;
                      if (src.startsWith('data:image/')) {
                        final b64 = src.split(',').last;
                        return Image.memory(
                          base64Decode(b64),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.storefront_rounded,
                            color: primaryBlue,
                            size: 28,
                          ),
                        );
                      }
                      if (src.isNotEmpty) {
                        return Image.network(
                          src,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.storefront_rounded,
                            color: primaryBlue,
                            size: 28,
                          ),
                        );
                      }
                      return Icon(
                        Icons.storefront_rounded,
                        color: primaryBlue,
                        size: 28,
                      );
                    },
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
                      // CODEX EDITS: Long cuisine lists roll smoothly instead
                      // of ending with ellipsis in the common vendor sidebar.
                      SmoothMarqueeText(
                        VendorData.displayCuisine.isNotEmpty
                            ? VendorData.displayCuisine
                            : 'Vendor Portal',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
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
                buildMenu(Icons.list, "About Us", 6, textColor, isDark),
                buildMenu(Icons.logout_rounded, "Logout", 7, textColor, isDark),
              ],
            ),
          ),
          SafeArea(
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: GestureDetector(
                onTap: widget.toggleTheme,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF4F6F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: primaryBlue,
                        size: 22,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        isDark ? 'Light Mode' : 'Dark Mode',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
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
    final isLogout = title == "Logout";
    final isAbout = title == "About Us";
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage()),
            );
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
            if (!mounted) return;
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
              Expanded(
                child: Text(
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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (title == "Orders" && _pendingOrderCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pendingOrderCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
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
