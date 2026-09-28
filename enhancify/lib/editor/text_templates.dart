import 'package:flutter/material.dart';

import 'layers.dart';

/// Ready-made text looks, based on the captions people use most on
/// Instagram / Pinterest photo dumps and collages.
class TextTemplate {
  const TextTemplate(this.build);
  final TextSpec Function() build;
}

const _pink = Color(0xFFEA026A);
const _ink = Color(0xFF2A0A1A);
const _cream = Color(0xFFFFF6EA);

final List<TextTemplate> textTemplates = [
  TextTemplate(() => TextSpec(text: 'Feeling 19 vibes ✨', font: 'AmaticSC', color: _ink, bg: TextBg.none)),
  TextTemplate(() => TextSpec(text: 'MAKING MEMORIES THAT LAST A LIFETIME', font: 'Montserrat', color: _ink, bg: TextBg.none, curve: 0.55, letterSpacing: 0.12)),
  TextTemplate(() => TextSpec(text: 'for the best of me', font: 'GreatVibes', color: _ink, bg: TextBg.none)),
  TextTemplate(() => TextSpec(text: 'S W I P E', font: 'Montserrat', color: const Color(0xFF6B4658), bg: TextBg.none, letterSpacing: 0.3)),
  TextTemplate(() => TextSpec(text: 'Your prettiest problem 💗', font: 'PlayfairDisplay', color: const Color(0xFF9E3A5A), bg: TextBg.none, italic: true)),
  TextTemplate(() => TextSpec(text: 'JULY', font: 'Montserrat', color: _ink, bg: TextBg.tiles, bgColor: _cream)),
  TextTemplate(() => TextSpec(text: 'photo dump', font: 'Poppins', color: Colors.white, bg: TextBg.label, bgColor: _ink)),
  TextTemplate(() => TextSpec(text: 'core memory', font: 'Poppins', color: _ink, bg: TextBg.label, bgColor: const Color(0xFFFFC2DA))),
  TextTemplate(() => TextSpec(text: 'good vibes only', font: 'Pacifico', color: Colors.white, bg: TextBg.shadow)),
  TextTemplate(() => TextSpec(text: 'golden hour', font: 'Sacramento', color: const Color(0xFFFFB547), bg: TextBg.shadow)),
  TextTemplate(() => TextSpec(text: 'Happy Birthday!', font: 'Lobster', color: _pink, bg: TextBg.outline, bgColor: Colors.white)),
  TextTemplate(() => TextSpec(text: 'besties forever', font: 'DancingScript', color: _pink, bg: TextBg.outline, bgColor: Colors.white, curve: -0.35)),
  TextTemplate(() => TextSpec(text: 'SUMMER 2026', font: 'BebasNeue', color: Colors.white, bg: TextBg.shadow, letterSpacing: 0.12)),
  TextTemplate(() => TextSpec(text: 'self love club', font: 'Caveat', color: _ink, bg: TextBg.highlight, bgColor: const Color(0xFFFFE38C))),
  TextTemplate(() => TextSpec(text: 'weekend mood', font: 'PermanentMarker', color: _pink, bg: TextBg.none)),
  TextTemplate(() => TextSpec(text: 'stay wild', font: 'Cinzel', color: Colors.white, bg: TextBg.shadow, letterSpacing: 0.2)),
  TextTemplate(() => TextSpec(text: 'hello, sunshine', font: 'Parisienne', color: const Color(0xFFFF7A45), bg: TextBg.none)),
  TextTemplate(() => TextSpec(text: 'XOXO', font: 'Monoton', color: _pink, bg: TextBg.none)),
  TextTemplate(() => TextSpec(text: 'dear diary...', font: 'ShadowsIntoLight', color: _ink, bg: TextBg.label, bgColor: _cream)),
  TextTemplate(() => TextSpec(text: 'LOVE YOU', font: 'Fredoka', color: Colors.white, bg: TextBg.label, bgColor: _pink)),
  TextTemplate(() => TextSpec(text: 'the best day ever', font: 'IndieFlower', color: _ink, bg: TextBg.none, curve: 0.3)),
  TextTemplate(() => TextSpec(text: 'Mood', font: 'AbrilFatface', color: _ink, bg: TextBg.none)),
  TextTemplate(() => TextSpec(text: 'GAME ON', font: 'PressStart2P', color: const Color(0xFF2EC4A6), bg: TextBg.outline, bgColor: _ink)),
  TextTemplate(() => TextSpec(text: 'thank u, next', font: 'GloriaHallelujah', color: const Color(0xFF7B4AE2), bg: TextBg.none)),
];
