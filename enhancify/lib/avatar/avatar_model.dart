import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything that defines the user's cartoon avatar (Snapchat/Bitmoji style).
class AvatarConfig {
  AvatarConfig({
    this.gender = 'girl',
    this.face = 'oval',
    this.skin = const Color(0xFFF2C9A9),
    this.hairStyle = 'long',
    this.hairColor = const Color(0xFF2B1B14),
    this.eyes = 'lashes',
    this.eyeColor = const Color(0xFF5B3A29),
    this.brows = 'soft',
    this.nose = 'small',
    this.facial = 'none',
    this.glasses = 'none',
    this.earrings = 'hoops',
    this.hat = 'none',
    this.outfitStyle = 'tee',
    this.outfitColor = const Color(0xFFEA026A),
    this.lipstick = true,
    this.lipColor = const Color(0xFFD9637A),
    this.accentColor = const Color(0xFFFFB547),
  });

  /// 'girl' or 'boy': picks the defaults, the shuffle and the option order.
  String gender;
  String face;
  Color skin;
  String hairStyle;
  Color hairColor;
  String eyes;
  Color eyeColor;
  String brows;
  String nose;
  String facial;
  String glasses;
  String earrings;
  String hat;
  String outfitStyle;
  Color outfitColor;
  bool lipstick;
  Color lipColor;
  Color accentColor;

  AvatarConfig copy() => AvatarConfig.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'face': face,
        'skin': skin.toARGB32(),
        'hairStyle': hairStyle,
        'hairColor': hairColor.toARGB32(),
        'eyes': eyes,
        'eyeColor': eyeColor.toARGB32(),
        'brows': brows,
        'nose': nose,
        'facial': facial,
        'glasses': glasses,
        'earrings': earrings,
        'hat': hat,
        'outfitStyle': outfitStyle,
        'outfitColor': outfitColor.toARGB32(),
        'lipstick': lipstick,
        'lipColor': lipColor.toARGB32(),
        'accentColor': accentColor.toARGB32(),
      };

  factory AvatarConfig.fromJson(Map<String, dynamic> j) {
    final d = AvatarConfig();
    Color c(String k, Color fallback) =>
        j[k] is int ? Color(j[k] as int) : fallback;
    String s(String k, String fallback, List<String> allowed) {
      final v = j[k];
      return v is String && allowed.contains(v) ? v : fallback;
    }

    return AvatarConfig(
      gender: s('gender', d.gender, const ['girl', 'boy']),
      face: s('face', d.face, AvatarOptions.faces),
      skin: c('skin', d.skin),
      hairStyle: s('hairStyle', d.hairStyle, AvatarOptions.hairStyles),
      hairColor: c('hairColor', d.hairColor),
      eyes: s('eyes', d.eyes, AvatarOptions.eyes),
      eyeColor: c('eyeColor', d.eyeColor),
      brows: s('brows', d.brows, AvatarOptions.brows),
      nose: s('nose', d.nose, AvatarOptions.noses),
      facial: s('facial', d.facial, AvatarOptions.facial),
      glasses: s('glasses', d.glasses, AvatarOptions.glasses),
      earrings: s('earrings', d.earrings, AvatarOptions.earrings),
      hat: s('hat', d.hat, AvatarOptions.hats),
      outfitStyle: s('outfitStyle', d.outfitStyle, AvatarOptions.outfits),
      outfitColor: c('outfitColor', d.outfitColor),
      lipstick: j['lipstick'] is bool ? j['lipstick'] as bool : d.lipstick,
      lipColor: c('lipColor', d.lipColor),
      accentColor: c('accentColor', d.accentColor),
    );
  }

  /// Default boy avatar.
  factory AvatarConfig.boy() => AvatarConfig(
        gender: 'boy',
        face: 'jaw',
        hairStyle: 'quiff',
        hairColor: const Color(0xFF2B1B14),
        eyes: 'round',
        brows: 'straight',
        nose: 'small',
        facial: 'none',
        earrings: 'none',
        outfitStyle: 'hoodie',
        outfitColor: const Color(0xFF3A7BD5),
        lipstick: false,
      );

  /// Default girl avatar.
  factory AvatarConfig.girl() => AvatarConfig();

  /// A random but good-looking avatar ("Shuffle"). Keeps [gender] if given.
  factory AvatarConfig.random({String? gender}) {
    final r = math.Random();
    T pick<T>(List<T> l) => l[r.nextInt(l.length)];
    final feminine = gender == null ? r.nextBool() : gender == 'girl';
    return AvatarConfig(
      gender: feminine ? 'girl' : 'boy',
      face: pick(feminine ? const ['oval', 'round', 'heart', 'square'] : const ['jaw', 'square', 'oval', 'round']),
      skin: pick(AvatarOptions.skinTones),
      hairStyle: pick(feminine
          ? const ['long', 'wavy', 'bob', 'bun', 'ponytail', 'braids', 'hijab', 'curly']
          : AvatarOptions.boyHair.where((h) => h != 'bald' || r.nextInt(4) == 0).toList()),
      hairColor: pick(AvatarOptions.hairColors),
      eyes: feminine ? pick(const ['lashes', 'almond']) : pick(const ['round', 'almond']),
      eyeColor: pick(AvatarOptions.eyeColors),
      brows: feminine ? pick(const ['soft', 'arched', 'thick']) : pick(const ['straight', 'thick', 'soft']),
      nose: pick(AvatarOptions.noses),
      facial: feminine ? 'none' : pick(AvatarOptions.facial),
      glasses: r.nextInt(3) == 0 ? pick(AvatarOptions.glasses) : 'none',
      earrings: feminine ? pick(AvatarOptions.earrings) : 'none',
      hat: r.nextInt(4) == 0 ? pick(AvatarOptions.hats) : 'none',
      outfitStyle: pick(feminine ? AvatarOptions.girlOutfits : AvatarOptions.boyOutfits),
      outfitColor: pick(AvatarOptions.outfitColors),
      lipstick: feminine && r.nextBool(),
      lipColor: pick(AvatarOptions.lipColors),
      accentColor: pick(AvatarOptions.accentColors),
    );
  }
}

