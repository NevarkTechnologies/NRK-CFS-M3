import 'package:flutter/material.dart';
import '../model/notification_model.dart';
import '../services/session.dart';
import 'cafeteria_page.dart';
import 'detail_page.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    NotificationModel.refreshSignal.addListener(_onRefresh);
  }

  @override
  void dispose() {
    NotificationModel.refreshSignal.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() {});
  }

  Future<void> _fetch() async {
    if (!AppSession.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      await NotificationModel.fetchNotifications(AppSession.userId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);

    return Scaffold(
      backgroundColor: background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context, isDark, "Notifications"),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : NotificationModel.notifications.isEmpty
                            ? _buildEmptyState(isDark)
                            : RefreshIndicator(
                                onRefresh: _fetch,
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 120),
                                  itemCount: NotificationModel.notifications.length,
                                  itemBuilder: (context, index) {
                                    final notif = NotificationModel.notifications[index];
                                    return _buildNotificationCard(context, notif, isDark);
                                  },
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 0,
        isDark: isDark,
        toggleTheme: () {},
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 20),
            ),
          ),
          const SizedBox(width: 16), // Ensures left-alignment right next to the button
          Text(
            title,
            style: TextStyle(
              fontSize: 18, 
              fontFamily: 'Nunito', 
              fontWeight: FontWeight.w900, 
              color: isDark ? Colors.white : const Color(0xFF0F4CFF), 
              letterSpacing: 0.5
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, Map<String, dynamic> notif, bool isDark) {
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final isUnread = notif['isRead'] != true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: isUnread
            ? Border.all(color: const Color(0xFF0F4CFF).withValues(alpha: 0.35), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          final id = notif['_id']?.toString() ?? '';
          if (isUnread && id.isNotEmpty) {
            await NotificationModel.markAsRead(id);
            if (mounted) setState(() {});
          }
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DetailPage(title: "Order Details")),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.notifications_active_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif["title"] ?? "",
                    style: TextStyle(
                      fontFamily: 'Nunito', 
                      fontWeight: FontWeight.w900, 
                      fontSize: 16, 
                      color: textColor
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif["message"] ?? "",
                    style: TextStyle(
                      fontFamily: 'Inter', 
                      fontWeight: FontWeight.w500,
                      fontSize: 13, 
                      color: subTextColor
                    ),
                  ),
                ],
              ),
            ),
            if (isUnread)
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(color: Color(0xFF0F4CFF), shape: BoxShape.circle),
              ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: subTextColor.withValues(alpha: 0.5)),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final subTextColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.notifications_none_rounded, size: 80, color: subTextColor.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text(
          "No notifications yet", 
          style: TextStyle(
            fontFamily: 'Nunito', 
            fontSize: 18, 
            fontWeight: FontWeight.w900, 
            color: subTextColor
          )
        ),
      ],
    );
  }
}

class NotificationDetailPage extends StatelessWidget {
  final String title;
  final List<String> items;

  const NotificationDetailPage({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);

    return Scaffold(
      backgroundColor: background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context, isDark, "Order Details"),
                  const SizedBox(height: 24),
                  Expanded(
                    child: items.isEmpty
                        ? Center(child: Text("No items found", style: TextStyle(fontFamily: 'Inter', color: textColor)))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05), 
                                      blurRadius: 10,
                                      offset: const Offset(0, 4)
                                    )
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE8F0FF),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.fastfood_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        items[index],
                                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: textColor, fontSize: 15),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 0, 
        isDark: isDark,
        toggleTheme: () {}, 
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDark, String barTitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : const Color(0xFF0F4CFF), size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            barTitle,
            style: TextStyle(
              fontSize: 18, 
              fontFamily: 'Nunito', 
              fontWeight: FontWeight.w900, 
              color: isDark ? Colors.white : const Color(0xFF0F4CFF), 
              letterSpacing: 0.5
            ),
          ),
        ],
      ),
    );
  }
}