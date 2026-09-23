import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Draggable before/after comparison. Both images are laid out with
/// BoxFit.contain in the same box so they line up exactly.
class BeforeAfter extends StatefulWidget {
  const BeforeAfter({super.key, required this.before, required this.after});

  final File before;
  final File after;

  @override
  State<BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<BeforeAfter> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void update(Offset local) =>
          setState(() => _split = (local.dx / w).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => update(d.localPosition),
        onTapDown: (d) => update(d.localPosition),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(widget.after, fit: BoxFit.contain, gaplessPlayback: true),
            ClipRect(
              clipper: _LeftClipper(_split),
              child: Image.file(widget.before,
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
            Positioned(
              left: (w * _split) - 1.5,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: Colors.white),
            ),
            Positioned(
              left: (w * _split) - 20,
              top: c.maxHeight / 2 - 20,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)],
                ),
                child: const Icon(Icons.compare_arrows,
                    color: AppColors.maroon, size: 22),
              ),
            ),
            const Positioned(left: 12, top: 12, child: _Tag('Before')),
            const Positioned(right: 12, top: 12, child: _Tag('After')),
          ],
        ),
      );
    });
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.split);
  final double split;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.split != split;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
