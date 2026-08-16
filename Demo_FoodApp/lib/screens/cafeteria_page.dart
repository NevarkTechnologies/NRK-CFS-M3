import '../utils/b64_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../model/notification_model.dart';
import '../services/session.dart';
import '../widgets/smooth_marquee_text.dart';
import 'home_page.dart';
import 'profile_page.dart';
import 'notification_page.dart';
import 'cart_page.dart';

class CafeteriaPage extends StatefulWidget {
  final VoidCallback toggleTheme;

  const CafeteriaPage({super.key, required this.toggleTheme});

  @override
  State<CafeteriaPage> createState() => _CafeteriaPageState();
}

class _CafeteriaPageState extends State<CafeteriaPage> {
  final Color appBlue = const Color(0xFF0F4CFF);
  String searchQuery = '';
  late FocusNode _searchFocusNode;

  List<Map<String, dynamic>> cafes = [];
  late List<Map<String, dynamic>> filteredCafes;
  bool isLoadingCafes = true;

  // cafeId -> stars the current user has given
  final Map<String, int> _userRatings = {};

  String? get _firebaseUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    filteredCafes = [];
    _loadCafes();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    if (!AppSession.isLoggedIn) return;
    try {
      await NotificationModel.fetchNotifications(AppSession.userId);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadCafes() async {
    setState(() {
      isLoadingCafes = true;
    });

    try {
      cafes = await ApiService.getCafes();
      try {
        await _loadUserRatings();
      } catch (error) {
        debugPrint('Rating restore deferred: $error');
      }
    } catch (_) {
      cafes = [];
    } finally {
      if (mounted) {
        setState(() {
          isLoadingCafes = false;
        });
        _filterCafes();
      }
    }
  }

  Future<void> _loadUserRatings() async {
    if (!AppSession.isLoggedIn || _firebaseUid == null) {
      _userRatings.clear();
      return;
    }
    final ratings = await ApiService.getUserRatings(_firebaseUid!);
    _userRatings
      ..clear()
      ..addAll(ratings);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _filterCafes() {
    setState(() {
      final query = searchQuery.toLowerCase();
      filteredCafes = cafes.where((cafe) {
        final name = cafe['name']?.toString().toLowerCase() ?? '';
        final cuisine = cafe['cuisine']?.toString().toLowerCase() ?? '';
        final location = cafe['location']?.toString().toLowerCase() ?? '';
        return query.isEmpty ||
            name.contains(query) ||
            cuisine.contains(query) ||
            location.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 760;
    final isWide = width > 1000;

    return Scaffold(
      // ✨ Changed background from white to a subtle cool blue (0xFFF0F6FF)
      backgroundColor: isDark
          ? const Color(0xFF020617)
          : const Color(0xFFF0F6FF),
      extendBody: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: RefreshIndicator(
          onRefresh: _loadCafes,
          color: const Color(0xFF0F4CFF),
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroSection(isDark),
                const SizedBox(height: 30),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionHeader(isDark),
                          const SizedBox(height: 16),
                          _buildCafeGrid(isDark, isMobile, isWide),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 0,
        isDark: isDark,
        toggleTheme: widget.toggleTheme,
      ),
    );
  }

  Widget _buildHeroSection(bool isDark) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            right: 20,
            bottom: 60,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE8F0FF),
            image: DecorationImage(
              image: const AssetImage('assets/bg.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                isDark
                    ? const Color(0xFF0F172A).withValues(alpha: 0.9)
                    : const Color(0xFFF0F6FF).withValues(alpha: 0.85),
                BlendMode.srcATop,
              ),
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFFDDE6FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Opacity(
                          opacity: 0.7, // 0.0 to 1.0
                          child: Image.asset(
                            'assets/icon/icon3.png',
                            width: 28,
                            height: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BenchBites',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF081F47),
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                height: 1.1,
                              ),
                            ),
                            Row(
                              children: [
                                const SizedBox(width: 4),
                                Text(
                                  'By Nevark',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF6B7280),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _iconButton(
                        icon: Icons.notifications_none_rounded,
                        isDark: isDark,
                        badgeCount: NotificationModel.notifications
                            .where((n) => n['isRead'] != true)
                            .length,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationPage(),
                            ),
                          ).then((_) {
                            if (mounted) setState(() {});
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Text(
                    'Skip the Wait.',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF081F47),
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Order & Pick Up.',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: appBlue,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 12,
                      children: [
                        _buildInfoChip(
                          Icons.takeout_dining_rounded,
                          "Grab & Go",
                          isDark,
                        ),
                        _buildInfoChip(
                          Icons.access_time_filled_rounded,
                          "Save Break Time",
                          isDark,
                        ),
                        _buildInfoChip(
                          Icons.compare_arrows_rounded,
                          "Zero Queue",
                          isDark,
                        ),
                        _buildInfoChip(
                          Icons.flash_on_rounded,
                          "Order in 20s",
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          bottom: -28,
          left: 0,
          right: 0,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSearchBar(isDark),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFDDE6FF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.white70 : appBlue),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF10254E),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final hintColor = isDark
        ? const Color.fromARGB(137, 178, 173, 173)
        : const Color.fromARGB(255, 105, 103, 103);
    final showAnimatedHint = searchQuery.isEmpty && !_searchFocusNode.hasFocus;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(60),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          TextField(
            focusNode: _searchFocusNode,
            onChanged: (value) {
              searchQuery = value;
              _filterCafes();
            },
            style: TextStyle(
              fontFamily: 'Inter',
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: '',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 20, right: 8, top: 4),
                child: Icon(
                  Icons.search_rounded,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                  size: 28,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 20,
                horizontal: 20,
              ),
            ),
          ),
          if (showAnimatedHint)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: IgnorePointer(
                child: AnimatedTextKit(
                  repeatForever: true,
                  animatedTexts: [
                    RotateAnimatedText(
                      'Search for Restaurants',
                      textStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: hintColor,
                        fontSize: 15,
                      ),
                      duration: const Duration(milliseconds: 1500),
                    ),
                    RotateAnimatedText(
                      'Search for Cafes',
                      textStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: hintColor,
                        fontSize: 15,
                      ),
                      duration: const Duration(milliseconds: 1500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required bool isDark,
    int? badgeCount,
    required VoidCallback onTap,
  }) {
    return Stack(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Icon(
              icon,
              color: isDark ? Colors.white : const Color(0xFF081F47),
              size: 22,
            ),
          ),
        ),
        if (badgeCount != null && badgeCount > 0)
          Positioned(
            top: -2,
            right: 1,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: appBlue, shape: BoxShape.circle),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  height: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(bool isDark) {
    // ✨ REMOVED the "View All" button row, keeping just the clean text header
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, top: 12.0),
      child: Text(
        'Restaurants & Cafes',
        style: TextStyle(
          fontFamily: 'Nunito',
          color: isDark ? Colors.white : const Color(0xFF081F47),
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildCafeGrid(bool isDark, bool isMobile, bool isWide) {
    if (isLoadingCafes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filteredCafes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Text(
            "No Restaurants or Cafeterias Found",
            style: TextStyle(
              fontFamily: 'Inter',
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double maxWidth = constraints.maxWidth;
        if (maxWidth <= 0) maxWidth = MediaQuery.of(context).size.width;

        int crossAxisCount;
        if (maxWidth > 1100) {
          crossAxisCount = 4;
        } else if (maxWidth > 800) {
          crossAxisCount = 3;
        } else if (maxWidth > 500) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 1;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredCafes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            mainAxisExtent: 400,
          ),
          itemBuilder: (context, index) {
            return _buildCafeCard(filteredCafes[index], isDark, isMobile);
          },
        );
      },
    );
  }

  Future<void> _showRatingDialog(Map<String, dynamic> cafe) async {
    final cafeId = cafe['_id']?.toString() ?? '';
    if (cafeId.isEmpty || !AppSession.isLoggedIn) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int selected = _userRatings[cafeId] ?? 0;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
            final textColor = isDark ? Colors.white : const Color(0xFF10254E);
            final subColor = isDark ? Colors.white60 : const Color(0xFF6B7280);
            return AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC107),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Rate ${cafe['name'] ?? 'Cafeteria'}',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'How would you rate your experience?',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: subColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < selected;
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setS(() => selected = i + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              filled
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: filled
                                  ? const Color(0xFFFFC107)
                                  : Colors.grey,
                              size: 38,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: appBlue,
                            side: BorderSide(
                              color: appBlue.withValues(alpha: 0.4),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
                          onPressed: selected == 0
                              ? null
                              : () async {
                                  Navigator.pop(ctx);
                                  try {
                                    final result = await ApiService.rateCafe(
                                      cafeId: cafeId,
                                      userId: AppSession.userId,
                                      stars: selected,
                                    );
                                    if (!mounted) return;
                                    setState(() {
                                      _userRatings[cafeId] = selected;
                                      final idx = cafes.indexWhere(
                                        (c) => c['_id']?.toString() == cafeId,
                                      );
                                      if (idx != -1) {
                                        cafes[idx]['rating'] = result['rating'];
                                        cafes[idx]['reviews'] =
                                            result['reviews'];
                                      }
                                      _filterCafes();
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        duration: const Duration(seconds: 1),
                                        content: Text(
                                          'Thanks for rating $selected ★',
                                        ),
                                        backgroundColor: appBlue,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  } catch (_) {}
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Submit',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_userRatings.containsKey(cafeId)) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final result = await ApiService.deleteRating(
                            cafeId: cafeId,
                            userId: AppSession.userId,
                          );
                          if (!mounted) return;
                          setState(() {
                            _userRatings.remove(cafeId);
                            final idx = cafes.indexWhere(
                              (c) => c['_id']?.toString() == cafeId,
                            );
                            if (idx != -1) {
                              cafes[idx]['rating'] = result['rating'];
                              cafes[idx]['reviews'] = result['reviews'];
                            }
                            _filterCafes();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              duration: Duration(seconds: 1),
                              content: Text('Rating removed'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (_) {}
                      },
                      child: Text(
                        'Remove my Rating',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          color: Colors.red.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _cafeImagePlaceholder(bool isDark) {
    return Container(
      height: 190,
      width: double.infinity,
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE8F0FF),
      child: Icon(
        Icons.storefront_rounded,
        size: 56,
        color: isDark ? Colors.white24 : appBlue.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildCafeCard(Map<String, dynamic> cafe, bool isDark, bool isMobile) {
    final isActive = cafe['active'] as bool? ?? true;
    return MouseRegion(
      cursor: isActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: isActive
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HomePage(cafe: cafe)),
                );
              }
            : null,
        child: Opacity(
          opacity: isActive ? 1.0 : 0.45,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Builder(
                          builder: (context) {
                            final imagePath = cafe['image']?.toString() ?? '';
                            if (imagePath.startsWith('data:image/')) {
                              final b64 = imagePath.split(',').last;
                              return Image.memory(
                                B64ImageCache.decode(b64),
                                height: 190,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _cafeImagePlaceholder(isDark),
                              );
                            }
                            if (imagePath.contains('assets/')) {
                              return Image.asset(
                                imagePath,
                                height: 190,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _cafeImagePlaceholder(isDark),
                              );
                            }
                            if (imagePath.isEmpty) {
                              return _cafeImagePlaceholder(isDark);
                            }
                            return Image.network(
                              imagePath,
                              height: 190,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _cafeImagePlaceholder(isDark),
                            );
                          },
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (cafe['offer']?.toString().trim().isNotEmpty ??
                                      false)
                                  ? cafe['offer'].toString()
                                  : 'Fresh & Fast',

                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                color: Color.fromARGB(255, 255, 244, 244),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              isActive
                                  ? (cafe['time']?.toString() ?? 'Instant')
                                  : 'Currently Unavailable',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                color: isActive ? appBlue : Colors.red.shade700,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              cafe['name']?.toString() ?? 'Unnamed Cafe',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.2,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF081F47),
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : const Color(0xFFE8F0FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFFFFC107),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${cafe['rating']}',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF10254E),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '(${cafe['reviews']} reviews)',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white54
                                        : const Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cafe['location']?.toString() ??
                                      'Nearby location',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SmoothMarqueeText(
                                  '${cafe['cuisine']?.toString() ?? 'Cafe'} • ${cafe['price']?.toString() ?? '₹300 for two'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white54
                                        : const Color(0xFF8B95A5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Rate Me banner
                    Builder(
                      builder: (_) {
                        final cafeId = cafe['_id']?.toString() ?? '';
                        final rated = _userRatings.containsKey(cafeId);
                        final ratedStars = _userRatings[cafeId] ?? 0;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _showRatingDialog(cafe),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: rated
                                    ? const Color(
                                        0xFFFFC107,
                                      ).withValues(alpha: 0.12)
                                    : appBlue.withValues(alpha: 0.07),
                                border: Border(
                                  top: BorderSide(
                                    color: isDark
                                        ? Colors.white12
                                        : Colors.grey.shade200,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    rated
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: rated
                                        ? const Color(0xFFFFC107)
                                        : appBlue,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    rated
                                        ? ' You Rated  $ratedStars ★   |   Tap to Change'
                                        : 'Tap to Rate',
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: rated
                                          ? const Color(0xFFFFC107)
                                          : appBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomFloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  final VoidCallback toggleTheme;

  const CustomFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.isDark,
    required this.toggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.4 : 0.08,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BottomNavigationBar(
                      currentIndex: currentIndex,
                      selectedItemColor: const Color(0xFF0F4CFF),
                      unselectedItemColor: isDark
                          ? Colors.white54
                          : Colors.grey.shade400,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,
                      selectedLabelStyle: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      onTap: (i) {
                        if (i == currentIndex) return;

                        if (i == 0) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CafeteriaPage(toggleTheme: toggleTheme),
                            ),
                          );
                        } else if (i == 1) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CartPage(toggleTheme: toggleTheme),
                            ),
                          );
                        } else if (i == 2) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfilePage(toggleTheme: toggleTheme),
                            ),
                          );
                        }
                      },
                      items: [
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.home_rounded),
                          label: "Home",
                        ),
                        BottomNavigationBarItem(
                          icon: ValueListenableBuilder<int>(
                            valueListenable: cartCountNotifier,
                            builder: (_, count, _) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.shopping_cart_rounded),
                                if (count > 0)
                                  Positioned(
                                    top: -6,
                                    right: -8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF0F4CFF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        count > 99 ? '99+' : '$count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          label: "Cart",
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.person_rounded),
                          label: "Profile",
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
