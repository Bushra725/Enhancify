import 'package:flutter/material.dart';

/// A bundled font the user can pick for text (see pubspec `fonts:`).
class FontOption {
  const FontOption(this.family, this.label, {this.weight = FontWeight.w400});
  final String family;
  final String label;
  final FontWeight weight;
}

const List<FontOption> editorFonts = [
  FontOption('Poppins', 'Classic', weight: FontWeight.w700),
  FontOption('Pacifico', 'Retro'),
  FontOption('DancingScript', 'Script', weight: FontWeight.w700),
  FontOption('GreatVibes', 'Elegant'),
  FontOption('Sacramento', 'Signature'),
  FontOption('Parisienne', 'Paris'),
  FontOption('Caveat', 'Handwritten', weight: FontWeight.w700),
  FontOption('ShadowsIntoLight', 'Diary'),
  FontOption('IndieFlower', 'Doodle'),
  FontOption('GloriaHallelujah', 'Notebook'),
  FontOption('PermanentMarker', 'Marker'),
  FontOption('AmaticSC', 'Sketchy'),
  FontOption('Lobster', 'Bold Script'),
  FontOption('PlayfairDisplay', 'Serif', weight: FontWeight.w700),
  FontOption('Cinzel', 'Luxury', weight: FontWeight.w600),
  FontOption('AbrilFatface', 'Magazine'),
  FontOption('BebasNeue', 'Headline'),
  FontOption('Montserrat', 'Modern', weight: FontWeight.w800),
  FontOption('Fredoka', 'Bubbly', weight: FontWeight.w600),
  FontOption('Righteous', 'Groovy'),
  FontOption('Monoton', 'Neon'),
  FontOption('PressStart2P', 'Pixel'),
];

FontOption fontByFamily(String family) =>
    editorFonts.firstWhere((f) => f.family == family,
        orElse: () => editorFonts.first);

/// Colors offered for text, drawing and backgrounds.
const List<Color> editorSwatches = [
  Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFEA026A), Color(0xFFFF5C9E),
  Color(0xFFFFB3CC), Color(0xFFFFE3EF), Color(0xFFE0354F), Color(0xFFFF7A45),
  Color(0xFFFFB547), Color(0xFFFFE38C), Color(0xFFA8E6B8), Color(0xFF2EC4A6),
  Color(0xFF9DB89A), Color(0xFF8EC5F0), Color(0xFF3A7BD5), Color(0xFFB892FF),
  Color(0xFF7B4AE2), Color(0xFF8A5A3C), Color(0xFFF7E3C8), Color(0xFF6B4658),
  Color(0xFF9E9E9E), Color(0xFF2A0A1A),
];