/// Choices shown in the avatar builder. Keys match lib/avatar/avatar_parts.dart.
class AvatarOptions {
  AvatarOptions._();

  static const faces = ['oval', 'round', 'square', 'heart', 'jaw'];
  static const hairStyles = [
    'long', 'wavy', 'bob', 'bun', 'ponytail', 'braids', 'curly', 'afro',
    'short', 'sidepart', 'buzz', 'bald', 'hijab',
    'quiff', 'spiky', 'fade', 'slick', 'fringe', 'manbun',
  ];
  static const boyHair = [
    'short', 'quiff', 'fade', 'spiky', 'sidepart', 'slick', 'fringe', 'buzz',
    'curly', 'afro', 'manbun', 'long', 'bald',
  ];
  static const girlHair = [
    'long', 'wavy', 'bob', 'bun', 'ponytail', 'braids', 'curly', 'afro',
    'hijab', 'fringe', 'short', 'sidepart', 'buzz',
  ];
  static const eyes = ['round', 'almond', 'lashes'];
  static const brows = ['soft', 'thick', 'arched', 'straight'];
  static const noses = ['small', 'button', 'line'];
  static const facial = ['none', 'stubble', 'mustache', 'chevron', 'goatee', 'beard', 'full'];
  static const glasses = ['none', 'round', 'square', 'cateye'];
  static const earrings = ['none', 'studs', 'hoops'];
  static const hats = ['none', 'bow', 'flowers', 'beanie', 'cap'];
  static const outfits = ['tee', 'hoodie', 'shirt', 'turtleneck', 'dress', 'jacket', 'polo', 'suit', 'kurta'];
  static const boyOutfits = ['tee', 'hoodie', 'jacket', 'polo', 'shirt', 'suit', 'kurta', 'turtleneck'];
  static const girlOutfits = ['tee', 'dress', 'hoodie', 'shirt', 'turtleneck', 'jacket', 'kurta', 'polo'];

