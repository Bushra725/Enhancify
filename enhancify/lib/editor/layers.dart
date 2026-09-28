import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../avatar/avatar_model.dart';

enum LayerKind { text, emoji, sticker, photo, avatar }

/// How text is decorated.
enum TextBg { none, shadow, outline, label, highlight, tiles }

/// Text content + style of a text layer.
class TextSpec {
  TextSpec({
    required this.text,
    this.font = 'Poppins',
    this.color = Colors.white,
    this.bgColor = const Color(0xFFEA026A),
    this.bg = TextBg.shadow,
    this.align = TextAlign.center,
    this.curve = 0,
    this.letterSpacing = 0,
    this.italic = false,
  });

  String text;
  String font;
  Color color;
  Color bgColor;
  TextBg bg;
  TextAlign align;

  /// -1 (smile) ... 0 (straight) ... 1 (arch). Only for single-line text.
  double curve;
  double letterSpacing;
  bool italic;

  TextSpec copy() => TextSpec(
        text: text,
        font: font,
        color: color,
        bgColor: bgColor,
        bg: bg,
        align: align,
        curve: curve,
        letterSpacing: letterSpacing,
        italic: italic,
      );
}

/// Shapes for stickers made from the user's own photo.
enum PhotoShape { cutout, original, circle, heart, rounded, star }

int _nextId = 0;
String newLayerId() => 'L${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';

/// One movable item placed on a photo or collage.
/// Position is stored relative to the stage (0..1) so it survives resizing
/// and full-resolution export.
class OverlayLayer {
  OverlayLayer._({
    required this.kind,
    this.center = const Offset(0.5, 0.5),
    this.scale = 1,
    this.rotation = 0,
    this.text,
    this.emoji,
    this.asset,
    this.image,
    this.avatar,
    this.pose,
  }) : id = newLayerId();

  factory OverlayLayer.text(TextSpec spec, {Offset center = const Offset(0.5, 0.5), double scale = 1, double rotation = 0}) =>
      OverlayLayer._(kind: LayerKind.text, text: spec, center: center, scale: scale, rotation: rotation);

  factory OverlayLayer.emoji(String emoji, {Offset center = const Offset(0.5, 0.45)}) =>
      OverlayLayer._(kind: LayerKind.emoji, emoji: emoji, center: center);

  factory OverlayLayer.sticker(String asset, {Offset center = const Offset(0.5, 0.45), double scale = 1, double rotation = 0}) =>
      OverlayLayer._(kind: LayerKind.sticker, asset: asset, center: center, scale: scale, rotation: rotation);

  factory OverlayLayer.photo(Uint8List png, {Offset center = const Offset(0.5, 0.5)}) =>
      OverlayLayer._(kind: LayerKind.photo, image: png, center: center, scale: 1.3);

  factory OverlayLayer.avatar(AvatarConfig config, String pose, {Offset center = const Offset(0.5, 0.5)}) =>
      OverlayLayer._(kind: LayerKind.avatar, avatar: config, pose: pose, center: center, scale: 1.2);

  final String id;
  final LayerKind kind;
  Offset center;
  double scale;
  double rotation;

  TextSpec? text;
  String? emoji;
  String? asset;
  Uint8List? image;
  AvatarConfig? avatar;
  String? pose;

  /// Base size as a fraction of the stage width (before [scale]).
  double get baseFraction => switch (kind) {
        LayerKind.text => 0.075, // font size
        LayerKind.emoji => 0.16, // font size
        LayerKind.sticker => 0.30,
        LayerKind.photo => 0.30,
        LayerKind.avatar => 0.30,
      };

  void clampScale() => scale = scale.clamp(0.15, 10.0);

  /// Keeps rotation in -pi..pi and snaps near-straight angles.
  void normalizeRotation() {
    var r = rotation % (2 * math.pi);
    if (r > math.pi) r -= 2 * math.pi;
    if (r.abs() < 0.04) r = 0;
    rotation = r;
  }
}
