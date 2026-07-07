import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _primaryBlue = Color(0xFF0F4CFF);

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  }

  void _openRefundPolicy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _RefundPolicyPage(),
      ),
    );
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

      // bottom: false so the list scrolls behind the translucent system nav
      // like every other page; the ListView padding keeps content reachable.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),

              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),

              decoration: BoxDecoration(
                color: cardColor,

                borderRadius: BorderRadius.circular(22),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
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
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFFEAF2FF),

                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: _primaryBlue,
                        size: 20,
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  const Text(
                    'About Us',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: _primaryBlue,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16, 24, 16, 32 + MediaQuery.of(context).padding.bottom),

                children: [
                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.all(20),

                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F4CFF), Color.fromARGB(255, 130, 157, 232)],

                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),

                      borderRadius: BorderRadius.circular(24),

                      boxShadow: [
                        BoxShadow(
                          color: _primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Center(
                          child: Image.asset(
                            'assets/Nevark.png',
                            height: 70,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Center(
                          child: Text(
                            'GROUPS',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              color: const Color.fromARGB(179, 43, 42, 42),
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  _infoCard(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.groups_rounded,
                    title: 'Who We Are',
                    body:
                        'Nevark is an innovation-first technology company, developing futuristic products that turn bold ideas into real-world experiences.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 16),

                  _infoCard(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.rocket_launch_rounded,

                    title: 'Our Mission',

                    body:
                        'To make every campus meal instant, effortless, and queue-free, making students spend less time waiting and more time doing what matters.',

                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 16),

                  _linkTile(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.assignment_return_rounded,

                    label: 'Refund Policy',
                    sub: 'Cancellations, TAT & refunds',

                    onTap: () => _openRefundPolicy(context),
                    text: text,
                    subColor: sub,
                    trailingIcon: Icons.arrow_forward_ios_rounded,
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Links',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: text,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _linkTile(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.language_sharp,

                    label: 'Visit our Website',
                    sub: 'www.nevark.in',

                    onTap: () => _launch('https://nevark.in'),
                    text: text,
                    subColor: sub,
                  ),

                  const SizedBox(height: 10),

                  _linkTile(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.description_outlined,

                    label: 'Terms and Conditions',
                    sub: 'Read our terms of service',

                    onTap: () => _launch('https://nevark.in/terms-condition'),
                    text: text,
                    subColor: sub,
                  ),

                  const SizedBox(height: 10),

                  _linkTile(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.fingerprint_rounded,

                    label: 'Privacy Policy',
                    sub: 'How we handle your data',

                    onTap: () => _launch('https://nevark.in/privacy'),
                    text: text,
                    subColor: sub,
                  ),

                  const SizedBox(height: 26),

                  Center(
                    child: Text(
                      '© 2026 Nevark LLP\n All Rights Reserved',

                      textAlign: TextAlign.center,

                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: sub,
                        height: 1.8,
                      ),
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

  Widget _infoCard({
    required Color cardColor,
    required bool isDark,
    required IconData icon,
    required String title,
    required String body,
    required Color text,
    required Color sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primaryBlue, size: 22),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: GoogleFonts.ruluko(
                    
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: text,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  body,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: sub,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkTile({
    required Color cardColor,
    required bool isDark,
    required IconData icon,
    required String label,
    required String sub,
    required VoidCallback onTap,
    required Color text,
    required Color subColor,
    IconData trailingIcon = Icons.open_in_new_rounded,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(16),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _primaryBlue, size: 20),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        label,
                        style: GoogleFonts.ruluko(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: text,
                        ),
                      ),

                      Text(
                        sub,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(trailingIcon, size: 16, color: subColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefundPolicyPage extends StatelessWidget {
  const _RefundPolicyPage();

  static const _primaryBlue = Color(0xFF0F4CFF);

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
        bottom: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),

              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),

              decoration: BoxDecoration(
                color: cardColor,

                borderRadius: BorderRadius.circular(22),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),

              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Refund Policy',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: _primaryBlue,
                      ),
                    ),
                  ),

                  InkWell(
                    borderRadius: BorderRadius.circular(14),

                    onTap: () => Navigator.pop(context),

                    child: Container(
                      width: 44,
                      height: 44,

                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFFEAF2FF),

                        borderRadius: BorderRadius.circular(14),
                      ),

                      child: const Icon(
                        Icons.close_rounded,
                        color: _primaryBlue,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16, 24, 16, 32 + MediaQuery.of(context).padding.bottom),

                children: [
                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.info_outline_rounded,
                    title: 'Overview',
                    body:
                        'This Refund Policy applies to all orders placed through BenchBites. By placing an order, you agree to the terms outlined below. This policy is designed to be fair to both students and campus food partners.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.cancel_schedule_send_rounded,
                    title: 'Order Cancellation',
                    body:
                        '• Once payment is completed, the order is confirmed and cannot be cancelled.\n'
                        '• Please review your items, customisations, and pickup details carefully before completing payment.\n'
                        '• We recommend double-checking your order summary on the payment screen, as it cannot be modified afterward.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Eligibility for Refund',
                    body:
                        'Refunds are applicable in the following cases:\n'
                        '• Order not delivered or not ready for pickup within a reasonable time.\n'
                        '• Item(s) missing from the order.\n'
                        '• Wrong item delivered.\n'
                        '• Food quality issue reported with valid image proof within 30 minutes of pickup/delivery.\n'
                        '• Payment deducted but order not placed due to a technical failure.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.block_rounded,
                    title: 'Non-Refundable Cases',
                    body:
                        '• Change of mind after the vendor has started preparing the order.\n'
                        '• Delay caused by the student not being present at the pickup point/counter.\n'
                        '• Incorrect order details entered by the student (e.g. wrong customisation).\n'
                        '• Complaints raised after 30 minutes of order completion.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.timer_outlined,
                    title: 'Refund Turnaround Time (TAT)',
                    body:
                        '• Refund request review: within 24-48 hours of raising the request.\n'
                        '• Once approved, refunds are initiated within 1-2 business days.\n'
                        '• UPI/Wallet refunds typically reflect within 2-4 business days.\n'
                        '• Card/Net Banking refunds may take 5-7 business days depending on the issuing bank.\n',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Refund Method',
                    body:
                        'Refunds are processed to the original payment method used at checkout. If the original method is unavailable, the amount will be credited to your preferred payment method after confirmation.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.support_agent_rounded,
                    title: 'How to Request a Refund',
                    body:
                        'Refund requests are handled via email and require proof of the payment deduction. To raise a request:\n\n'
                        '1. Take a screenshot of the payment deduction (bank/UPI app confirmation).\n'
                        '2. Note down the Payment ID from your transaction.\n'
                        '3. Email the screenshot and Payment ID to team@nevark.in.\n'
                        '4. Use the subject line: "<PAYMENT ID> - Request for Refund".\n\n'
                        'Our team will verify the details and respond with the status of your refund.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 14),

                  _section(
                    cardColor: cardColor,
                    isDark: isDark,
                    icon: Icons.mail_outline_rounded,
                    title: 'Need Help?',
                    body:
                        'For any refund or payment related concerns, email team@nevark.in with your Payment ID. We aim to respond within 48 hours.',
                    text: text,
                    sub: sub,
                  ),

                  const SizedBox(height: 20),

                  Center(
                    child: Text(
                      'This policy may be updated periodically.\nLast updated: July 2026',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: sub,
                        height: 1.8,
                      ),
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

  Widget _section({
    required Color cardColor,
    required bool isDark,
    required IconData icon,
    required String title,
    required String body,
    required Color text,
    required Color sub,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(18),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primaryBlue, size: 18),
              ),

              const SizedBox(width: 12),

              Text(
                title,
                style: GoogleFonts.ruluko(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: text,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            body,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: sub,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}