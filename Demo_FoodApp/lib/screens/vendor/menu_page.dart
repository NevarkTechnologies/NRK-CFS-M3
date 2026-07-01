import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import 'vendor_page_wrapper.dart';

/// Capitalizes the first letter of each word as the user types,
/// e.g. "chicken biryani" -> "Chicken Biryani".
class _TitleCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final buffer = StringBuffer();
    var capitalizeNext = true;
    for (final char in text.split('')) {
      if (char.trim().isEmpty) {
        buffer.write(char);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
      }
    }
    final formatted = buffer.toString();
    if (formatted == text) return newValue;
    return TextEditingValue(
      text: formatted,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class MenuItemModel {
  final String id;
  String name;
  int price;
  String category;
  bool available;
  String image;

  MenuItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.available = true,
    this.image = '',
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: (json['price'] is num)
          ? (json['price'] as num).toInt()
          : int.tryParse(json['price']?.toString() ?? '0') ?? 0,
      category: json['category']?.toString() ?? 'Others',
      available: json['available'] != null ? json['available'] as bool : true,
      image: json['image']?.toString() ?? '',
    );
  }
}

class MenuPage extends StatefulWidget {
  final VoidCallback toggleTheme;
  const MenuPage({super.key, required this.toggleTheme});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isLoading = true;
  List<MenuItemModel> menu = [];
  // Tracks which categories are collapsed. Absent/false => expanded (default).
  final Map<String, bool> _collapsedCategories = {};

