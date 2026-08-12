import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

// FEATURE 2026-08-12: Non-dismissable "Update required" gate. Shown when the
// backend reports the installed build is below the minimum supported version.
// On mount it launches Google Play's immediate update flow; the buttons let the
// user retry it or open the store listing directly. There is no way past this
// screen without updating — back is blocked.
class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({super.key});

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.nevark.foodapp';
  static const _primaryBlue = Color(0xFF0F4CFF);
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    // Trigger the immediate update as soon as the gate appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runUpdate());
  }

  Future<void> _runUpdate() async {
    if (_launching) return;
    setState(() => _launching = true);
    await UpdateService.startImmediateUpdate();
    // If Play completes the update it restarts the app; if we get here the user
    // dismissed or it was unavailable — stay on the gate and let them retry.
    if (mounted) setState(() => _launching = false);
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(_playStoreUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF020617) : const Color(0xFFF4F6F9);
    final textColor = isDark ? Colors.white : const Color(0xFF10254E);
    final subText = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.system_update_rounded,
                        color: _primaryBlue, size: 48),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Update Required',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A newer version of BenchBites is required to continue. '
                    'Please update to keep ordering.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      height: 1.6,
                      color: subText,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _launching ? null : _runUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _launching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Update Now',
                              style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _openStore,
                    child: const Text('Open Play Store',
                        style: TextStyle(color: _primaryBlue)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