  /// Options in the order that suits the chosen gender (all stay available).
  static List<String> hairFor(String gender) => gender == 'boy' ? boyHair : girlHair;
  static List<String> outfitsFor(String gender) => gender == 'boy' ? boyOutfits : girlOutfits;
  static List<String> facesFor(String gender) =>
      gender == 'boy' ? const ['jaw', 'square', 'oval', 'round', 'heart'] : faces;

  static const skinTones = [
    Color(0xFFFBE3D3), Color(0xFFF7D7C4), Color(0xFFF2C9A9), Color(0xFFE8B48E),
    Color(0xFFD9A07A), Color(0xFFC68863), Color(0xFFA86F4C), Color(0xFF8D5A3B),
    Color(0xFF6E452D), Color(0xFF5C3A28), Color(0xFF45291B),
  ];
  static const hairColors = [
    Color(0xFF111111), Color(0xFF2B1B14), Color(0xFF4A2E1F), Color(0xFF7A4B2A),
    Color(0xFFA86B3C), Color(0xFFC98A3E), Color(0xFFE8C07A), Color(0xFFB23A2A),
    Color(0xFFE06A8C), Color(0xFF9E78D8), Color(0xFF3A7BD5), Color(0xFF9E9E9E),
    Color(0xFFF2F2F2),
  ];
  static const eyeColors = [
    Color(0xFF2B1B14), Color(0xFF5B3A29), Color(0xFF8A5A3C), Color(0xFF3A7BD5),
    Color(0xFF2EC4A6), Color(0xFF6E9F6A), Color(0xFF9E9E9E), Color(0xFF7B4AE2),
  ];
  static const outfitColors = [
    Color(0xFFEA026A), Color(0xFFFF8DBB), Color(0xFFFFFFFF), Color(0xFF222222),
    Color(0xFF3A7BD5), Color(0xFF8EC5F0), Color(0xFF2EC4A6), Color(0xFF9DB89A),
    Color(0xFFFFB547), Color(0xFFFFE38C), Color(0xFFB892FF), Color(0xFFE0354F),
    Color(0xFF8A5A3C), Color(0xFFF7E3C8),
  ];
  static const lipColors = [
    Color(0xFFD9637A), Color(0xFFEA026A), Color(0xFFE0354F), Color(0xFFB0485C),
    Color(0xFFC98A7A), Color(0xFF9E3A5A),
  ];
  static const accentColors = [
    Color(0xFFFFB547), Color(0xFFEA026A), Color(0xFFFFFFFF), Color(0xFFD9D9D9),
    Color(0xFF8EC5F0), Color(0xFFB892FF), Color(0xFF222222),
  ];

  static String label(String key) => switch (key) {
        'none' => 'None',
        'sidepart' => 'Side part',
        'cateye' => 'Cat-eye',
        'hijab' => 'Hijab',
        'turtleneck' => 'Turtleneck',
        'jaw' => 'Angular',
        'manbun' => 'Man bun',
        'full' => 'Full beard',
        'chevron' => 'Chevron',
        _ => key[0].toUpperCase() + key.substring(1),
      };
}

/// Sticker poses, in the order shown to the user.
const List<String> avatarPoseOrder = [
  'happy', 'hi', 'love', 'laugh', 'lol', 'wink', 'cool', 'kiss', 'yay',
  'wow', 'sleepy', 'sad', 'angry', 'bye',
];

/// Saves the avatar on the device.
class AvatarStore {
  AvatarStore._();
  static const _key = 'avatar_config_v1';

  static Future<AvatarConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AvatarConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AvatarConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(c.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
