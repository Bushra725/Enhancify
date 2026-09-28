import 'package:flutter/material.dart';

import '../../editor/layers.dart';

/// How a photo frame looks.
enum FrameStyle { plain, bordered, rounded, polaroid, scallop, arch, circle }

/// Background of the collage board.
enum BgKind { color, paper, grid, blurPhoto, photo }

/// A photo slot, in board-relative units (0..1). Frames may hang over the
/// edges (e.g. the "swipe" carousel) — the board clips them.
class CFrame {
  const CFrame(this.x, this.y, this.w, this.h,
      {this.rot = 0, this.style = FrameStyle.plain, this.radius = 0.04});
  final double x, y, w, h;

  /// Degrees.
  final double rot;
  final FrameStyle style;

  /// Corner radius as a fraction of the frame's shorter side.
  final double radius;
}

enum DecoKind { tornBand, wavyBand, dots, line, rect }

/// Non-editable artwork that belongs to the template (torn paper, bands...).
class Deco {
  const Deco(this.kind, this.x, this.y, this.w, this.h,
      {this.color = Colors.white, this.front = true, this.stroke = 1.5});
  final DecoKind kind;
  final double x, y, w, h;
  final Color color;

  /// Painted above the photos (true) or below them.
  final bool front;
  final double stroke;
}

/// Editable text/sticker the template starts with.
class Seed {
  const Seed(this.make);
  final OverlayLayer Function() make;
}

class CollageTemplate {
  const CollageTemplate({
    required this.id,
    required this.name,
    required this.aspect,
    required this.frames,
    this.bg = BgKind.color,
    this.bgColor = Colors.white,
    this.tint,
    this.decos = const [],
    this.seeds = const [],
    this.adjustableGap = false,
    this.tip,
  });

  final String id;
  final String name;

  /// width / height of the board.
  final double aspect;
  final List<CFrame> frames;
  final BgKind bg;
  final Color bgColor;

  /// Color laid over a blurred photo background.
  final Color? tint;
  final List<Deco> decos;
  final List<Seed> seeds;
  final bool adjustableGap;
  final String? tip;

  /// A full-bleed background photo takes the first slot.
  bool get hasPhotoBackground => bg == BgKind.photo;
  int get slotCount => frames.length + (hasPhotoBackground ? 1 : 0);
}

const _ink = Color(0xFF2A0A1A);
const _cream = Color(0xFFF4EEE6);

OverlayLayer _text(TextSpec s, double x, double y, {double scale = 1, double rot = 0}) =>
    OverlayLayer.text(s, center: Offset(x, y), scale: scale, rotation: rot);

OverlayLayer _sticker(String name, double x, double y, {double scale = 1, double rot = 0}) =>
    OverlayLayer.sticker('assets/stickers/$name.png',
        center: Offset(x, y), scale: scale, rotation: rot);

