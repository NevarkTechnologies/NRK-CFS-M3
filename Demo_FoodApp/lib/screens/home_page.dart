import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../services/api_service.dart';
import 'cart_page.dart';
import 'notification_page.dart';
import 'profile_page.dart';
import 'cafeteria_page.dart';
import '../model/cart_model.dart';
import '../model/favorite_model.dart';

class HomePage extends StatefulWidget {
  final Map<String, dynamic> cafe;
  final VoidCallback? toggleTheme;

  const HomePage({super.key, required this.cafe, this.toggleTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Color appBlue = const Color(0xFF0F4CFF); // Your vibrant brand blue
  String searchQuery = '';
  late FocusNode _searchFocusNode;

  late ScrollController _scrollController;
  bool _isMenuVisible = true;
  bool _isCartVisible = true;

  final Map<String, GlobalKey> categoryKeys = {};
  Map<String, List<Map<String, dynamic>>> groupedFoods = {};

  late List<Map<String, dynamic>> allFoods;
  late List<Map<String, dynamic>> filteredFoods;
  bool isLoadingMenu = true;

  List<Map<String, dynamic>> _getMenuForCafe(String cafeName, String image) {
    String nameLower = cafeName.toLowerCase();

    if (nameLower.contains('baskin') || nameLower.contains('ice cream') || nameLower.contains('dessert')) {
      return [
        {"id": "d1", "name": "Chocolate Fudge Sundae", "price": 220, "image": image, "desc": "Rich chocolate ice cream with hot fudge, nuts, & cherry.", "category": "Sundaes", "rating": 4.8, "reviews": 128, "isVeg": true},
        {"id": "d2", "name": "Mint Choc Chip Scoop", "price": 120, "image": image, "desc": "Refreshing mint ice cream with chocolate chips.", "category": "Scoops", "rating": 4.5, "reviews": 85, "isVeg": true},
        {"id": "d3", "name": "Strawberry Milkshake", "price": 160, "image": image, "desc": "Thick and creamy strawberry shake.", "category": "Shakes", "rating": 4.6, "reviews": 112, "isVeg": true},
        {"id": "d4", "name": "Belgian Waffle", "price": 190, "image": image, "desc": "Warm waffle topped with vanilla ice cream and syrup.", "category": "Waffles", "rating": 4.9, "reviews": 230, "isVeg": true},
      ];
    } else if (nameLower.contains('pizza') || nameLower.contains('domino')) {
      return [
        {"id": "p1", "name": "Margherita Pizza", "price": 250, "image": image, "desc": "Classic cheese and tomato wood-fired pizza.", "category": "Pizzas", "rating": 4.7, "reviews": 320, "isVeg": true},
        {"id": "p2", "name": "Pepperoni Pizza", "price": 300, "image": image, "desc": "Spicy pepperoni slices with mozzarella.", "category": "Pizzas", "rating": 4.9, "reviews": 410, "isVeg": false},
        {"id": "p3", "name": "Garlic Breadsticks", "price": 120, "image": image, "desc": "Freshly baked garlic bread with cheese dip.", "category": "Sides", "rating": 4.5, "reviews": 150, "isVeg": true},
        {"id": "p4", "name": "Coke Zero", "price": 60, "image": image, "desc": "Chilled aerated beverage.", "category": "Beverages", "rating": 4.3, "reviews": 90, "isVeg": true},
      ];
    } else if (nameLower.contains('starbucks') || nameLower.contains('coffee') || nameLower.contains('cafe')) {
      return [
        {"id": "c1", "name": "Caramel Macchiato", "price": 220, "image": image, "desc": "Freshly steamed milk with vanilla-flavored syrup.", "category": "Hot Coffees", "rating": 4.8, "reviews": 215, "isVeg": true},
        {"id": "c2", "name": "Iced Vanilla Latte", "price": 240, "image": image, "desc": "Espresso poured over ice and milk.", "category": "Cold Coffees", "rating": 4.7, "reviews": 180, "isVeg": true},
        {"id": "c3", "name": "Blueberry Muffin", "price": 150, "image": image, "desc": "Soft muffin baked with fresh blueberries.", "category": "Bakery", "rating": 4.5, "reviews": 95, "isVeg": true},
        {"id": "c4", "name": "Butter Croissant", "price": 130, "image": image, "desc": "Flaky, buttery, authentic French croissant.", "category": "Bakery", "rating": 4.6, "reviews": 120, "isVeg": true},
      ];
    } else {
      return [
        {"id": "m1", "name": "Chicken Biryani", "price": 220, "image": image, "desc": "Spicy traditional biryani with tender chicken pieces.", "category": "Mains", "rating": 4.3, "reviews": 150, "isVeg": false},
        {"id": "m2", "name": "Paneer Butter Masala", "price": 190, "image": image, "desc": "Cottage cheese cubes in a rich tomato gravy.", "category": "Mains", "rating": 4.6, "reviews": 180, "isVeg": true},
        {"id": "s1", "name": "Paneer Tikka", "price": 180, "image": image, "desc": "Grilled paneer cubes marinated in spices.", "category": "Starters", "rating": 4.8, "reviews": 210, "isVeg": true},
        {"id": "snk1", "name": "Masala French Fries", "price": 110, "image": image, "desc": "Crispy fries with Indian spices.", "category": "Snacks", "rating": 4.5, "reviews": 140, "isVeg": true},
        {"id": "bev1", "name": "Fresh Lime Soda", "price": 70, "image": image, "desc": "Refreshing sweet and salt lime soda.", "category": "Beverages", "rating": 4.2, "reviews": 85, "isVeg": true},
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      setState(() {});
    });

    _scrollController = ScrollController();

    allFoods = [];
    filteredFoods = [];
    _loadMenuForCafe();
  }

  Future<void> _loadMenuForCafe() async {
    setState(() {
      isLoadingMenu = true;
    });

    try {
      final cafeId = widget.cafe['_id']?.toString() ?? widget.cafe['id']?.toString();
      if (cafeId != null && cafeId.isNotEmpty) {
        final items = await ApiService.getMenu(cafeId: cafeId);
        allFoods = items.map((item) {
          return {
            'id': item['_id']?.toString() ?? item['id']?.toString() ?? '',
            'name': item['name'] ?? '',
            'price': item['price'] ?? 0,
            'image': item['image']?.toString().isNotEmpty == true ? item['image'] : widget.cafe['image'],
            'desc': item['description'] ?? item['desc'] ?? '',
            'category': item['category'] ?? 'Others',
            'rating': item['rating'] ?? 4.5,
            'reviews': item['reviews'] ?? 0,
            'isVeg': item['isVeg'] ?? true,
          };
        }).toList();
      } else {
        String cafeName = widget.cafe['name'] ?? 'Main Canteen';
        String cafeImage = widget.cafe['image'] ?? 'https://via.placeholder.com/150';
        allFoods = _getMenuForCafe(cafeName, cafeImage);
      }
    } catch (error) {
      allFoods = _getMenuForCafe(widget.cafe['name'] ?? 'Main Canteen', widget.cafe['image'] ?? 'https://via.placeholder.com/150');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingMenu = false;
          _filterFoods();
        });
      }
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _filterFoods() {
    setState(() {
      filteredFoods = allFoods.where((food) {
        return searchQuery.isEmpty ||
            food['name'].toLowerCase().contains(searchQuery.toLowerCase()) ||
            food['category'].toLowerCase().contains(searchQuery.toLowerCase());
      }).toList();

      groupedFoods.clear();
      for (var food in filteredFoods) {
        String cat = food['category'];
        if (!groupedFoods.containsKey(cat)) {
          groupedFoods[cat] = [];
          if (!categoryKeys.containsKey(cat)) {
            categoryKeys[cat] = GlobalKey();
          }
        }
        groupedFoods[cat]!.add(food);
      }
    });
  }

  void _updateCart(Map<String, dynamic> food, int delta) {
    setState(() {
      _isCartVisible = true;

      if (delta > 0) {
        CartModel.add(food["id"]);
      } else {
        CartModel.remove(food["id"]);
      }

      int index = globalCartItems.indexWhere((item) => item["id"] == food["id"]);
      if (index != -1) {
        globalCartItems[index]["qty"] += delta;
        if (globalCartItems[index]["qty"] <= 0) {
          globalCartItems.removeAt(index);
        }
      } else if (delta > 0) {
        globalCartItems.add({
          "id": food["id"],
          "name": food["name"],
          "price": food["price"],
          "qty": 1,
          "image": food["image"],
          "cafeId": widget.cafe["_id"] ?? widget.cafe["id"],
          "cafeteriaName": widget.cafe["name"] ?? "Campus Cafeteria",
          "location": widget.cafe["location"] ?? "Pickup counter",
        });
      }
    });
  }

  void _showMenuBottomSheet(bool isDark) {
    showModalBottomSheet(
        context: context,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(height: 16),
                  Text("EXPLORE MENU", style: TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w900, color: isDark ? Colors.white54 : Colors.grey.shade500, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  ...groupedFoods.keys.map((cat) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      title: Text(
                        cat,
                        style: TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF081F47)),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: appBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          "${groupedFoods[cat]!.length}",
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.bold, color: appBlue),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        final key = categoryKeys[cat];
                        if (key != null && key.currentContext != null) {
                          Scrollable.ensureVisible(
                            key.currentContext!,
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeInOutCubic,
                            alignment: 0.05,
                          );
                        }
                      },
                    );
                  }),
                ],
              ),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1000;
    final isTablet = size.width > 600 && size.width <= 1000;

    int totalCartItems = globalCartItems.fold(0, (sum, item) => sum + (item['qty'] as int));
    double totalCartPrice = globalCartItems.fold(0.0, (sum, item) => sum + ((item['price'] as num) * (item['qty'] as int)));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF4F8FD),
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CuteFoodBackgroundPainter(isDark: isDark, brandColor: appBlue),
            ),
          ),

          SafeArea(
            bottom: false,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: NotificationListener<UserScrollNotification>(
                          onNotification: (notification) {
                            if (notification.direction == ScrollDirection.reverse) {
                              if (_isMenuVisible || _isCartVisible) {
                                setState(() {
                                  _isMenuVisible = false;
                                  _isCartVisible = false;
                                });
                              }
                            } else if (notification.direction == ScrollDirection.forward) {
                              if (!_isMenuVisible || !_isCartVisible) {
                                setState(() {
                                  _isMenuVisible = true;
                                  _isCartVisible = true;
                                });
                              }
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1180),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 16),
                                      _buildTopBar(isDark),
                                      const SizedBox(height: 16),
                                      _buildSearchBar(isDark),
                                      const SizedBox(height: 20),
                                      _buildSectionHeader(isDark),
                                      _buildMenuCategories(isDark, isDesktop, isTablet),
                                      const SizedBox(height: 200),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.fastLinearToSlowEaseIn,
                    bottom: _isMenuVisible ? (totalCartItems > 0 ? 150.0 : 90.0) : -100.0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _isMenuVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Align(
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () => _showMenuBottomSheet(isDark),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white : const Color(0xFF081F47),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: (isDark ? Colors.white : Colors.black).withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.restaurant_menu_rounded, color: isDark ? const Color(0xFF081F47) : Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Text("MENU", style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: isDark ? const Color(0xFF081F47) : Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.fastLinearToSlowEaseIn,
                    bottom: _isCartVisible && totalCartItems > 0 ? 80.0 : -150.0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _isCartVisible && totalCartItems > 0 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: _buildFloatingCartBanner(totalCartItems, totalCartPrice),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomFloatingNavBar(
        currentIndex: 0,
        isDark: isDark,
        toggleTheme: widget.toggleTheme ?? () {},
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    // Reverting the top bar exactly to your requested layout
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            isDark: isDark,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.cafe['name'] ?? 'Menu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    color: isDark ? Colors.white : appBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.cafe['cuisine'] ?? 'Food Menu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: isDark ? Colors.white70 : const Color(0xFF5B6B89),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (widget.toggleTheme != null)
            _buildIconButton(
              icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              isDark: isDark,
              onTap: widget.toggleTheme!,
            ),
          const SizedBox(width: 8),
          _buildIconButton(
            icon: Icons.notifications_none_rounded,
            isDark: isDark,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPage())),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, required bool isDark, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: isDark ? Colors.white : appBlue, size: 18),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 15,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: TextField(
        focusNode: _searchFocusNode,
        onChanged: (value) {
          searchQuery = value;
          _filterFoods();
        },
        style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: 'Search delicious meals...',
          hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 13, color: isDark ? Colors.white54 : Colors.grey.shade500),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 10.0),
            child: Icon(Icons.search, size: 18, color: isDark ? Colors.white54 : Colors.grey.shade600),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        'Explore Menu',
        style: TextStyle(
          fontFamily: 'Nunito',
          color: isDark ? Colors.white : const Color(0xFF081F47),
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildMenuCategories(bool isDark, bool isDesktop, bool isTablet) {
    if (groupedFoods.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("No items found.", style: TextStyle(fontFamily: 'Inter'))));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groupedFoods.entries.map((entry) {
        return Column(
          key: categoryKeys[entry.key],
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
              child: Row(
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF081F47),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.grey.shade300, thickness: 1)),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entry.value.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                // This ensures the layout is responsive like the cafeteria page
                crossAxisCount: isDesktop ? 4 : (isTablet ? 3 : 2),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 290,
              ),
              itemBuilder: (context, index) {
                return _buildFoodCard(entry.value[index], isDark);
              },
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildFoodCard(Map<String, dynamic> food, bool isDark) {
    final qty = CartModel.getQty(food["id"]);
    final cardBg = isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
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
                  final imageUrl = food["image"]?.toString().trim() ?? '';
                  if (imageUrl.isEmpty) {
                    return const SizedBox(height: 110);
                  }
                  return Image.network(
                    imageUrl,
                    height: 110,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 110),
                  );
                },
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => FavoriteModel.toggleFavorite(food)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 3))]),
                    child: Icon(FavoriteModel.isFavorite(food["id"]) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Colors.redAccent, size: 16),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food["name"],
                        style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF10254E), fontSize: 13, height: 1.2),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        food["desc"],
                        style: TextStyle(fontFamily: 'Inter', color: isDark ? Colors.white54 : const Color(0xFF6B7280), fontSize: 10, fontWeight: FontWeight.w500, height: 1.3),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE8F0FF), borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 10),
                            const SizedBox(width: 2),
                            Text("${food['rating']}", style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF10254E))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text("(${food['reviews']})", style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: isDark ? Colors.white54 : const Color(0xFF6B7280))),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(border: Border.all(color: food['isVeg'] == true ? Colors.green : Colors.red, width: 1.0), borderRadius: BorderRadius.circular(4)),
                        child: Icon(Icons.circle, color: food['isVeg'] == true ? Colors.green : Colors.red, size: 5),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("₹${food["price"]}", style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : const Color(0xFF10254E))),
                      qty == 0
                          ? SizedBox(
                              height: 30,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: appBlue,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  elevation: 0,
                                ),
                                onPressed: () => _updateCart(food, 1),
                                child: const Text("ADD", style: TextStyle(fontFamily: 'Nunito', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5)),
                              ),
                            )
                          : Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(color: appBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: appBlue.withOpacity(0.3))),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(onTap: () => _updateCart(food, -1), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.remove, size: 14, color: appBlue))),
                                  Text("$qty", style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: appBlue, fontSize: 13)),
                                  InkWell(onTap: () => _updateCart(food, 1), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.add, size: 14, color: appBlue))),
                                ],
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
    );
  }

  Widget _buildFloatingCartBanner(int totalItems, double totalPrice) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CartPage(toggleTheme: widget.toggleTheme ?? () {})),
        ).then((_) {
          setState(() {});
        });
      },
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [appBlue, const Color(0xFF0033CC)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: appBlue.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("$totalItems Item${totalItems > 1 ? 's' : ''} in Cart", style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text("Checkout to proceed", style: TextStyle(fontFamily: 'Inter', color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w500, fontSize: 10)),
                ],
              ),
            ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("View Cart", style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                    Text("₹$totalPrice", style: const TextStyle(fontFamily: 'Nunito', color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 10)
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class CuteFoodBackgroundPainter extends CustomPainter {
  final bool isDark;
  final Color brandColor;

  CuteFoodBackgroundPainter({required this.isDark, required this.brandColor});

  @override
  void paint(Canvas canvas, Size size) {
    final Color topColor = isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFFDE8E8); 
    final Color bottomColor = isDark ? brandColor.withOpacity(0.15) : const Color(0xFFDDE6FF);

    final Paint blobPaint = Paint()
      ..shader = LinearGradient(colors: [topColor, bottomColor]).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
      
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.1), 160, blobPaint);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.7), 220, blobPaint);

    final iconColor = isDark ? Colors.white.withOpacity(0.03) : brandColor.withOpacity(0.04);

    void drawIcon(IconData icon, Offset position, double iconSize, double angle) {
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: iconSize,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: iconColor,
          ),
        ),
      );
      textPainter.layout();
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }

    drawIcon(Icons.donut_large_rounded, Offset(size.width * 0.85, size.height * 0.15), 180, 0.35); 
    drawIcon(Icons.cake_rounded, Offset(size.width * 0.1, size.height * 0.35), 150, -0.25); 
    drawIcon(Icons.fastfood_rounded, Offset(size.width * 0.9, size.height * 0.8), 200, -0.2); 
    drawIcon(Icons.emoji_food_beverage_rounded, Offset(size.width * 0.2, size.height * 0.85), 120, 0.2); 
    drawIcon(Icons.icecream_rounded, Offset(size.width * 0.5, size.height * 0.25), 80, 0.1); 
    drawIcon(Icons.local_pizza_rounded, Offset(size.width * 0.3, size.height * 0.6), 100, 0.3); 
    drawIcon(Icons.restaurant, Offset(size.width * 0.7, size.height * 0.5), 90, -0.15); 

    final random = math.Random(42);
    final dotColor = isDark ? Colors.white.withOpacity(0.05) : brandColor.withOpacity(0.06);
    
    for (int i = 0; i < 75; i++) {
      double x = random.nextDouble() * size.width;
      double y = random.nextDouble() * size.height;
      double r = random.nextDouble() * 1.5 + 1.0;
      canvas.drawCircle(Offset(x, y), r, Paint()..color = dotColor);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
