import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import 'avatar_model.dart';
import 'avatar_parts.dart';

/// Paints the avatar from the vector parts in avatar_parts.dart.
class AvatarPainter extends CustomPainter {
  AvatarPainter(this.config, {this.pose = 'happy'}) : _sig = _signature(config);

  final AvatarConfig config;
  final String pose;

  /// Snapshot of the config when this painter was made. The builder edits
  /// the config in place, so compare snapshots, not objects.
  final String _sig;

  /// height / width of the artwork (200 x 240).
  static const double aspect = 240 / 200;

  static final Map<String, Path> _pathCache = {};

  static Path _path(String d) =>
      _pathCache.putIfAbsent(d, () => parseSvgPathData(d));

  static Color _shade(Color c, double f) => Color.fromARGB(
        255,
        ((c.r * 255) * f).round().clamp(0, 255),
        ((c.g * 255) * f).round().clamp(0, 255),
        ((c.b * 255) * f).round().clamp(0, 255),
      );

  Color? _color(String? role) {
    if (role == null || role == 'none') return null;
    switch (role) {
      case 'skin':
        return config.skin;
      case 'skinShade':
        return _shade(config.skin, 0.86);
      case 'hair':
        return config.hairColor;
      case 'hairShade':
        return _shade(config.hairColor, 0.72);
      case 'eye':
        return config.eyeColor;
      case 'lip':
        return config.lipColor;
      case 'outfit':
        return config.outfitColor;
      case 'outfitShade':
        return _shade(config.outfitColor, 0.8);
      case 'blush':
        return const Color(0xFFFF7A9A);
      case 'ink':
        return const Color(0xFF2A0A1A);
      case 'white':
        return Colors.white;
      case 'glasses':
        return const Color(0xFF2A0A1A);
      case 'accent':
        return config.accentColor;
    }
    if (role.startsWith('#') && role.length == 7) {
      final v = int.tryParse(role.substring(1), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return null;
  }

  void _draw(Canvas canvas, List<AP> parts) {
    for (final p in parts) {
      final path = _path(p.d);
      final fill = _color(p.fill);
      if (fill != null) {
        canvas.drawPath(
          path,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.fill
            ..color = fill.withValues(alpha: p.op),
        );
      }
      final stroke = _color(p.stroke);
      if (stroke != null && p.sw > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = p.sw
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = stroke.withValues(alpha: p.op),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pz = avatarPoses[pose] ?? avatarPoses['happy']!;
    canvas.save();
    canvas.scale(size.width / 200, size.height / 240);

    _draw(canvas, avatarHairBack[config.hairStyle] ?? const []);
    _draw(canvas, avatarNeck);
    _draw(canvas, avatarBodies[config.outfitStyle] ?? avatarBodies['tee']!);
    _draw(canvas, avatarEars);
    _draw(canvas, avatarHeads[config.face] ?? avatarHeads['oval']!);
    _draw(canvas, avatarBlush);
    _draw(
        canvas,
        (pz.brows != null ? avatarPoseBrows[pz.brows!] : null) ??
            avatarBrows[config.brows] ??
            const []);
    _draw(
        canvas,
        (pz.eyes != null ? avatarPoseEyes[pz.eyes!] : null) ??
            avatarEyes[config.eyes] ??
            const []);
    _draw(canvas, avatarNoses[config.nose] ?? const []);
    final mouth =
        pz.mouth == 'smile' && config.lipstick ? 'lips' : pz.mouth;
    _draw(canvas, avatarMouths[mouth] ?? avatarMouths['smile']!);
    _draw(canvas, avatarFacialHair[config.facial] ?? const []);
    _draw(canvas, avatarHairFrame[config.hairStyle] ?? const []);
    _draw(canvas, avatarHairFront[config.hairStyle] ?? const []);
    _draw(canvas, avatarEarrings[config.earrings] ?? const []);
    _draw(canvas, avatarHeadwear[config.hat] ?? const []);
    if (pz.eyes != 'sun') _draw(canvas, avatarGlasses[config.glasses] ?? const []);
    _draw(canvas, pz.extra);

    for (final t in pz.texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            fontFamily: t.font,
            fontSize: t.size,
            fontWeight: FontWeight.w700,
            color: _color(t.fill) ?? Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline =
          tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(t.x - tp.width / 2, t.y - baseline));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AvatarPainter old) =>
      old.pose != pose || old._sig != _sig;

  static String _signature(AvatarConfig c) => c.toJson().toString();
}

/// Convenience widget.
class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.config, this.pose = 'happy', this.width = 120});
  final AvatarConfig config;
  final String pose;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * AvatarPainter.aspect,
        child: CustomPaint(painter: AvatarPainter(config, pose: pose)),
      );
}
