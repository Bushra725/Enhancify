import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../services/app_state.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/illustrations.dart';
import '../paywall/paywall_screen.dart';
import 'enhancer_preferences_screen.dart';
import 'privacy_preferences_screen.dart';
import 'subscription_info_screen.dart';
import 'suggest_feature_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _url(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'Could not open link.');
  }

  Future<void> _email(BuildContext context, String subject) async {
    final uri = Uri.parse('mailto:${AppConfig.supportEmail}'
        '?subject=${Uri.encodeComponent(subject)}');
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      showSnack(context, 'Email us at ${AppConfig.supportEmail}');
    }
  }

  Future<void> _redeem(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.surface,
        title: const Text('Use Redeem Code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Enter your code'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Redeem')),
        ],
      ),
    );
    // Dispose after the dialog's exit animation has finished.
    Future<void>.delayed(const Duration(milliseconds: 600), controller.dispose);
    if (code == null || code.isEmpty || !context.mounted) return;
    // Store codes are redeemed in the store; the subscription then
    // appears through Restore Purchases.
    final url = (!kIsWeb && Platform.isIOS)
        ? 'https://apps.apple.com/redeem?code=${Uri.encodeComponent(code)}'
        : 'https://play.google.com/redeem?code=${Uri.encodeComponent(code)}';
    await _url(context, url);
  }

  Future<void> _permissions(BuildContext context) async {
    final ps = await MediaService.galleryPermissionState();
    if (!context.mounted) return;
    final label = switch (ps) {
      PermissionState.authorized => 'Full access',
      PermissionState.limited => 'Limited access',
      PermissionState.denied => 'Denied',
      PermissionState.restricted => 'Restricted',
      PermissionState.notDetermined => 'Not asked yet',
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.surface,
        title: const Text('Photos Permissions'),
        content: Text('Current access: $label\n\n'
            '${AppConfig.appName} only reads the photos you choose to enhance.'),
        actions: [
          if (ps == PermissionState.limited)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await MediaService.presentLimited();
              },
              child: const Text('Select photos'),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (ps == PermissionState.notDetermined) {
                await MediaService.requestGalleryPermission();
              } else {
                await MediaService.openSettings();
              }
            },
            child: Text(ps == PermissionState.notDetermined
                ? 'Allow access'
                : 'Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.tr('settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 30),
        children: [
          _ProCard(isPro: state.isPro, tier: state.tier),
          const _AppearanceCard(),
          _Group('Social', [
            const _Item(Icons.share_outlined, 'Share App',
                onTap: MediaService.shareApp),
            _Item(Icons.camera_alt_outlined, 'Instagram',
                external: true,
                onTap: () => _url(context, AppConfig.instagramUrl)),
            _Item(Icons.facebook, 'Facebook',
                external: true,
                onTap: () => _url(context, AppConfig.facebookUrl)),
            _Item(Icons.music_note_outlined, 'TikTok',
                external: true,
                onTap: () => _url(context, AppConfig.tiktokUrl)),
          ]),
          _Group('Help', [
            _Item(Icons.help_outline, 'Help Center',
                external: true,
                onTap: () => _url(context, AppConfig.helpCenterUrl)),
            _Item(Icons.support_agent_outlined, 'Contact Support',
                external: true,
                onTap: () => _email(context, '${AppConfig.appName} support')),
            _Item(Icons.lightbulb_outline, 'Suggest A Feature',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SuggestFeatureScreen()))),
            _Item(Icons.receipt_long_outlined, 'Subscription Info',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SubscriptionInfoScreen()))),
            _Item(Icons.redeem_outlined, 'Use Redeem Code',
                onTap: () => _redeem(context)),
          ]),
          _Group('General', [
            _Item(Icons.photo_library_outlined, 'Photos Permissions',
                onTap: () => _permissions(context)),
            _Item(Icons.tune, 'Enhancer Preferences',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EnhancerPreferencesScreen()))),
          ]),
          _Group('Legal', [
            _Item(Icons.description_outlined, 'Terms of Service',
                external: true, onTap: () => _url(context, AppConfig.termsUrl)),
            _Item(Icons.privacy_tip_outlined, 'Privacy Policy',
                external: true,
                onTap: () => _url(context, AppConfig.privacyUrl)),
            _Item(Icons.shield_outlined, 'Privacy Preferences',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PrivacyPreferencesScreen()))),
            _Item(Icons.code, 'Open Source Libraries',
                onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConfig.appName)),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text('${AppConfig.appName} v1.0.0',
                style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tr = context.tr;
    return _Group(tr('appearance'), [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('theme'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.light, label: Text(tr('light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(tr('dark'))),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (s) => state.setThemeMode(s.first),
            ),
          ],
        ),
      ),
      _Item(Icons.language, tr('language'),
          trailing: Icons.chevron_right_rounded, onTap: () => _pickLanguage(context)),
    ]);
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final state = context.read<AppState>();
    final code = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in Tr.codes)
              ListTile(
                title: Text(Tr.names[c] ?? c),
                trailing: state.languageCode == c
                    ? const Icon(Icons.check, color: AppColors.red)
                    : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (code != null) await state.setLanguage(code);
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({required this.isPro, required this.tier});
  final bool isPro;
  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18, top: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPro
                      ? 'You are Pro 👑'
                      : tier == SubscriptionTier.lite
                          ? '${AppConfig.appName} Lite'
                          : AppConfig.proName,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 19,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                for (final t in const [
                  'Unlimited saves',
                  'Multiple results',
                  'No ads',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 16, color: AppColors.red),
                        const SizedBox(width: 6),
                        Text(t,
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 13)),
                      ],
                    ),
                  ),
                if (!isPro) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 150,
                    child: PillButton(
                      label: tier == SubscriptionTier.lite
                          ? 'Upgrade'
                          : 'Try Pro Now',
                      kind: ButtonStyleKind.dark,
                      height: 46,
                      onPressed: () => openPaywall(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(
            width: 100,
            height: 110,
            child: FittedBox(child: GiftBox(open: true, size: 90)),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.items);
  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DarkCard(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 4),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            ...items,
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(
    this.icon,
    this.label, {
    required this.onTap,
    this.external = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool external;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: context.palette.textSecondary),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: Icon(
        trailing ??
            (external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded),
        size: 20,
        color: context.palette.textSecondary,
      ),
    );
  }
}
