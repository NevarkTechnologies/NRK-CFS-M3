import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _primaryBlue = Color(0xFF0F4CFF);

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final cardColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF10254E);
    final sub = isDark ? Colors.white60 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: _primaryBlue, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('About Us', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 18, color: _primaryBlue)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F4CFF), Color(0xFF3B6FFF)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: _primaryBlue.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 30),
                        ),
                        const SizedBox(height: 18),
                        const Text('Nevark', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 28, color: Colors.white)),
                        const SizedBox(height: 6),
                        const Text(
                          'Technology for the modern cafeteria experience.',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Colors.white70, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _infoCard(cardColor: cardColor, isDark: isDark, icon: Icons.lightbulb_outline_rounded,
                    title: 'Who We Are',
                    body: 'Nevark is a technology company building smart cafeteria solutions for campuses and institutions. We connect students and staff to their campus dining through fast, reliable, and modern digital tools.',
                    text: text, sub: sub),
                  const SizedBox(height: 16),
                  _infoCard(cardColor: cardColor, isDark: isDark, icon: Icons.rocket_launch_rounded,
                    title: 'Our Mission',
                    body: 'To make campus food ordering effortless — eliminating queues, reducing wait times, and giving vendors real-time tools to run their cafeteria efficiently.',
                    text: text, sub: sub),
                  const SizedBox(height: 24),
                  Text('Links', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 16, color: text)),
                  const SizedBox(height: 12),
                  _linkTile(cardColor: cardColor, isDark: isDark, icon: Icons.language_rounded,
                    label: 'Visit our Website', sub: 'www.nevark.in',
                    onTap: () => _launch('https://nevark.in'), text: text, subColor: sub),
                  const SizedBox(height: 10),
                  _linkTile(cardColor: cardColor, isDark: isDark, icon: Icons.description_outlined,
                    label: 'Terms & Conditions', sub: 'Read our terms of service',
                    onTap: () => _launch('https://nevark.in/terms-condition'), text: text, subColor: sub),
                  const SizedBox(height: 10),
                  _linkTile(cardColor: cardColor, isDark: isDark, icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy', sub: 'How we handle your data',
                    onTap: () => _launch('https://nevark.in/privacy'), text: text, subColor: sub),
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      '© 2026 Nevark Technologies\nAll Rights Reserved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: sub, height: 1.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({required Color cardColor, required bool isDark, required IconData icon, required String title, required String body, required Color text, required Color sub}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: _primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _primaryBlue, size: 22)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 15, color: text)),
                const SizedBox(height: 6),
                Text(body, style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: sub, height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkTile({required Color cardColor, required bool isDark, required IconData icon, required String label, required String sub, required VoidCallback onTap, required Color text, required Color subColor}) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: _primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _primaryBlue, size: 20)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 14, color: text)),
                      Text(sub, style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: subColor)),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new_rounded, size: 16, color: subColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
