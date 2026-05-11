import 'package:flutter/material.dart';
import '../services/api_service.dart';
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

  final List<Map<String, dynamic>> _fallbackCafes = [
    {
      'name': 'Madno - House of Sundaes and Waffles',
      'rating': 4.4,
      'reviews': 413,
      'time': '45-50 mins',
      'image': 'assets/cafes/cafe3.jpg',
      'category': 'Desserts',
      'cuisine': 'Ice Cream, Desserts',
      'price': '₹500 for two',
      'tag': 'Pure Veg',
      'offer': 'Buy 1 get 1',
      'location': 'Madno, 3.9 km',
    },
    {
      'name': 'Dindigul Thalappakatti',
      'rating': 4.3,
      'reviews': 520,
      'time': '45-55 mins',
      'image': 'assets/cafes/cafe1.jpg',
      'category': 'South Indian',
      'cuisine': 'Biryani, South Indian',
      'price': '₹400 for two',
      'tag': 'Hyderabadi',
      'offer': '20% off',
      'location': 'Thalappakatti, 2.7 km',
    },
    {
      'name': 'Baskin Robbins - Ice Cream Delight',
      'rating': 4.5,
      'reviews': 784,
      'time': '25-30 mins',
      'image': 'assets/cafes/cafe2.jpg',
      'category': 'Desserts',
      'cuisine': 'Ice Cream, Desserts',
      'price': '₹350 for two',
      'tag': 'Premium',
      'offer': 'Buy 1 get 1',
      'location': 'Baskin, 1.2 km',
    },
    {
      'name': 'Cafe Lounge Express',
      'rating': 4.2,
      'reviews': 298,
      'time': '30-40 mins',
      'image': 'assets/cafes/cafe1.jpg',
      'category': 'Cafe',
      'cuisine': 'Coffee, Snacks',
      'price': '₹320 for two',
      'tag': 'Quick Bite',
      'offer': '10% off',
      'location': 'Central, 1.8 km',
    },
  ];

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    filteredCafes = [];
    _loadCafes();
  }

  Future<void> _loadCafes() async {
    setState(() {
      isLoadingCafes = true;
    });

    try {
      cafes = await ApiService.getCafes();
      if (cafes.isEmpty) {
        cafes = List<Map<String, dynamic>>.from(_fallbackCafes);
      }
    } catch (_) {
      cafes = List<Map<String, dynamic>>.from(_fallbackCafes);
    } finally {
      if (mounted) {
        setState(() {
          isLoadingCafes = false;
        });
        _filterCafes();
      }
    }
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
        return query.isEmpty || name.contains(query) || cuisine.contains(query) || location.contains(query);
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
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF0F6FF),
      extendBody: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
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
            bottom: 60 
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE8F0FF),
            image: DecorationImage(
              image: const AssetImage('bg.jpg'), 
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                isDark ? const Color(0xFF0F172A).withOpacity(0.9) : const Color(0xFFF0F6FF).withOpacity(0.85), 
                BlendMode.srcATop
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
                          color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFDDE6FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.restaurant, color: appBlue, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            
                            Text(
                              'Nevark',
                              style: TextStyle(fontFamily: 'Nunito', color: isDark ? Colors.white : const Color(0xFF081F47), fontWeight: FontWeight.w900, fontSize: 22, height: 1.1),
                            ),
                            Row(
                              children: [
                                Icon(Icons.location_on, color: appBlue, size: 14),
                                const SizedBox(width: 4),
                                Text('Hosur', style: TextStyle(fontFamily: 'Inter', color: isDark ? Colors.white70 : const Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _iconButton(
                        icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        isDark: isDark,
                        onTap: widget.toggleTheme, 
                      ),
                      const SizedBox(width: 10),
                      _iconButton(
                        icon: Icons.notifications_none_rounded,
                        isDark: isDark,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPage())); 
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  
                  Text(
                    'Skip the queue.',
                    style: TextStyle(fontFamily: 'Nunito', fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF081F47), height: 1.1, letterSpacing: -0.5),
                  ),
                  Text(
                    'Order & pick up.',
                    style: TextStyle(fontFamily: 'Nunito', fontSize: 32, fontWeight: FontWeight.w900, color: appBlue, height: 1.1, letterSpacing: -0.5),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildInfoChip(Icons.shopping_bag_outlined, "Order in\n2 mins", isDark),
                      _buildInfoChip(Icons.access_time_rounded, "Save time", isDark),
                      _buildInfoChip(Icons.cleaning_services_rounded, "Fresh &\nhygienic", isDark),
                    ],
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
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFDDE6FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.white70 : appBlue),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF10254E), height: 1.2),
          )
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        focusNode: _searchFocusNode,
        onChanged: (value) {
          searchQuery = value;
          _filterCafes();
        },
        style: TextStyle(fontFamily: 'Inter', color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: 'Search food, cafes or cuisines',
          hintStyle: TextStyle(fontFamily: 'Inter', color: isDark ? Colors.white54 : Colors.grey.shade400, fontSize: 15),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 20, right: 12),
            child: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.grey.shade500, size: 24),
          ),
          // ✨ REMOVED the suffixIcon filter button entirely
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        ),
      ),
    );
  }

  Widget _iconButton({required IconData icon, required bool isDark, int? badgeCount, required VoidCallback onTap}) {
    return Stack(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: isDark ? Colors.white : const Color(0xFF081F47), size: 24),
          ),
        ),
        if (badgeCount != null && badgeCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: appBlue,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1),
              ),
            ),
          )
      ],
    );
  }

  Widget _buildSectionHeader(bool isDark) {
    // ✨ REMOVED the "View All" button row, keeping just the clean text header
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        'Cafeterias',
        style: TextStyle(
          fontFamily: 'Nunito',
          color: isDark ? Colors.white : const Color(0xFF081F47),
          fontSize: 24,
          fontWeight: FontWeight.w900, 
          letterSpacing: -0.3,
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
            "No cafeterias found",
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
            mainAxisExtent: 360,
          ),
          itemBuilder: (context, index) {
            return _buildCafeCard(filteredCafes[index], isDark, isMobile);
          },
        );
      },
    );
  }

  Widget _buildCafeCard(Map<String, dynamic> cafe, bool isDark, bool isMobile) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => HomePage(cafe: cafe)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
                    if (imagePath.contains('assets/')) {
                      return Image.asset(
                        imagePath,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200),
                      );
                    }
                    return Image.network(
                      imagePath.isNotEmpty ? imagePath : 'https://via.placeholder.com/400x300',
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200),
                    );
                  },
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      cafe['offer']?.toString() ?? 'Fresh & fast',
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Text(
                      cafe['time']?.toString() ?? '30-40 mins',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        color: appBlue,
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
                        color: isDark ? Colors.white : const Color(0xFF081F47),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE8F0FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${cafe['rating']}',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF10254E),
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
                            color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cafe['location']?.toString() ?? 'Nearby location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${cafe['cuisine']?.toString() ?? 'Cafe'} • ${cafe['price']?.toString() ?? '₹300 for two'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white54 : const Color(0xFF8B95A5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                      BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.08), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BottomNavigationBar(
                      currentIndex: currentIndex,
                      selectedItemColor: const Color(0xFF0F4CFF),
                      unselectedItemColor: isDark ? Colors.white54 : Colors.grey.shade400,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,
                      selectedLabelStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold, fontSize: 12),
                      unselectedLabelStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600, fontSize: 11),
                      onTap: (i) {
                        if (i == currentIndex) return;

                        if (i == 0) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CafeteriaPage(toggleTheme: toggleTheme)));
                        } else if (i == 1) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage(toggleTheme: toggleTheme)));
                        } else if (i == 2) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(toggleTheme: toggleTheme)));
                        }
                      },
                      items: const [
                        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Home"),
                        BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_rounded), label: "Cart"),
                        BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Profile"),
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