  Map<String, List<MenuItemModel>> groupByCategory() {
    final grouped = <String, List<MenuItemModel>>{};
    for (var item in menu) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  List<String> getCategoryOptions() {
    final normalized = <String, String>{};
    for (var item in menu) {
      final category = item.category.trim();
      if (category.isEmpty) continue;
      final lower = category.toLowerCase();
      if (!normalized.containsKey(lower)) {
        normalized[lower] = normalizeCategory(category);
      }
    }
    return normalized.values.toList();
  }

  String normalizeCategory(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return 'Others';
    return trimmed
        .split(RegExp(r'\s+'))
        .map(
          (part) => part.isEmpty
              ? ''
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String canonicalCategory(String category) {
    final normalized = normalizeCategory(category);
    for (var existing in getCategoryOptions()) {
      if (existing.toLowerCase() == normalized.toLowerCase()) {
        return existing;
      }
    }
    return normalized;
  }

  @override
  void initState() {
    super.initState();
    loadMenu();
  }

  Future<void> loadMenu() async {
    setState(() {
      isLoading = true;
    });

    try {
      final cafeId = AppSession.cafeId;
      if (cafeId.isEmpty) {
        throw Exception('Vendor cafe id missing');
      }
      final items = await ApiService.getMenu(cafeId: cafeId);
      if (!mounted) return;
      setState(() {
        menu = items.map((item) => MenuItemModel.fromJson(item)).toList();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> addItem(Color cardColor, Color textColor) async {
    String name = '';
    String selectedCategory = '';
    String customCategory = '';
    bool useCustomCategory = false;
    int price = 0;
    Uint8List? selectedImageBytes;
    String selectedImageDataUrl = '';
    final categories = getCategoryOptions();
    const customOption = 'Create new category';
    if (categories.isNotEmpty) {
      selectedCategory = categories.first;
    } else {
      selectedCategory = customOption;
      useCustomCategory = true;
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final categoryItems = [...categories, customOption];
          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Add New Item',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _inputField(
                    'Item Name',
                    (v) => setDialogState(() => name = v),
                    textColor,
                    titleCase: true,
                  ),
                  if (categories.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Category',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontFamily: 'Inter',
                          ),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: useCustomCategory
                                ? customOption
                                : selectedCategory,
                            isExpanded: true,
                            items: categoryItems.map((categoryValue) {
                              return DropdownMenuItem<String>(
                                value: categoryValue,
                                child: Text(
                                  categoryValue,
                                  style: TextStyle(
                                    color: textColor,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                if (value == customOption) {
                                  useCustomCategory = true;
                                  customCategory = '';
                                } else {
                                  useCustomCategory = false;
                                  selectedCategory = value;
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  if (useCustomCategory)
                    _inputField(
                      'New Category',
                      (v) => setDialogState(() => customCategory = v),
                      textColor,
                    ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey.withValues(alpha: 0.08),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selectedImageBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              selectedImageBytes!,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        ElevatedButton.icon(
                          icon: const Icon(Icons.image),
                          label: Text(
                            selectedImageBytes != null
                                ? 'Replace photo'
                                : 'Upload photo',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final pickedImage = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                            );
                            if (pickedImage == null) return;
                            final bytes = await pickedImage.readAsBytes();
                            final mimeType =
                                pickedImage.mimeType ?? 'image/png';
                            setDialogState(() {
                              selectedImageBytes = bytes;
                              selectedImageDataUrl =
                                  'data:$mimeType;base64,${base64Encode(bytes)}';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _inputField(
                    'Price (₹)',
                    (v) => setDialogState(() => price = int.tryParse(v) ?? 0),
                    textColor,
                    isNumber: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.grey,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);

                  if (name.isEmpty || price <= 0) return;
                  Navigator.pop(context);

                  final cafeId = AppSession.cafeId;
                  final vendorId = AppSession.vendorId;

                  if (cafeId.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Vendor cafe id missing'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }

                  final rawCategory = useCustomCategory
                      ? customCategory
                      : selectedCategory;
                  final savedCategory = canonicalCategory(
                    rawCategory.isEmpty ? 'Others' : rawCategory,
                  );

                  try {
                    final newItem = await ApiService.createMenuItem(
                      name: name,
                      price: price,
                      category: savedCategory,
                      cafeId: cafeId,
                      vendorId: vendorId,
                      image: selectedImageDataUrl,
                      imageType: selectedImageDataUrl.isNotEmpty
                          ? 'base64'
                          : 'none',
                    );

                    if (!mounted) return;

                    setState(() {
                      menu.add(MenuItemModel.fromJson(newItem));
                    });

                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Menu item added successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (error) {
                    if (!mounted) return;

                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          error.toString().replaceFirst('Exception: ', ''),
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                child: const Text(
                  'Save Item',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _inputField(
    String label,
    Function(String) onChanged,
    Color textColor, {
    bool isNumber = false,
    bool titleCase = false,
    TextEditingController? controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textCapitalization: titleCase
            ? TextCapitalization.words
            : TextCapitalization.none,
        inputFormatters: titleCase ? [_TitleCaseTextFormatter()] : null,
        style: TextStyle(
          color: textColor,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey.shade500,
            fontFamily: 'Inter',
          ),
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Future<void> toggleAvailability(MenuItemModel item) async {
    try {
      final updated = await ApiService.updateMenuItem(item.id, {
        'available': !item.available,
      });
      if (!mounted) return;
      setState(() {
        item.available = updated['available'] as bool? ?? !item.available;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> deleteItem(MenuItemModel item) async {
    try {
      await ApiService.deleteMenuItem(item.id);
      if (!mounted) return;
      setState(() {
        menu.removeWhere((m) => m.id == item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menu item deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void openEditDialog(MenuItemModel item, Color cardColor, Color textColor) {
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.price.toString());
    final categories = getCategoryOptions();
    const customOption = 'Create new category';
    String selectedCategory = canonicalCategory(item.category);
    String customCategory = '';
    bool useCustomCategory = false;
    // Ensure the item's current category is selectable even if it somehow
    // isn't part of the derived options list.
    if (!categories.any(
      (c) => c.toLowerCase() == selectedCategory.toLowerCase(),
    )) {
      categories.insert(0, selectedCategory);
    }
    Uint8List? selectedImageBytes;
    String selectedImageDataUrl = '';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final categoryItems = [...categories, customOption];
          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Edit Item',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _inputField(
                    'Item Name',
                    (_) {},
                    textColor,
                    titleCase: true,
                    controller: nameController,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontFamily: 'Inter',
                        ),
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: useCustomCategory
                              ? customOption
                              : selectedCategory,
                          isExpanded: true,
                          items: categoryItems.map((categoryValue) {
                            return DropdownMenuItem<String>(
                              value: categoryValue,
                              child: Text(
                                categoryValue,
                                style: TextStyle(
                                  color: textColor,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              if (value == customOption) {
                                useCustomCategory = true;
                                customCategory = '';
                              } else {
                                useCustomCategory = false;
                                selectedCategory = value;
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  if (useCustomCategory)
                    _inputField(
                      'New Category',
                      (v) => setDialogState(() => customCategory = v),
                      textColor,
                    ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey.withValues(alpha: 0.08),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selectedImageBytes != null ||
                            item.image.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: selectedImageBytes != null
                                ? Image.memory(
                                    selectedImageBytes!,
                                    height: 140,
                                    fit: BoxFit.cover,
                                  )
                                : _buildMenuItemImage(item.image),
                          ),
                          const SizedBox(height: 10),
                        ],
                        ElevatedButton.icon(
                          icon: const Icon(Icons.image),
                          label: Text(
                            selectedImageBytes != null
                                ? 'Replace photo'
                                : item.image.isNotEmpty
                                ? 'Change photo'
                                : 'Upload photo',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final pickedImage = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 60,
                            );
                            if (pickedImage == null) return;
                            final bytes = await pickedImage.readAsBytes();
                            final mimeType =
                                pickedImage.mimeType ?? 'image/png';
                            setDialogState(() {
                              selectedImageBytes = bytes;
                              selectedImageDataUrl =
                                  'data:$mimeType;base64,${base64Encode(bytes)}';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _inputField(
                    'Price (₹)',
                    (_) {},
                    textColor,
                    isNumber: true,
                    controller: priceController,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.grey,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: () async {
                  final navigator = Navigator.of(context);

                  final rawCategory = useCustomCategory
                      ? customCategory
                      : selectedCategory;
                  final savedCategory = canonicalCategory(
                    rawCategory.isEmpty ? 'Others' : rawCategory,
                  );

                  await updateMenuItem(
                    item.id,
                    nameController.text,
                    savedCategory,
                    priceController.text,
                    image: selectedImageDataUrl.isNotEmpty
                        ? selectedImageDataUrl
                        : null,
                    imageType: selectedImageDataUrl.isNotEmpty ? 'base64' : null,
                  );

                  if (!mounted) return;
                  navigator.pop();
                },
                child: const Text(
                  'Save Item',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> updateMenuItem(
    String id,
    String name,
    String category,
    String price, {
    String? image,
    String? imageType,
  }) async {
    try {
      final data = {
        'name': name,
        'category': category,
        'price': double.parse(price),
      };
      if (image != null && image.isNotEmpty) {
        data['image'] = image;
        if (imageType != null) {
          data['imageType'] = imageType;
        }
      }
      final response = await ApiService.updateMenuItem(id, data);
      if (!mounted) return;
      setState(() {
        final index = menu.indexWhere((m) => m.id == id);
        if (index != -1) {
          menu[index] = MenuItemModel.fromJson(response);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menu item updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildMenuItemImage(String imageUrl) {
    if (imageUrl.startsWith('data:')) {
      final base64Part = imageUrl.split(',').last;
      try {
        final bytes = base64Decode(base64Part);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.fastfood_rounded,
            color: Colors.blueGrey,
            size: 40,
          ),
        );
      } catch (_) {
        return const Icon(
          Icons.fastfood_rounded,
          color: Colors.blueGrey,
          size: 40,
        );
      }
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.fastfood_rounded, color: Colors.blueGrey, size: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedMenu = groupByCategory();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark
        ? const Color(0xFF020617)
        : const Color(0xFFF4F6F9);
    final Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF081F47);

    return VendorPageWrapper(
      pageTitle: 'Menu Management',
      selectedMenuIndex: 3,
      toggleTheme: widget.toggleTheme,
      child: Scaffold(
        backgroundColor: bgColor,
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : menu.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 80,
                      color: Colors.grey.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your menu is empty',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click + Add Item to get started',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: groupedMenu.entries.map((entry) {
                  final bool collapsed =
                      _collapsedCategories[entry.key] ?? false;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() {
                          _collapsedCategories[entry.key] = !collapsed;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              Text(
                                '${entry.value.length}',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade500,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: collapsed ? -0.25 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.expand_more_rounded,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fade().slideX(),
                      if (!collapsed) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: entry.value
                              .map(
                                (item) => buildCard(
                                  item,
                                  cardColor,
                                  textColor,
                                  isDark,
                                ),
                              )
                              .toList(),
                        ).animate().fade(delay: 100.ms),
                      ],
                      const SizedBox(height: 32),
                    ],
                  );
                }).toList(),
              ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: primaryBlue,
          onPressed: () => addItem(cardColor, textColor),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget buildCard(
    MenuItemModel item,
    Color cardColor,
    Color textColor,
    bool isDark,
  ) {
    return Container(
      width: MediaQuery.of(context).size.width > 600
          ? 240
          : (MediaQuery.of(context).size.width / 2) - 24,
      padding: const EdgeInsets.all(16),
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
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey.withValues(alpha: 0.1),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.image.isEmpty
                ? Icon(
                    Icons.fastfood_rounded,
                    color: primaryBlue.withValues(alpha: 0.5),
                    size: 40,
                  )
                : _buildMenuItemImage(item.image),
          ),
          const SizedBox(height: 16),
          Text(
            item.name,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: textColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${item.price}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              color: primaryBlue,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 190;

              return isSmall
                  ? Column(
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: item.available
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: () => toggleAvailability(item),
                            icon: Icon(
                              item.available
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: item.available ? Colors.green : Colors.red,
                              size: 22,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      openEditDialog(item, cardColor, textColor),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                  onPressed: () => deleteItem(item),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: item.available
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: () => toggleAvailability(item),
                            icon: Icon(
                              item.available
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              color: item.available ? Colors.green : Colors.red,
                              size: 22,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.blue,
                              size: 18,
                            ),
                            onPressed: () =>
                                openEditDialog(item, cardColor, textColor),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Container(
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            onPressed: () => deleteItem(item),
                          ),
                        ),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}
