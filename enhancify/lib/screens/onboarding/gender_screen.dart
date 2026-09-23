import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import 'surprise_screen.dart';

class GenderScreen extends StatelessWidget {
  const GenderScreen({super.key});

  Future<void> _pick(BuildContext context, Gender g) async {
    await context.read<AppState>().setGender(g);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const SurpriseScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget option(String emoji, String label, Gender g) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _pick(context, g),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Icon(Icons.chevron_right, color: context.palette.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('Welcome to ${AppConfig.appName}!',
                  style: TextStyle(color: context.palette.textSecondary, fontSize: 15)),
              const SizedBox(height: 6),
              const Text("What's your gender?",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const Spacer(),
              option('👩', 'Female', Gender.female),
              option('👨', 'Male', Gender.male),
              option('⭐', 'Other', Gender.other),
              const Spacer(),
              Center(
                child: Text(
                  'We will only use this information to personalize your experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.textMuted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
