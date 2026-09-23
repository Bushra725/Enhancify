import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/ads_service.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../settings/privacy_preferences_screen.dart';
import 'gender_screen.dart';

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  Future<void> _finish(BuildContext context,
      {required bool analytics, required bool ads}) async {
    final state = context.read<AppState>();
    final adsService = context.read<AdsService>();
    await state.setConsent(analytics: analytics, personalizedAds: ads);
    adsService.init();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GenderScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Welcome to ${AppConfig.appName}! 👋',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
              const SizedBox(height: 6),
              const Text('Customize your\nexperience 🫶',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              const Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    'We use tracking technologies that either are essential for '
                    'the app to function correctly or are used to produce '
                    'aggregated statistics. With your consent, we and our '
                    'third-party partners will also use tracking technologies '
                    'to improve the in-app experience, and to provide you with '
                    'personalized services and targeted advertising. To give '
                    'your consent, tap Accept All and Continue.\n\n'
                    'Alternatively, you can customize your privacy settings by '
                    'tapping Customize Preferences, or by going to Privacy '
                    'Settings at any time. If you don\'t want us to use '
                    'non-technical tracking technologies, tap Refuse.\n\n'
                    'For more information about how we process your personal '
                    'data, please read our Privacy Policy.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 15, height: 1.45),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'Accept All and Continue',
                onPressed: () => _finish(context, analytics: true, ads: true),
              ),
              const SizedBox(height: 12),
              PillButton(
                label: 'Refuse',
                onPressed: () => _finish(context, analytics: false, ads: false),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<(bool, bool)>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const PrivacyPreferencesScreen(onboarding: true),
                      ),
                    );
                    if (result != null && context.mounted) {
                      await _finish(context, analytics: result.$1, ads: result.$2);
                    }
                  },
                  child: const Text(
                    'Customize Preferences',
                    style: TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
