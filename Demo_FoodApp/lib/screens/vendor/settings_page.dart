import '../../utils/b64_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/session.dart';
import '../../services/api_service.dart';
import 'vendor_data.dart';
import 'vendor_page_wrapper.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback toggleTheme;

  const SettingsPage({super.key, required this.toggleTheme});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isEditing = false;
  bool isSaving = false;

  late TextEditingController nameCtrl,
      descCtrl,
      phoneCtrl,
      emailCtrl,
      addressCtrl,
      cityCtrl,
      pinCtrl;

  Set<String> selectedCuisines = {};
  final List<String> cuisineOptions = [
    'North Indian',
    'South Indian',
    'Chinese',
    'Continental',
    'Fast Food',
    'Cafe',
    'Bakery',
    'Italian',
    'Seafood',
    'Vegetarian',
    'Vegan',
    'Fusion',
  ];

  bool orderNotif = true;
  bool emailNotif = true;
  bool smsNotif = true;

  String? _pickedImageBase64;
  String _currentImageUrl = '';
  bool isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _currentImageUrl = VendorData.displayImage;
    nameCtrl = TextEditingController(
      text: VendorData.displayName == "Not set yet"
          ? ""
          : VendorData.displayName,
    );
    descCtrl = TextEditingController(
      text: VendorData.displayDescription == "Not set yet"
          ? ""
          : VendorData.displayDescription,
    );

    // Phone field: Initialize with +91 prefix
    final phone = VendorData.displayPhone;
    phoneCtrl = TextEditingController(
      text: (phone == "Not set yet" || phone.isEmpty) ? "+91" : phone,
    );

    emailCtrl = TextEditingController(
      text: VendorData.displayEmail == "Not set yet"
          ? ""
          : VendorData.displayEmail,
    );
    addressCtrl = TextEditingController(
      text: VendorData.displayAddress == "Not set yet"
          ? ""
          : VendorData.displayAddress,
    );
    cityCtrl = TextEditingController(
      text: VendorData.displayCity == "Not set yet"
          ? ""
          : VendorData.displayCity,
    );
    pinCtrl = TextEditingController(
      text: VendorData.displayPin == "Not set yet" ? "" : VendorData.displayPin,
    );

    // Initialize selected cuisines
    final cuisineStr = VendorData.displayCuisine;
    if (cuisineStr != "Not set yet") {
      selectedCuisines = cuisineStr.split(',').map((c) => c.trim()).toSet();
    }
  }

  bool get _hasValidBusinessDetails {
    final phoneText = phoneCtrl.text.trim();
    bool isPhoneValid =
        phoneText.isNotEmpty &&
        phoneText.startsWith('+91') &&
        phoneText.length == 13 &&
        int.tryParse(phoneText.substring(3)) != null;

    final pinText = pinCtrl.text.trim();
    bool isPinValid =
        pinText.isNotEmpty &&
        pinText.length == 6 &&
        int.tryParse(pinText) != null;

    return nameCtrl.text.trim().isNotEmpty &&
        selectedCuisines.isNotEmpty &&
        descCtrl.text.trim().isNotEmpty &&
        isPhoneValid &&
        emailCtrl.text.trim().isNotEmpty &&
        addressCtrl.text.trim().isNotEmpty &&
        cityCtrl.text.trim().isNotEmpty &&
        isPinValid;
  }

  void toggleEdit() => setState(() => isEditing = !isEditing);

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 65,
      maxWidth: 1200,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    setState(() {
      _pickedImageBase64 = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  Widget _buildImageUploadSection(Color text, bool isDark) {
    final hasImage = _pickedImageBase64 != null || _currentImageUrl.isNotEmpty;
    final displayImage = _pickedImageBase64 ?? _currentImageUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cafeteria Photo',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontFamily: 'Inter',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEditing
                    ? primaryBlue.withValues(alpha: 0.4)
                    : Colors.grey.shade300,
                width: 1.5,
              ),
            ),
            child: Stack(
              children: [
                if (hasImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: _buildCafeImage(displayImage, double.infinity, 160),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 40,
                          color: isDark ? Colors.white38 : Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No photo uploaded',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade400,
                            fontSize: 13,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isEditing)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: primaryBlue,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: primaryBlue.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.upload_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Upload Photo',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
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
          ),
        ],
      ),
    );
  }

  Widget _buildCafeImage(String src, double width, double height) {
    if (src.startsWith('data:image/')) {
      final base64Data = src.split(',').last;
      return Image.memory(
        B64ImageCache.decode(base64Data),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: Colors.grey.shade200),
      );
    }
    if (src.contains('assets/')) {
      return Image.asset(
        src,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: Colors.grey.shade200),
      );
    }
    return Image.network(
      src,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: Colors.grey.shade200),
    );
  }

  Future<void> saveChanges() async {
    if (!_hasValidBusinessDetails) {
      String errorMsg = 'Please complete all fields correctly:\n';
      if (nameCtrl.text.trim().isEmpty) {
        errorMsg += '• Restaurant name required\n';
      }
      if (selectedCuisines.isEmpty) {
        errorMsg += '• Select at least one cuisine\n';
      }
      if (descCtrl.text.trim().isEmpty) errorMsg += '• Description required\n';
      if (phoneCtrl.text.trim().isEmpty ||
          !phoneCtrl.text.trim().startsWith('+91') ||
          phoneCtrl.text.trim().length != 13) {
        errorMsg += '• Valid phone with +91 prefix (13 chars total)\n';
      }
      if (emailCtrl.text.trim().isEmpty) errorMsg += '• Email required\n';
      if (addressCtrl.text.trim().isEmpty) errorMsg += '• Address required\n';
      if (cityCtrl.text.trim().isEmpty) errorMsg += '• City required\n';
      if (pinCtrl.text.trim().isEmpty || pinCtrl.text.trim().length != 6) {
        errorMsg += '• PIN code must be 6 digits\n';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      // Ensure we have the latest user data - fallback when cafeId missing
      if (AppSession.cafeId.isEmpty && AppSession.userId.isNotEmpty) {
        try {
          final updated = await ApiService.updateUser(AppSession.userId, {});
          await AppSession.setUser(updated);
        } catch (_) {
          // ignore; we'll check cafeId below and surface a proper error
        }
      }

      final cafeId = AppSession.cafeId;

      if (cafeId.isEmpty) {
        throw Exception('Cafe ID not found. Please log in again.');
      }

      // Update cafe details
      final cafeUpdate = {
        'name': nameCtrl.text.trim(),
        'cuisine': selectedCuisines.join(', '),
        'description': descCtrl.text.trim(),
        'location': addressCtrl.text.trim(),
        'city': cityCtrl.text.trim(),
        'pin': pinCtrl.text.trim(),
        if (_pickedImageBase64 != null) 'image': _pickedImageBase64,
        if (_pickedImageBase64 != null) 'imageType': 'base64',
      };

      final firebaseToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final authHeaders = {
        'Content-Type': 'application/json',
        if (firebaseToken != null) 'Authorization': 'Bearer $firebaseToken',
      };

      final cafeResponse = await http
          .patch(
            Uri.parse('${ApiService.baseUrl}/cafes/$cafeId'),
            headers: authHeaders,
            body: jsonEncode(cafeUpdate),
          )
          .timeout(const Duration(seconds: 10));

      if (cafeResponse.statusCode != 200) {
        throw Exception('Failed to update cafe: ${cafeResponse.statusCode}');
      }

      // Update user phone
      final userId = AppSession.userId;
      if (userId.isNotEmpty) {
        final userUpdate = {'phone': phoneCtrl.text.trim()};
        final userResponse = await http
            .patch(
              Uri.parse('${ApiService.baseUrl}/users/$userId'),
              headers: authHeaders,
              body: jsonEncode(userUpdate),
            )
            .timeout(const Duration(seconds: 10));

        if (userResponse.statusCode != 200) {
          throw Exception('Failed to update user: ${userResponse.statusCode}');
        }
      }

      // Update session
      final cafe = Map<String, dynamic>.from(AppSession.cafe ?? {});
      cafe['name'] = nameCtrl.text.trim();
      cafe['cuisine'] = selectedCuisines.join(', ');
      cafe['description'] = descCtrl.text.trim();
      cafe['location'] = addressCtrl.text.trim();
      cafe['city'] = cityCtrl.text.trim();
      cafe['pin'] = pinCtrl.text.trim();
      if (_pickedImageBase64 != null) {
        cafe['image'] = _pickedImageBase64;
        cafe['imageType'] = 'base64';
        _currentImageUrl = _pickedImageBase64!;
        _pickedImageBase64 = null;
      }

      final current = AppSession.currentUser;
      if (current != null) {
        current['cafeId'] = cafe;
        current['phone'] = phoneCtrl.text.trim();
        current['email'] = emailCtrl.text.trim();
        await AppSession.setUser(current);
      }

      setState(() => isEditing = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Settings saved successfully!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 600;
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    Color bgColor = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    Color cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    Color textColor = isDark ? Colors.white : const Color(0xFF081F47);

    // ✅ WRAP WITH VENDOR PAGE WRAPPER
    return VendorPageWrapper(
      pageTitle: "Settings", // ✅ Top bar title
      selectedMenuIndex: 5, // ✅ Highlight "Settings" in menu
      toggleTheme: widget.toggleTheme,
      child: PopScope(
        canPop: _hasValidBusinessDetails,
        child: Scaffold(
          backgroundColor: bgColor,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    /// 🔹 BUSINESS DETAILS
                    buildCard(
                      "Business Details",
                      Icons.store_rounded,
                      Column(
                        children: [
                          _buildImageUploadSection(textColor, isDark),
                          buildField(
                            "Restaurant Name",
                            nameCtrl,
                            textColor,
                            isDark,
                          ),
                          buildCuisineSelector(textColor, isDark),
                          buildField(
                            "Description",
                            descCtrl,
                            textColor,
                            isDark,
                            maxLines: 3,
                          ),
                          buildPhoneField(textColor, isDark),
                          buildField("Email", emailCtrl, textColor, isDark),
                        ],
                      ),
                      cardColor,
                      textColor,
                      isDark,
                    ).animate().fade().slideY(begin: 0.1),

                    /// 🔹 LOCATION
                    buildCard(
                      "Location",
                      Icons.location_on_rounded,
                      Column(
                        children: [
                          buildField("Address", addressCtrl, textColor, isDark),
                          isMobile
                              ? Column(
                                  children: [
                                    buildField(
                                      "City",
                                      cityCtrl,
                                      textColor,
                                      isDark,
                                    ),
                                    buildField(
                                      "PIN",
                                      pinCtrl,
                                      textColor,
                                      isDark,
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: buildField(
                                        "City",
                                        cityCtrl,
                                        textColor,
                                        isDark,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: buildField(
                                        "PIN",
                                        pinCtrl,
                                        textColor,
                                        isDark,
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                      cardColor,
                      textColor,
                      isDark,
                    ).animate().fade(delay: 100.ms).slideY(begin: 0.1),

                    /// 🔹 NOTIFICATIONS
                    buildCard(
                      "Notifications",
                      Icons.notifications_rounded,
                      Column(
                        children: [
                          buildSwitch(
                            "New Order Alerts",
                            orderNotif,
                            (v) => setState(() => orderNotif = v),
                            textColor,
                          ),
                          buildSwitch(
                            "Email Notifications (Coming Soon)",
                            false,
                            null,
                            Colors.grey,
                          ),

                          buildSwitch(
                            "SMS Alerts (Coming Soon)",
                            false,
                            null,
                            Colors.grey,
                          ),
                        ],
                      ),
                      cardColor,
                      textColor,
                      isDark,
                    ).animate().fade(delay: 200.ms).slideY(begin: 0.1),

                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 20),
            child: ElevatedButton.icon(
              onPressed: (!isEditing || (_hasValidBusinessDetails && !isSaving))
                  ? (isEditing ? saveChanges : toggleEdit)
                  : null,
              icon: Icon(
                isSaving
                    ? null
                    : (isEditing ? Icons.save_rounded : Icons.edit_rounded),
                size: 16,
              ),
              label: Text(
                isSaving ? "Saving..." : (isEditing ? "Save" : "Edit Profile"),
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isEditing
                    ? (_hasValidBusinessDetails ? Colors.green : Colors.grey)
                    : primaryBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCard(
    String title,
    IconData icon,
    Widget child,
    Color card,
    Color text,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: card,
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
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryBlue, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget buildField(
    String label,
    TextEditingController ctrl,
    Color text,
    bool isDark, {
    int maxLines = 1,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        enabled: (label == "Email") ? false : isEditing,
        maxLines: maxLines,
        obscureText: obscure,
        onChanged: (val) => setState(() {}),
        style: TextStyle(
          color: text,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey.shade500,
            fontFamily: 'Inter',
          ),
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontFamily: 'Inter',
          ),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildCuisineSelector(Color text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Cuisine Type',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontFamily: 'Inter',
                fontSize: 12,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cuisineOptions.map((cuisine) {
                  final isSelected = selectedCuisines.contains(cuisine);
                  return FilterChip(
                    label: Text(
                      cuisine,
                      style: TextStyle(
                        color: isSelected ? Colors.white : text,
                        fontSize: 12,
                        fontFamily: 'Inter',
                      ),
                    ),
                    selected: isSelected,
                    onSelected: isEditing
                        ? (selected) {
                            setState(() {
                              if (selected) {
                                selectedCuisines.add(cuisine);
                              } else {
                                selectedCuisines.remove(cuisine);
                              }
                            });
                          }
                        : null,
                    backgroundColor: Colors.transparent,
                    selectedColor: primaryBlue,
                    side: BorderSide(
                      color: isSelected ? primaryBlue : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPhoneField(Color text, bool isDark) {
    final phoneText = phoneCtrl.text.trim();
    final digitsOnly = phoneText.replaceFirst(RegExp(r'^\+91'), '');
    final isPhoneValid =
        phoneText.isNotEmpty &&
        phoneText.startsWith('+91') &&
        phoneText.length == 13 &&
        int.tryParse(digitsOnly) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: phoneCtrl,
        enabled: isEditing,
        keyboardType: TextInputType.phone,
        maxLength: 13,
        style: TextStyle(
          color: text,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
        onChanged: (val) {
          // Prevent deletion of +91 prefix
          if (!val.startsWith('+91')) {
            phoneCtrl.text = '+91';
            phoneCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: 3),
            );
          } else if (val.length > 13) {
            // Limit to +91 + 10 digits = 13 chars
            phoneCtrl.text = val.substring(0, 13);
            phoneCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: 13),
            );
          } else {
            // Only allow digits after +91
            final prefix = val.substring(0, 3);
            final digits = val.substring(3).replaceAll(RegExp(r'[^0-9]'), '');
            phoneCtrl.text = prefix + digits;
            phoneCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: prefix.length + digits.length),
            );
          }
          setState(() {});
        },
        decoration: InputDecoration(
          labelText: "Phone (+91)",
          labelStyle: TextStyle(
            color: Colors.grey.shade500,
            fontFamily: 'Inter',
          ),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          counterText: '',
          suffixIcon: phoneText.length > 3
              ? (isPhoneValid
                    ? Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : Icon(Icons.error, color: Colors.red, size: 20))
              : null,
          helperText: (phoneText.length > 3 && !isPhoneValid)
              ? 'Phone must be exactly 10 digits'
              : null,
          helperStyle: const TextStyle(
            color: Colors.redAccent,
            fontSize: 11,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  Widget buildSwitch(
    String title,
    bool value,
    Function(bool)? onChanged,
    Color text,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          activeThumbColor: primaryBlue,
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              color: text,
            ),
          ),
          value: value,
          onChanged: isEditing ? onChanged : null,
        ),
      ),
    );
  }
}
