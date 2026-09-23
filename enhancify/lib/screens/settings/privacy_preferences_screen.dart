import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Consent toggles. In onboarding mode it pops `(analytics, ads)`;
/// otherwise it saves directly.
class PrivacyPreferencesScreen extends StatefulWidget {
  const PrivacyPreferencesScreen({super.key, this.onboarding = false});
  final bool onboarding;

  @override
  State<PrivacyPreferencesScreen> createState() =>
      _PrivacyPreferencesScreenState();
}

class _PrivacyPreferencesScreenState extends State<PrivacyPreferencesScreen> {
  late bool _analytics;
  late bool _ads;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _analytics = widget.onboarding ? false : s.analyticsConsent;
    _ads = widget.onboarding ? false : s.personalizedAdsConsent;
  }

  Future<void> _save() async {
    if (widget.onboarding) {
      Navigator.of(context).pop((_analytics, _ads));
      return;
    }
    await context
        .read<AppState>()
        .setConsent(analytics: _analytics, personalizedAds: _ads);
    if (!mounted) return;
    showSnack(context, 'Privacy preferences saved');
    Navigator.of(context).pop();
  }

  Widget _tile(String title, String sub, bool value, ValueChanged<bool>? onChanged) {
    return DarkCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(sub,
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile('Strictly necessary',
              'Required for the app to work. Always on.', true, null),
          const SizedBox(height: 12),
          _tile('Analytics',
              'Anonymous statistics that help us improve the app.',
              _analytics, (v) => setState(() => _analytics = v)),
          const SizedBox(height: 12),
          _tile('Personalized ads',
              'Allow partners to show ads based on your interests.',
              _ads, (v) => setState(() => _ads = v)),
          const SizedBox(height: 28),
          PillButton(label: 'Save preferences', onPressed: _save),
        ],
      ),
    );
  }
}
