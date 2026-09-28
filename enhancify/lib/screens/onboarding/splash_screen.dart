import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import 'onboarding_screen.dart';

/// Short animated opening before home or onboarding.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onboarded});

  final bool onboarded;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future<void>.delayed(const Duration(milliseconds: 2300), _next);
  }

  void _next() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        settings: RouteSettings(name: widget.onboarded ? 'home' : 'onboard'),
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: widget.onboarded ? const HomeScreen() : const OnboardingScreen(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0.15, 0.7, curve: Curves.easeOut));
    final rise = Tween<double>(begin: 24, end: 0).animate(fade);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF7FB), Color(0xFFFFD6E8), Color(0xFFFFF4F9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const _SparkleField(),
            Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final scale = 0.86 + 0.14 * Curves.easeOutBack.transform(_c.value.clamp(0, 1));
                  return Opacity(
                    opacity: fade.value,
                    child: Transform.translate(
                      offset: Offset(0, rise.value),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 52),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      AppConfig.appName,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2A0A1A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('splashTagline'),
                      style: const TextStyle(color: Color(0xFF8A4B66), fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparkleField extends StatefulWidget {
  const _SparkleField();

  @override
  State<_SparkleField> createState() => _SparkleFieldState();
}

class _SparkleFieldState extends State<_SparkleField> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        return CustomPaint(
          painter: _SparklePainter(_spin.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFEA026A);
    const spots = [
      Offset(0.18, 0.22),
      Offset(0.82, 0.18),
      Offset(0.12, 0.72),
      Offset(0.78, 0.68),
      Offset(0.5, 0.12),
      Offset(0.88, 0.46),
    ];
    for (var i = 0; i < spots.length; i++) {
      final wobble = math.sin((t + i * 0.17) * math.pi * 2);
      final c = Offset(spots[i].dx * size.width, spots[i].dy * size.height + wobble * 8);
      paint.color = const Color(0xFFEA026A).withValues(alpha: 0.18 + 0.12 * wobble.abs());
      canvas.drawCircle(c, 5 + (i % 3), paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}
