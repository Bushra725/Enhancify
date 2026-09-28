import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/illustrations.dart';
import 'discover_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _loading = false;
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => _open(AppConfig.termsUrl);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => _open(AppConfig.privacyUrl);

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DiscoverScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.blushGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 340,
                      height: 300,
                      child: HeroPhotos(),
                    ),
                  ),
                ),
                const Spacer(),
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Take your\nphotos to new\n'),
                    TextSpan(
                        text: 'heights',
                        style: TextStyle(color: AppColors.primary)),
                  ]),
                  style: TextStyle(
                    fontSize: 40,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A0A1A),
                  ),
                ),
                const SizedBox(height: 28),
                PillButton(
                  label: context.tr('getStarted'),
                  kind: ButtonStyleKind.brand,
                  loading: _loading,
                  onPressed: _start,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded),
                ),
                const SizedBox(height: 18),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        color: Color(0xFF6B4658), fontSize: 12.5),
                    children: [
                      const TextSpan(
                          text: 'By continuing, you accept our '),
                      TextSpan(
                        text: 'Terms of Service',
                        recognizer: _terms,
                        style: const TextStyle(
                            decoration: TextDecoration.underline,
                            color: AppColors.primary),
                      ),
                      const TextSpan(
                          text: ' and acknowledge receipt of our '),
                      TextSpan(
                        text: 'Privacy Policy',
                        recognizer: _privacy,
                        style: const TextStyle(
                            decoration: TextDecoration.underline,
                            color: AppColors.primary),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
