import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.maroon, AppColors.maroonDeep, AppColors.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
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
                const Text(
                  'Take your\nphotos to new\nheights',
                  style: TextStyle(
                    fontSize: 40,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 28),
                PillButton(
                  label: 'Get Started',
                  loading: _loading,
                  onPressed: _start,
                  trailing: const Icon(Icons.arrow_forward_ios_rounded),
                ),
                const SizedBox(height: 18),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                    children: [
                      const TextSpan(
                          text: 'By continuing, you accept our '),
                      TextSpan(
                        text: 'Terms of Service',
                        recognizer: _terms,
                        style: const TextStyle(
                            decoration: TextDecoration.underline,
                            color: Colors.white),
                      ),
                      const TextSpan(
                          text: ' and acknowledge receipt of our '),
                      TextSpan(
                        text: 'Privacy Policy',
                        recognizer: _privacy,
                        style: const TextStyle(
                            decoration: TextDecoration.underline,
                            color: Colors.white),
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