final List<CollageTemplate> collageTemplates = [
  // ---------------------------------------------------- Pinterest-inspired
  CollageTemplate(
    id: 'scrapbook',
    name: 'Scrapbook',
    aspect: 0.62,
    bg: BgKind.paper,
    bgColor: const Color(0xFFF6F0E8),
    frames: const [
      CFrame(0.03, 0.03, 0.84, 0.5, style: FrameStyle.bordered),
      CFrame(0.28, 0.45, 0.69, 0.51, style: FrameStyle.bordered),
    ],
    decos: const [Deco(DecoKind.line, 0.12, 0.5, 0, 0.48, color: _ink, front: false)],
    seeds: [
      Seed(() => _sticker('flowers/dried_bouquet', 0.9, 0.47, scale: 0.85, rot: 0.25)),
      Seed(() => _sticker('paper/vintage_camera', 0.19, 0.9, scale: 0.85, rot: -0.2)),
    ],
  ),
  CollageTemplate(
    id: 'memories',
    name: 'Memories',
    aspect: 0.8,
    bg: BgKind.paper,
    bgColor: const Color(0xFFF3EEE8),
    frames: const [
      CFrame(0.05, 0.03, 0.44, 0.43),
      CFrame(0.51, 0.03, 0.44, 0.43),
      CFrame(0.05, 0.54, 0.44, 0.43),
      CFrame(0.51, 0.54, 0.44, 0.43),
    ],
    decos: const [Deco(DecoKind.wavyBand, 0, 0.415, 1, 0.17, color: Color(0xFFF3EEE8))],
    seeds: [
      Seed(() => _text(
          TextSpec(
              text: 'MAKING MEMORIES THAT LAST A LIFETIME',
              font: 'Montserrat',
              color: _ink,
              bg: TextBg.none,
              curve: 0.32,
              letterSpacing: 0.14),
          0.5,
          0.5,
          scale: 0.62)),
    ],
  ),
  CollageTemplate(
    id: 'torn',
    name: 'Torn paper',
    aspect: 0.5625,
    frames: const [
      CFrame(0, 0, 1, 0.345),
      CFrame(0, 0.33, 1, 0.345),
      CFrame(0, 0.66, 1, 0.34),
    ],
    decos: const [
      Deco(DecoKind.tornBand, 0, 0.318, 1, 0.04),
      Deco(DecoKind.tornBand, 0, 0.648, 1, 0.04),
    ],
  ),
  CollageTemplate(
    id: 'swipe',
    name: 'Swipe',
    aspect: 0.8,
    bgColor: Colors.white,
    frames: const [
      CFrame(0.29, 0.07, 0.42, 0.66, style: FrameStyle.rounded, radius: 0.03),
      CFrame(-0.1, 0.22, 0.26, 0.42, style: FrameStyle.rounded, radius: 0.03),
      CFrame(0.84, 0.22, 0.26, 0.42, style: FrameStyle.rounded, radius: 0.03),
    ],
    seeds: [
      Seed(() => _text(TextSpec(text: 'for the best of me', font: 'GreatVibes', color: _ink, bg: TextBg.none), 0.5, 0.82, scale: 0.9)),
      Seed(() => _text(TextSpec(text: 'SWIPE', font: 'Montserrat', color: const Color(0xFF6B4658), bg: TextBg.none, letterSpacing: 0.35), 0.5, 0.92, scale: 0.45)),
    ],
  ),
  CollageTemplate(
    id: 'vibes',
    name: '19 vibes',
    aspect: 0.56,
    bg: BgKind.paper,
    bgColor: const Color(0xFFF8EFE4),
    frames: const [
      CFrame(0.05, 0.03, 0.54, 0.36),
      CFrame(0.62, 0.03, 0.34, 0.19),
      CFrame(0.62, 0.24, 0.34, 0.36),
      CFrame(0.05, 0.47, 0.54, 0.4),
      CFrame(0.62, 0.62, 0.34, 0.35),
    ],
    seeds: [
      Seed(() => _text(TextSpec(text: 'FEELING 19 VIBES ✨', font: 'AmaticSC', color: _ink, bg: TextBg.none), 0.31, 0.43, scale: 0.85)),
      Seed(() => _sticker('flowers/white_blossom', 0.59, 0.05, scale: 0.4, rot: 0.3)),
      Seed(() => _sticker('love/heart_puffy', 0.52, 0.86, scale: 0.42, rot: -0.2)),
    ],
  ),
  CollageTemplate(
    id: 'polaroid_stack',
    name: 'Polaroid stack',
    aspect: 0.6,
    bg: BgKind.photo,
    frames: const [
      CFrame(0.6, 0.06, 0.32, 0.2, style: FrameStyle.polaroid, rot: 2),
      CFrame(0.42, 0.24, 0.32, 0.2, style: FrameStyle.polaroid, rot: -3),
      CFrame(0.6, 0.41, 0.32, 0.2, style: FrameStyle.polaroid, rot: 3),
      CFrame(0.42, 0.58, 0.32, 0.2, style: FrameStyle.polaroid, rot: -2),
      CFrame(0.62, 0.76, 0.3, 0.19, style: FrameStyle.polaroid, rot: 2),
    ],
    decos: const [Deco(DecoKind.rect, 0.93, 0, 0.07, 1, color: Color(0xFF9DB89A), front: false)],
  ),
  CollageTemplate(
    id: 'cutout',
    name: 'Cut-out',
    aspect: 0.56,
    bg: BgKind.photo,
    frames: const [
      CFrame(0.04, 0.02, 0.58, 0.34, style: FrameStyle.polaroid, rot: -1),
      CFrame(0.7, 0.03, 0.33, 0.2, style: FrameStyle.polaroid, rot: 2),
      CFrame(0.05, 0.4, 0.42, 0.25, style: FrameStyle.polaroid),
      CFrame(0.05, 0.68, 0.42, 0.25, style: FrameStyle.polaroid, rot: 1),
    ],
    tip: 'Tip: Stickers → From my photo → Cut out adds yourself with a white outline.',
  ),
  CollageTemplate(
    id: 'masonry',
    name: 'Dark grid',
    aspect: 0.55,
    bgColor: const Color(0xFF0F0D0E),
    frames: const [
      CFrame(0.03, 0.015, 0.455, 0.37, style: FrameStyle.rounded, radius: 0.05),
      CFrame(0.515, 0.015, 0.455, 0.21, style: FrameStyle.rounded, radius: 0.05),
      CFrame(0.515, 0.25, 0.455, 0.34, style: FrameStyle.rounded, radius: 0.05),
      CFrame(0.03, 0.41, 0.455, 0.37, style: FrameStyle.rounded, radius: 0.05),
      CFrame(0.515, 0.615, 0.455, 0.37, style: FrameStyle.rounded, radius: 0.05),
      CFrame(0.03, 0.805, 0.455, 0.18, style: FrameStyle.rounded, radius: 0.05),
    ],
    decos: const [
      Deco(DecoKind.dots, 0.42, 0.392, 0.05, 0.01),
      Deco(DecoKind.dots, 0.905, 0.232, 0.05, 0.01),
      Deco(DecoKind.dots, 0.905, 0.597, 0.05, 0.01),
      Deco(DecoKind.dots, 0.42, 0.787, 0.05, 0.01),
    ],
  ),
  CollageTemplate(
    id: 'sage',
    name: 'Sage dream',
    aspect: 0.56,
    bg: BgKind.blurPhoto,
    bgColor: const Color(0xFFDDE5C8),
    tint: const Color(0x99D8E0BE),
    frames: const [
      CFrame(0.07, 0.14, 0.36, 0.36),
      CFrame(0.45, 0.07, 0.44, 0.33),
      CFrame(0.05, 0.51, 0.38, 0.34),
      CFrame(0.45, 0.42, 0.44, 0.21),
      CFrame(0.45, 0.645, 0.44, 0.23),
    ],
    seeds: [
      Seed(() => _sticker('doodles/hearts_doodle', 0.8, 0.9, scale: 0.8, rot: 0.1)),
    ],
  ),
  CollageTemplate(
    id: 'bows',
    name: 'Pink bows',
    aspect: 0.56,
    bg: BgKind.grid,
    bgColor: const Color(0xFFF9D3DC),
    frames: const [
      CFrame(0.03, 0.03, 0.54, 0.25, style: FrameStyle.scallop),
      CFrame(0.56, 0.2, 0.41, 0.21, style: FrameStyle.scallop),
      CFrame(0.03, 0.31, 0.54, 0.27, style: FrameStyle.scallop),
      CFrame(0.56, 0.48, 0.41, 0.21, style: FrameStyle.scallop),
      CFrame(0.03, 0.62, 0.54, 0.33, style: FrameStyle.scallop),
    ],
    seeds: [
      Seed(() => _sticker('cute/bow_white', 0.62, 0.17, scale: 0.4, rot: -0.2)),
      Seed(() => _sticker('cute/bow_white', 0.55, 0.44, scale: 0.35, rot: 0.2)),
      Seed(() => _text(TextSpec(text: 'Your prettiest problem 💗', font: 'PlayfairDisplay', italic: true, color: const Color(0xFF9E3A5A), bg: TextBg.none), 0.77, 0.33, scale: 0.5)),
    ],
  ),
  CollageTemplate(
    id: 'july',
    name: 'July',
    aspect: 0.5,
    bg: BgKind.paper,
    bgColor: const Color(0xFFF6F1EC),
    frames: const [
      CFrame(0.02, 0.01, 0.5, 0.27, style: FrameStyle.polaroid, rot: -3),
      CFrame(0.49, 0.02, 0.5, 0.27, style: FrameStyle.polaroid, rot: 4),
      CFrame(0.01, 0.27, 0.52, 0.27, style: FrameStyle.polaroid, rot: 2),
      CFrame(0.48, 0.3, 0.5, 0.29, style: FrameStyle.polaroid, rot: -4),
      CFrame(0.01, 0.57, 0.52, 0.28, style: FrameStyle.polaroid, rot: -2),
      CFrame(0.47, 0.61, 0.52, 0.3, style: FrameStyle.polaroid, rot: 3),
    ],
    seeds: [
      Seed(() => _sticker('flowers/pink_flower', 0.5, 0.29, scale: 0.8, rot: 0.2)),
      Seed(() => _text(TextSpec(text: 'JULY', font: 'Montserrat', color: _ink, bg: TextBg.tiles, bgColor: _cream), 0.3, 0.56, scale: 0.55)),
    ],
  ),
  CollageTemplate(
    id: 'arches',
    name: 'Arches',
    aspect: 0.8,
    bg: BgKind.paper,
    bgColor: const Color(0xFFFFE9F1),
    frames: const [
      CFrame(0.05, 0.12, 0.28, 0.6, style: FrameStyle.arch),
      CFrame(0.36, 0.12, 0.28, 0.6, style: FrameStyle.arch),
      CFrame(0.67, 0.12, 0.28, 0.6, style: FrameStyle.arch),
    ],
    seeds: [
      Seed(() => _text(TextSpec(text: 'photo dump', font: 'Pacifico', color: const Color(0xFFEA026A), bg: TextBg.none), 0.5, 0.84, scale: 0.9)),
      Seed(() => _sticker('cute/sparkle_pink', 0.9, 0.08, scale: 0.4)),
    ],
  ),
  // ---------------------------------------------------- classic grids
  CollageTemplate(id: '2side', name: '2 side', aspect: 1, adjustableGap: true, frames: const [
    CFrame(0, 0, 0.5, 1), CFrame(0.5, 0, 0.5, 1),
  ]),
  CollageTemplate(id: '2stack', name: '2 stack', aspect: 0.8, adjustableGap: true, frames: const [
    CFrame(0, 0, 1, 0.5), CFrame(0, 0.5, 1, 0.5),
  ]),
  CollageTemplate(id: '3story', name: '3 story', aspect: 0.5625, adjustableGap: true, frames: const [
    CFrame(0, 0, 1, 1 / 3), CFrame(0, 1 / 3, 1, 1 / 3), CFrame(0, 2 / 3, 1, 1 / 3),
  ]),
  CollageTemplate(id: '3focus', name: '3 focus', aspect: 1, adjustableGap: true, frames: const [
    CFrame(0, 0, 0.62, 1), CFrame(0.62, 0, 0.38, 0.5), CFrame(0.62, 0.5, 0.38, 0.5),
  ]),
  CollageTemplate(id: '4grid', name: '4 grid', aspect: 1, adjustableGap: true, frames: const [
    CFrame(0, 0, 0.5, 0.5), CFrame(0.5, 0, 0.5, 0.5), CFrame(0, 0.5, 0.5, 0.5), CFrame(0.5, 0.5, 0.5, 0.5),
  ]),
  CollageTemplate(id: '6grid', name: '6 grid', aspect: 0.75, adjustableGap: true, frames: const [
    CFrame(0, 0, 0.5, 1 / 3), CFrame(0.5, 0, 0.5, 1 / 3),
    CFrame(0, 1 / 3, 0.5, 1 / 3), CFrame(0.5, 1 / 3, 0.5, 1 / 3),
    CFrame(0, 2 / 3, 0.5, 1 / 3), CFrame(0.5, 2 / 3, 0.5, 1 / 3),
  ]),
  CollageTemplate(id: 'hearts', name: 'Circles', aspect: 1, bgColor: const Color(0xFFFFE3EF), frames: const [
    CFrame(0.06, 0.06, 0.52, 0.52, style: FrameStyle.circle),
    CFrame(0.56, 0.12, 0.38, 0.38, style: FrameStyle.circle),
    CFrame(0.12, 0.58, 0.36, 0.36, style: FrameStyle.circle),
    CFrame(0.46, 0.46, 0.5, 0.5, style: FrameStyle.circle),
  ]),
];
