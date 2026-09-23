import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../paywall/paywall_screen.dart';

class SubscriptionInfoScreen extends StatefulWidget {
  const SubscriptionInfoScreen({super.key});

  @override
  State<SubscriptionInfoScreen> createState() => _SubscriptionInfoScreenState();
}

class _SubscriptionInfoScreenState extends State<SubscriptionInfoScreen> {
  bool _restoring = false;

  Future<void> _manage() async {
    final url = (!kIsWeb && Platform.isIOS)
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions?package=${AppConfig.androidPackage}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final msg = await context.read<PurchaseService>().restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    showSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = switch (state.tier) {
      SubscriptionTier.pro => 'Pro',
      SubscriptionTier.lite => 'Lite',
      SubscriptionTier.free => 'Free',
    };
    String left(String key, int limit, {bool liteUnlimited = true}) {
      final r = state.remaining(key, limit, liteUnlimited: liteUnlimited);
      return r < 0 ? 'Unlimited' : '$r of $limit left today';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription Info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DarkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current plan',
                    style: TextStyle(color: context.palette.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(plan,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900)),
                    if (state.isPro) ...[
                      const SizedBox(width: 8),
                      const ProBadge(),
                    ],
                  ],
                ),
                const Divider(height: 28),
                _row('Photo enhancements',
                    left(UsageKeys.enhance, AppConfig.freeEnhancementsPerDay)),
                _row('AI filters',
                    left(UsageKeys.filter, AppConfig.freeFiltersPerDay)),
                _row('Saves', left(UsageKeys.save, AppConfig.freeSavesPerDay)),
                _row('Ads', state.showAds ? 'Shown' : 'None'),
                _row('Video enhance', state.isPro ? 'Included' : 'Pro only'),
                _row('AI photo full packs', state.isPro ? 'Included' : 'Pro only'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!state.isPro)
            PillButton(
              label: state.isPaid ? 'Upgrade to Pro' : 'See plans',
              kind: ButtonStyleKind.brand,
              onPressed: () => openPaywall(context),
            ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Restore Purchases',
            kind: ButtonStyleKind.outline,
            loading: _restoring,
            onPressed: _restore,
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Manage Subscription',
            kind: ButtonStyleKind.outline,
            onPressed: _manage,
          ),
          const SizedBox(height: 16),
          Text(
            'Subscriptions renew automatically unless cancelled at least 24 '
            'hours before the end of the current period. Manage or cancel '
            'anytime in your store account settings.',
            style: TextStyle(color: context.palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(a)),
            Text(b, style: TextStyle(color: context.palette.textSecondary)),
          ],
        ),
      );
}
