import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fonts.dart';
import 'layers.dart';

/// Renders a [TextSpec] at [fontSize]. Used on the stage, in previews and in
/// the export (it's the same widget tree).
class TextLayerView extends StatelessWidget {
  const TextLayerView({
    super.key,
    required this.spec,
    required this.fontSize,
    this.maxWidth,
  });

  final TextSpec spec;
  final double fontSize;
  final double? maxWidth;

  TextStyle get _base {
    final f = fontByFamily(spec.font);
    return TextStyle(
      fontFamily: spec.font,
      fontSize: fontSize,
      fontWeight: f.weight,
      fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: spec.letterSpacing * fontSize,
      height: 1.18,
      color: spec.color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = spec.text.isEmpty ? ' ' : spec.text;
    final style = _base;

    if (spec.bg == TextBg.tiles) return _tiles(text, style);

    final curved = spec.curve.abs() > 0.02 && !text.contains('\n');
    Widget core;
    if (curved) {
      core = CurvedText(
        text: text,
        style: style,
        curve: spec.curve,
        outline: spec.bg == TextBg.outline ? spec.bgColor : null,
        shadow: spec.bg == TextBg.shadow,
      );
      if (maxWidth != null) {
        // Long curved captions shrink to fit instead of running off-screen.
        core = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: FittedBox(fit: BoxFit.scaleDown, child: core),
        );
      }
    } else {
      core = _plain(text, style);
    }

    switch (spec.bg) {
      case TextBg.label:
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: fontSize * 0.55, vertical: fontSize * 0.22),
          decoration: BoxDecoration(
            color: spec.bgColor,
            borderRadius: BorderRadius.circular(fontSize * 0.45),
          ),
          child: core,
        );
      case TextBg.highlight:
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: fontSize * 0.3, vertical: fontSize * 0.08),
          color: spec.bgColor.withValues(alpha: 0.75),
          child: core,
        );
      default:
        return core;
    }
  }

  Widget _plain(String text, TextStyle style) {
    Widget t(TextStyle s) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
          child: Text(text, textAlign: spec.align, style: s),
        );
    switch (spec.bg) {
      case TextBg.shadow:
        return t(style.copyWith(shadows: [
          Shadow(
              blurRadius: fontSize * 0.25,
              color: Colors.black.withValues(alpha: 0.45),
              offset: Offset(0, fontSize * 0.04)),
        ]));
      case TextBg.outline:
        return Stack(
          children: [
            t(style.copyWith(
              color: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = fontSize * 0.14
                ..strokeJoin = StrokeJoin.round
                ..color = spec.bgColor,
            )),
            t(style),
          ],
        );
      default:
        return t(style);
    }
  }

  /// Each letter on its own little card ("J U L Y").
  Widget _tiles(String text, TextStyle style) {
    final chars = text.split('');
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: fontSize * 0.12,
      runSpacing: fontSize * 0.12,
      children: [
        for (final c in chars)
          if (c == ' ')
            SizedBox(width: fontSize * 0.4, height: fontSize)
          else
            Container(
              width: fontSize * 1.05,
              height: fontSize * 1.15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: spec.bgColor,
                borderRadius: BorderRadius.circular(fontSize * 0.12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: fontSize * 0.12,
                      offset: Offset(0, fontSize * 0.05)),
                ],
              ),
              child: Text(c,
                  style: style.copyWith(
                      fontSize: fontSize * 0.72, letterSpacing: 0, height: 1)),
            ),
      ],
    );
  }
}

/// Text laid out along an arc. curve > 0 arches up (rainbow), < 0 smiles.
class CurvedText extends StatelessWidget {
  const CurvedText({
    super.key,
    required this.text,
    required this.style,
    required this.curve,
    this.outline,
    this.shadow = false,
  });

  final String text;
  final TextStyle style;
  final double curve;
  final Color? outline;
  final bool shadow;

  // Laying out one TextPainter per letter is costly; reuse recent layouts
  // while layers are dragged around.
  static final Map<String, _CurvedTextPainter> _cache = {};

