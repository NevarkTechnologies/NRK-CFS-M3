import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'vendor_data.dart';
import 'vendor_page_wrapper.dart'; // ✅ Import wrapper

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Color primaryBlue = const Color(0xFF0F4CFF);
  bool isEditing = false;

  late TextEditingController nameCtrl,
      cuisineCtrl,
      descCtrl,
      phoneCtrl,
      emailCtrl,
      addressCtrl,
      cityCtrl,
      pinCtrl;
  bool orderNotif = VendorData.orderNotif;
  bool emailNotif = VendorData.emailNotif;
  bool smsNotif = VendorData.smsNotif;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: VendorData.displayName);
    cuisineCtrl = TextEditingController(text: VendorData.displayCuisine);
    descCtrl = TextEditingController(text: VendorData.displayDescription);
    phoneCtrl = TextEditingController(text: VendorData.displayPhone);
    emailCtrl = TextEditingController(text: VendorData.displayEmail);
    addressCtrl = TextEditingController(text: VendorData.displayAddress);
    cityCtrl = TextEditingController(text: VendorData.displayCity);
    pinCtrl = TextEditingController(text: VendorData.displayPin);
  }

  void toggleEdit() => setState(() => isEditing = !isEditing);

  void saveChanges() {
    VendorData.name = nameCtrl.text;
    VendorData.cuisine = cuisineCtrl.text;
    VendorData.description = descCtrl.text;
    VendorData.phone = phoneCtrl.text;
    VendorData.email = emailCtrl.text;
    VendorData.address = addressCtrl.text;
    VendorData.city = cityCtrl.text;
    VendorData.pin = pinCtrl.text;
    VendorData.orderNotif = orderNotif;
    VendorData.emailNotif = emailNotif;
    VendorData.smsNotif = smsNotif;
    setState(() => isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Changes Saved Successfully!"),
        backgroundColor: Colors.green,
      ),
    );
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
      pageTitle: "Settings",                  // ✅ Top bar title
      selectedMenuIndex: 5,                   // ✅ Highlight "Settings" in menu
      toggleTheme: () {},                     // Pass your theme toggle function
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
                        buildField("Restaurant Name", nameCtrl, textColor, isDark),
                        buildField("Cuisine Type", cuisineCtrl, textColor, isDark),
                        buildField("Description", descCtrl, textColor, isDark, maxLines: 3),
                        buildField("Phone", phoneCtrl, textColor, isDark),
                        buildField("Email", emailCtrl, textColor, isDark),
                      ],
                    ),
                    cardColor,
                    textColor,
                    isDark,
                  )
                      .animate()
                      .fade()
                      .slideY(begin: 0.1),

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
                                  buildField("City", cityCtrl, textColor, isDark),
                                  buildField("PIN", pinCtrl, textColor, isDark),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: buildField("City", cityCtrl, textColor, isDark)),
                                  const SizedBox(width: 16),
                                  Expanded(child: buildField("PIN", pinCtrl, textColor, isDark)),
                                ],
                              ),
                      ],
                    ),
                    cardColor,
                    textColor,
                    isDark,
                  )
                      .animate()
                      .fade(delay: 100.ms)
                      .slideY(begin: 0.1),

                  /// 🔹 NOTIFICATIONS
                  buildCard(
                    "Notifications",
                    Icons.notifications_rounded,
                    Column(
                      children: [
                        buildSwitch("New Order Alerts", orderNotif, (v) => setState(() => orderNotif = v), textColor),
                        buildSwitch("Email Notifications", emailNotif, (v) => setState(() => emailNotif = v), textColor),
                        buildSwitch("SMS Alerts", smsNotif, (v) => setState(() => smsNotif = v), textColor),
                      ],
                    ),
                    cardColor,
                    textColor,
                    isDark,
                  )
                      .animate()
                      .fade(delay: 200.ms)
                      .slideY(begin: 0.1),

               

                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 20),
          child: ElevatedButton.icon(
            onPressed: isEditing ? saveChanges : toggleEdit,
            icon: Icon(isEditing ? Icons.save_rounded : Icons.edit_rounded, size: 16),
            label: Text(
              isEditing ? "Save" : "Edit Profile",
              style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isEditing ? Colors.green : primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCard(String title, IconData icon, Widget child, Color card, Color text, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
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
                  color: primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryBlue, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: text),
              )
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget buildField(String label, TextEditingController ctrl, Color text, bool isDark,
      {int maxLines = 1, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        enabled: isEditing,
        maxLines: maxLines,
        obscureText: obscure,
        style: TextStyle(color: text, fontFamily: 'Inter', fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontFamily: 'Inter'),
          filled: true,
          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildSwitch(String title, bool value, Function(bool) onChanged, Color text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: SwitchListTile(
        activeColor: primaryBlue,
        contentPadding: EdgeInsets.zero,
        title: Text(title,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: text)),
        value: value,
        onChanged: isEditing ? onChanged : null,
      ),
    );
  }
}
