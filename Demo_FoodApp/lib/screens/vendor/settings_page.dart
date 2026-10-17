import '../../utils/b64_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/session.dart';
import '../../services/api_service.dart';
import '../../services/order_print_service.dart';
import '../../services/order_speech_service.dart';
import '../../services/printer_transport.dart';
import '../../services/receipt_builder.dart';
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
    _loadVoiceAvailability();
    _loadPrinterSettings();
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

  @override
  void dispose() {
    // NOTE: this page had no dispose() at all — the profile controllers below
    // were already leaking. Added here rather than disposing only the two new
    // printer fields, which would have looked like an oversight.
    nameCtrl.dispose();
    descCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    addressCtrl.dispose();
    cityCtrl.dispose();
    pinCtrl.dispose();
    _printerIpCtrl.dispose();
    _printerPortCtrl.dispose();
    super.dispose();
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
          duration: const Duration(seconds: 1),
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

      final firebaseToken = await FirebaseAuth.instance.currentUser
          ?.getIdToken();
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
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 1),
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

                    /// 🔹 ORDER ANNOUNCEMENTS
                    buildCard(
                      "Order Announcements",
                      Icons.campaign_rounded,
                      _buildAnnouncementSettings(textColor, isDark),
                      cardColor,
                      textColor,
                      isDark,
                    ).animate().fade(delay: 250.ms).slideY(begin: 0.1),

                    /// 🔹 ORDER PRINTING
                    // Hidden on web: a browser can open neither a raw socket
                    // nor a Bluetooth link, so there is nothing to offer there.
                    if (OrderPrintService.instance.isSupported)
                      buildCard(
                        "Order Printing",
                        Icons.print_rounded,
                        _buildPrinterSettings(textColor, isDark),
                        cardColor,
                        textColor,
                        isDark,
                      ).animate().fade(delay: 300.ms).slideY(begin: 0.1),

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

  // FEATURE: spoken "One new order, token N" alerts. These are per-device
  // preferences rather than cafe profile fields, so they save immediately and
  // are deliberately not gated behind the Edit Profile mode.
  Map<String, bool> _voiceAvailable = {};

  Future<void> _loadVoiceAvailability() async {
    await OrderSpeechService.instance.loadPreferences();
    final availability = <String, bool>{};
    for (final code in OrderSpeechService.announcementLanguages.keys) {
      availability[code] = await OrderSpeechService.instance
          .isLanguageAvailable(code);
    }
    if (mounted) setState(() => _voiceAvailable = availability);
  }

  Widget _buildAnnouncementSettings(Color text, bool isDark) {
    final service = OrderSpeechService.instance;
    final missing = OrderSpeechService.announcementLanguages.keys
        .where((code) => _voiceAvailable[code] == false)
        .map((code) => OrderSpeechService.announcementLanguages[code])
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: service.announcementsEnabled,
          builder: (context, enabled, _) => Material(
            color: Colors.transparent,
            child: SwitchListTile(
              activeThumbColor: primaryBlue,
              contentPadding: EdgeInsets.zero,
              title: Text(
                "Announce New Orders",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  color: text,
                ),
              ),
              subtitle: Text(
                'Reads "One new order, token 12" aloud while this page is open',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: text.withValues(alpha: 0.6),
                ),
              ),
              value: enabled,
              onChanged: service.setAnnouncementsEnabled,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Announcement language",
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: text.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<String>(
          valueListenable: service.announcementLanguage,
          builder: (context, selected, _) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: OrderSpeechService.announcementLanguages.entries.map((
              entry,
            ) {
              // null availability = not checked yet; assume usable rather than
              // locking the vendor out while the engine is still starting.
              final usable = _voiceAvailable[entry.key] != false;
              return ChoiceChip(
                label: Text(entry.value),
                selected: selected == entry.key,
                onSelected: usable
                    ? (_) => service.setAnnouncementLanguage(entry.key)
                    : null,
                labelStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: selected == entry.key
                      ? Colors.white
                      : text.withValues(alpha: usable ? 0.85 : 0.35),
                ),
                selectedColor: primaryBlue,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            "$missing not installed on this device. Add the voice under "
            "Settings → System → Languages & input → Text-to-speech output → "
            "Install voice data.",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              height: 1.5,
              color: Colors.orange.shade700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => OrderSpeechService.instance.previewAnnouncement(),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text(
              "Test announcement",
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryBlue,
              side: BorderSide(color: primaryBlue.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // FEATURE: thermal kitchen tickets. Per-device settings like the
  // announcement ones — the printer is physically attached to this one phone,
  // so they save immediately and are deliberately not gated behind Edit
  // Profile, and they are never synced to the server.
  final TextEditingController _printerIpCtrl = TextEditingController();
  final TextEditingController _printerPortCtrl = TextEditingController();
  List<PairedDevice> _pairedPrinters = const [];
  List<String> _discoveredPrinters = const [];
  bool _loadingPaired = false;
  bool _scanningNetwork = false;

  /// null = not checked yet, so the status row stays quiet rather than
  /// claiming the printer is offline before anything has been tried.
  bool? _printerOnline;

  Future<void> _loadPrinterSettings() async {
    final printer = OrderPrintService.instance;
    if (!printer.isSupported) return;
    await printer.loadSettings();
    if (!mounted) return;
    _printerIpCtrl.text = printer.config.value.ip;
    _printerPortCtrl.text = printer.config.value.port.toString();
    setState(() {});
    if (printer.config.value.connection == PrinterConnection.bluetooth) {
      await _refreshPairedPrinters();
    }
    await _refreshPrinterStatus();
  }

  Future<void> _refreshPairedPrinters() async {
    setState(() => _loadingPaired = true);
    // Requests BLUETOOTH_CONNECT if it has not been granted yet — Android 12+
    // needs it at runtime, the manifest entry alone is not enough.
    final devices = await OrderPrintService.instance.pairedDevices();
    if (!mounted) return;
    setState(() {
      _pairedPrinters = devices;
      _loadingPaired = false;
    });
  }

  Future<void> _refreshPrinterStatus() async {
    final printer = OrderPrintService.instance;
    if (!printer.isReady) {
      if (mounted) setState(() => _printerOnline = null);
      return;
    }
    final online = await printer.probe();
    if (!mounted) return;
    setState(() => _printerOnline = online);
  }

  Future<void> _scanForPrinters() async {
    setState(() {
      _scanningNetwork = true;
      _discoveredPrinters = const [];
    });
    final port =
        int.tryParse(_printerPortCtrl.text.trim()) ?? PrinterConfig.defaultPort;
    final found = await OrderPrintService.instance.scanForNetworkPrinters(
      port: port,
    );
    if (!mounted) return;
    setState(() {
      _discoveredPrinters = found;
      _scanningNetwork = false;
    });
    if (found.isEmpty) {
      _toast(
        'No printers found on this network. Check the printer is switched on '
        'and joined to the same Wi-Fi.',
      );
    }
  }

  Future<void> _testPrint() async {
    try {
      await OrderPrintService.instance.testPrint();
      if (!mounted) return;
      _toast('Test ticket sent to the printer');
    } catch (error) {
      if (!mounted) return;
      _toast(error.toString(), isError: true);
    }
    await _refreshPrinterStatus();
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildPrinterSettings(Color text, bool isDark) {
    final printer = OrderPrintService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── How orders are handled ────────────────────────────────────────
        // The one setting here that changes how service actually runs, so it
        // leads and spells out the consequence rather than just naming a mode.
        _printerLabel('When an order arrives', text),
        const SizedBox(height: 10),
        ValueListenableBuilder<OrderHandlingMode>(
          valueListenable: printer.orderMode,
          builder: (context, mode, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _printerChip(
                    label: 'Manual',
                    selected: mode == OrderHandlingMode.manual,
                    onTap: () => printer.setOrderMode(OrderHandlingMode.manual),
                    text: text,
                    isDark: isDark,
                  ),
                  _printerChip(
                    label: 'Automatic',
                    selected: mode == OrderHandlingMode.auto,
                    onTap: () => printer.setOrderMode(OrderHandlingMode.auto),
                    text: text,
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                mode == OrderHandlingMode.auto
                    ? 'Orders are accepted and the ticket prints on its own. '
                          'You can still reject one before it is handed over.'
                    : 'You tap Accept on each order, and the ticket prints '
                          'then. Rejected orders never print.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  height: 1.5,
                  color: text.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 32),

        // ── Connection ────────────────────────────────────────────────────
        _printerLabel('Printer connection', text),
        const SizedBox(height: 10),
        ValueListenableBuilder<PrinterConfig>(
          valueListenable: printer.config,
          builder: (context, config, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _printerChip(
                    label: 'Off',
                    selected: config.connection == PrinterConnection.off,
                    onTap: () async {
                      await printer.setConnection(PrinterConnection.off);
                      await _refreshPrinterStatus();
                    },
                    text: text,
                    isDark: isDark,
                  ),
                  _printerChip(
                    label: 'Bluetooth',
                    selected: config.connection == PrinterConnection.bluetooth,
                    onTap: () async {
                      await printer.setConnection(PrinterConnection.bluetooth);
                      await _refreshPairedPrinters();
                      await _refreshPrinterStatus();
                    },
                    text: text,
                    isDark: isDark,
                  ),
                  _printerChip(
                    label: 'Wi-Fi / LAN',
                    selected: config.connection == PrinterConnection.network,
                    onTap: () async {
                      await printer.setConnection(PrinterConnection.network);
                      await _refreshPrinterStatus();
                    },
                    text: text,
                    isDark: isDark,
                  ),
                ],
              ),
              if (config.connection == PrinterConnection.bluetooth) ...[
                const SizedBox(height: 16),
                _buildBluetoothPicker(config, text, isDark),
              ],
              if (config.connection == PrinterConnection.network) ...[
                const SizedBox(height: 16),
                _buildNetworkPicker(config, text, isDark),
              ],
            ],
          ),
        ),

        // ── Paper, copies, status ─────────────────────────────────────────
        const Divider(height: 32),
        _printerLabel('Paper width', text),
        const SizedBox(height: 10),
        ValueListenableBuilder<PaperWidth>(
          valueListenable: printer.paper,
          builder: (context, paper, _) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: PaperWidth.values
                .map(
                  (width) => _printerChip(
                    label: width.label,
                    selected: paper == width,
                    onTap: () => printer.setPaper(width),
                    text: text,
                    isDark: isDark,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        ValueListenableBuilder<int>(
          valueListenable: printer.copies,
          builder: (context, copies, _) => Row(
            children: [
              Expanded(child: _printerLabel('Copies per order', text)),
              IconButton(
                onPressed: copies > 1
                    ? () => printer.setCopies(copies - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: primaryBlue,
              ),
              Text(
                '$copies',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: text,
                ),
              ),
              IconButton(
                onPressed: copies < 3
                    ? () => printer.setCopies(copies + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: primaryBlue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _buildPrinterStatusRow(text),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _testPrint,
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text(
              "Test print",
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryBlue,
              side: BorderSide(color: primaryBlue.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothPicker(PrinterConfig config, Color text, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _printerLabel('Paired printers', text)),
            IconButton(
              onPressed: _loadingPaired ? null : _refreshPairedPrinters,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: primaryBlue,
              tooltip: 'Refresh list',
            ),
          ],
        ),
        if (_loadingPaired)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_pairedPrinters.isEmpty)
          Text(
            'No paired printers found. Pair the printer once in Android '
            'Settings → Bluetooth, then tap refresh.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              height: 1.5,
              color: Colors.orange.shade700,
            ),
          )
        else
          ..._pairedPrinters.map(
            (device) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                Icons.bluetooth_rounded,
                color: primaryBlue,
                size: 20,
              ),
              title: Text(
                device.name.isEmpty ? device.mac : device.name,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: text,
                ),
              ),
              subtitle: Text(
                device.mac,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: text.withValues(alpha: 0.5),
                ),
              ),
              trailing: config.btMac == device.mac
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: primaryBlue,
                      size: 20,
                    )
                  : null,
              onTap: () async {
                await OrderPrintService.instance.setBluetoothDevice(device);
                await _refreshPrinterStatus();
              },
            ),
          ),
      ],
    );
  }

  Widget _buildNetworkPicker(PrinterConfig config, Color text, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _printerIpCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(fontFamily: 'Inter', color: text),
                decoration: const InputDecoration(
                  labelText: 'Printer IP address',
                  hintText: '192.168.1.87',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _printerPortCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(fontFamily: 'Inter', color: text),
                decoration: const InputDecoration(
                  labelText: 'Port',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () async {
                await OrderPrintService.instance.setNetworkTarget(
                  _printerIpCtrl.text,
                  int.tryParse(_printerPortCtrl.text.trim()) ??
                      PrinterConfig.defaultPort,
                );
                await _refreshPrinterStatus();
                if (mounted) _toast('Printer address saved');
              },
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save address'),
            ),
            TextButton.icon(
              onPressed: _scanningNetwork ? null : _scanForPrinters,
              icon: _scanningNetwork
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find_rounded, size: 18),
              label: Text(_scanningNetwork ? 'Scanning…' : 'Scan for printers'),
            ),
          ],
        ),
        // Saves the vendor having to find the printer's IP by hand, which is
        // not a reasonable thing to ask of a canteen owner.
        ..._discoveredPrinters.map(
          (ip) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.print_rounded, color: primaryBlue, size: 20),
            title: Text(
              ip,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: text,
              ),
            ),
            trailing: config.ip == ip
                ? Icon(Icons.check_circle_rounded, color: primaryBlue, size: 20)
                : null,
            onTap: () async {
              _printerIpCtrl.text = ip;
              await OrderPrintService.instance.setNetworkTarget(
                ip,
                int.tryParse(_printerPortCtrl.text.trim()) ??
                    PrinterConfig.defaultPort,
              );
              await _refreshPrinterStatus();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrinterStatusRow(Color text) {
    final printer = OrderPrintService.instance;
    if (!printer.isReady) {
      return Text(
        'No printer selected yet.',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: text.withValues(alpha: 0.6),
        ),
      );
    }

    final online = _printerOnline;
    final color = online == null
        ? Colors.grey
        : (online ? Colors.green : Colors.redAccent);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            online == null
                ? 'Checking ${printer.config.value.label}…'
                : (online
                      ? 'Connected to ${printer.config.value.label}'
                      : 'Cannot reach ${printer.config.value.label}'),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: text.withValues(alpha: 0.7),
            ),
          ),
        ),
        IconButton(
          onPressed: _refreshPrinterStatus,
          icon: const Icon(Icons.sync_rounded, size: 18),
          color: primaryBlue,
          tooltip: 'Check connection',
        ),
      ],
    );
  }

  Widget _printerLabel(String label, Color text) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: text.withValues(alpha: 0.7),
      ),
    );
  }

  /// Same chip styling as the announcement language picker, so the two cards
  /// read as one settings screen rather than two.
  Widget _printerChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color text,
    required bool isDark,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: selected ? Colors.white : text.withValues(alpha: 0.85),
      ),
      selectedColor: primaryBlue,
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
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