  @override
  Widget build(BuildContext context) {
    final c = curve.clamp(-1.0, 1.0);
    final key = '$text|${style.hashCode}|$c|${outline?.toARGB32()}|$shadow';
    var painter = _cache[key];
    if (painter == null) {
      painter = _CurvedTextPainter(
        text: text,
        style: style,
        curve: c,
        outline: outline,
        shadow: shadow,
      );
      if (_cache.length > 40) _cache.remove(_cache.keys.first);
      _cache[key] = painter;
    }
    return CustomPaint(size: painter.measure(), painter: painter);
  }
}

class _Glyph {
  _Glyph(this.painter, this.stroke);
  final TextPainter painter;
  final TextPainter? stroke;
  double get width => painter.width;
}

class _CurvedTextPainter extends CustomPainter {
  _CurvedTextPainter({
    required this.text,
    required this.style,
    required this.curve,
    this.outline,
    this.shadow = false,
  }) {
    final shadows = shadow
        ? [
            Shadow(
                blurRadius: (style.fontSize ?? 20) * 0.25,
                color: Colors.black.withValues(alpha: 0.45)),
          ]
        : null;
    for (final ch in text.characters) {
      final p = TextPainter(
        text: TextSpan(text: ch, style: style.copyWith(shadows: shadows)),
        textDirection: TextDirection.ltr,
      )..layout();
      TextPainter? sp;
      if (outline != null) {
        sp = TextPainter(
          text: TextSpan(
            text: ch,
            style: style.copyWith(
              color: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = (style.fontSize ?? 20) * 0.14
                ..color = outline!,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      }
      _glyphs.add(_Glyph(p, sp));
    }
    _total = _glyphs.fold(0.0, (a, g) => a + g.width);
    _h = _glyphs.isEmpty ? (style.fontSize ?? 20) : _glyphs.first.painter.height;
    _theta = curve.abs() * math.pi * 1.2; // up to 216 degrees
    _r = _theta < 0.001 ? 0 : _total / _theta;
  }

  final String text;
  final TextStyle style;
  final double curve;
  final Color? outline;
  final bool shadow;

  final List<_Glyph> _glyphs = [];
  double _total = 0;
  double _h = 0;
  double _theta = 0;
  double _r = 0;

  Size measure() {
    if (_r == 0) return Size(_total, _h);
    final half = _theta / 2;
    final width = (half <= math.pi / 2 ? 2 * _r * math.sin(half) : 2 * _r) + _h * 1.8;
    final height = _r * (1 - math.cos(half)) + _h * 1.6;
    return Size(width, height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_r == 0) {
      var x = 0.0;
      for (final g in _glyphs) {
        g.stroke?.paint(canvas, Offset(x, 0));
        g.painter.paint(canvas, Offset(x, 0));
        x += g.width;
      }
      return;
    }
    final arch = curve > 0;
    final half = _theta / 2;
    final cx = size.width / 2;
    // Circle center: below the text for an arch, above for a smile.
    final cy = arch ? _h * 1.1 + _r : _h * 1.1 - _r * math.cos(half);
    var run = 0.0;
    for (final g in _glyphs) {
      final mid = run + g.width / 2;
      run += g.width;
      final double a;
      final double rot;
      if (arch) {
        a = -math.pi / 2 - half + mid / _r;
        rot = a + math.pi / 2;
      } else {
        a = math.pi / 2 + half - mid / _r;
        rot = a - math.pi / 2;
      }
      final px = cx + _r * math.cos(a);
      final py = cy + _r * math.sin(a);
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(rot);
      final o = Offset(-g.width / 2, arch ? -g.painter.height * 0.85 : -g.painter.height * 0.85);
      g.stroke?.paint(canvas, o);
      g.painter.paint(canvas, o);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CurvedTextPainter old) =>
      old.text != text || old.style != style || old.curve != curve ||
      old.outline != outline || old.shadow != shadow;
}
