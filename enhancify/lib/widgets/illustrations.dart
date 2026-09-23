import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Two tilted "before / after" photo cards for the welcome screen.
class HeroPhotos extends StatelessWidget {
  const HeroPhotos({super.key});

  Widget _card(double angle, List<Color> colors, bool sharp) => Transform.rotate(
        angle: angle,
        child: Container(
          width: 170,
          height: 200,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 18)],
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.face_retouching_natural,
                    size: 90,
                    color: Colors.white.withValues(alpha: sharp ? 0.95 : 0.35)),
                if (!sharp)
                  Container(color: Colors.white.withValues(alpha: 0.18)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 30,
            top: 20,
            child: _card(-0.18,
                const [Color(0xFFD9A7B0), Color(0xFF8A5A63)], false),
          ),
          Positioned(
            right: 30,
            top: 70,
            child: _card(0.14, const [AppColors.redLight, AppColors.maroon], true),
          ),
          const Positioned(
              left: 24, top: 12, child: _Spark(size: 10, circle: true)),
          const Positioned(right: 60, top: 18, child: _Spark(size: 12)),
          const Positioned(left: 110, bottom: 10, child: _Spark(size: 10)),
          const Positioned(
              right: 26, bottom: 30, child: _Spark(size: 8, circle: true)),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({required this.size, this.circle = false});
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) => circle
      ? Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 1.5),
          ),
        )
      : Icon(Icons.close, size: size + 4, color: Colors.white70);
}

/// Gift box with an optional open state and a gentle wobble.
class GiftBox extends StatefulWidget {
  const GiftBox({super.key, this.open = false, this.size = 170});
  final bool open;
  final double size;

  @override
  State<GiftBox> createState() => _GiftBoxState();
}

class _GiftBoxState extends State<GiftBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        final wobble = widget.open ? 0.0 : math.sin(t * math.pi * 2) * 0.05;
        return Transform.rotate(
          angle: wobble,
          child: SizedBox(
            width: s * 1.2,
            height: s * 1.35,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                if (widget.open)
                  Positioned(
                    bottom: s * 0.7 + t * 10,
                    child: Icon(Icons.star_rounded,
                        size: s * 0.6, color: AppColors.gold),
                  ),
                // box body
                Container(
                  width: s,
                  height: s * 0.72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6F8B), Color(0xFFB0123A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.5),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(width: s * 0.16, color: const Color(0xFFFFD1DC)),
                      Positioned(
                        left: s * 0.12,
                        top: s * 0.12,
                        child: Text('?',
                            style: TextStyle(
                                fontSize: s * 0.26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white70)),
                      ),
                      Positioned(
                        right: s * 0.1,
                        bottom: s * 0.06,
                        child: Text('?',
                            style: TextStyle(
                                fontSize: s * 0.22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
                // lid
                Positioned(
                  bottom: s * 0.66 + (widget.open ? s * 0.35 : 0),
                  child: Transform.rotate(
                    angle: widget.open ? -0.5 : 0,
                    child: Container(
                      width: s * 1.1,
                      height: s * 0.2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF8FA5), Color(0xFFD01E4A)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                          width: s * 0.16, color: const Color(0xFFFFD1DC)),
                    ),
                  ),
                ),
                if (!widget.open)
                  Positioned(
                    bottom: s * 0.84,
                    child: Icon(Icons.card_giftcard,
                        size: s * 0.3, color: const Color(0xFFFFD1DC)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Floating confetti dots behind the gift.
class Confetti extends StatelessWidget {
  const Confetti({super.key});

  @override
  Widget build(BuildContext context) {
    final rnd = math.Random(7);
    const colors = [
      AppColors.gold,
      Colors.white,
      AppColors.redLight,
      Color(0xFF7CF6D0),
      Color(0xFF8AA4FF),
    ];
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        return Stack(
          children: List.generate(40, (i) {
            return Positioned(
              left: rnd.nextDouble() * c.maxWidth,
              top: rnd.nextDouble() * c.maxHeight,
              child: Transform.rotate(
                angle: rnd.nextDouble() * math.pi,
                child: Container(
                  width: 4 + rnd.nextDouble() * 6,
                  height: 3 + rnd.nextDouble() * 4,
                  color: colors[i % colors.length]
                      .withValues(alpha: 0.5 + rnd.nextDouble() * 0.5),
                ),
              ),
            );
          }),
        );
      }),
    );
  }
}
