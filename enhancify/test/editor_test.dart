import 'package:enhancify/avatar/avatar_model.dart';
import 'package:enhancify/avatar/avatar_painter.dart';
import 'package:enhancify/avatar/avatar_parts.dart';
import 'package:enhancify/data/emoji_data.dart';
import 'package:enhancify/data/sticker_data.dart';
import 'package:enhancify/editor/layers.dart';
import 'package:enhancify/editor/text_templates.dart';
import 'package:enhancify/editor/text_view.dart';
import 'package:enhancify/screens/collage/collage_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full emoji keyboard is bundled', () {
    final total = emojiCategories.fold<int>(0, (a, c) => a + c.items.length);
    expect(emojiCategories.length, 9);
    expect(total, greaterThan(1800));
  });

  test('more than 50 aesthetic stickers', () {
    final total = stickerCategories.fold<int>(0, (a, c) => a + c.assets.length);
    expect(total, greaterThan(50));
  });

  test('avatar config survives a save/load round trip', () {
    final a = AvatarConfig.random();
    final b = AvatarConfig.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });

  test('every avatar option and pose has artwork', () {
    for (final k in AvatarOptions.faces) {
      expect(avatarHeads.containsKey(k), isTrue, reason: k);
    }
    for (final k in AvatarOptions.hairStyles) {
      expect(avatarHairFront.containsKey(k), isTrue, reason: k);
    }
    for (final k in AvatarOptions.outfits) {
      expect(avatarBodies.containsKey(k), isTrue, reason: k);
    }
    for (final p in avatarPoseOrder) {
      expect(avatarPoses.containsKey(p), isTrue, reason: p);
    }
  });

  test('collage templates have sane frames', () {
    for (final t in collageTemplates) {
      expect(t.frames, isNotEmpty, reason: t.id);
      expect(t.aspect, greaterThan(0), reason: t.id);
      for (final f in t.frames) {
        expect(f.w, greaterThan(0), reason: t.id);
        expect(f.h, greaterThan(0), reason: t.id);
      }
    }
  });

  testWidgets('text styles, curved text and avatar render', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            for (final t in textTemplates)
              TextLayerView(spec: t.build(), fontSize: 20, maxWidth: 300),
            TextLayerView(
              spec: TextSpec(text: 'curved ❤️ text', curve: 0.8, bg: TextBg.outline),
              fontSize: 20,
            ),
            TextLayerView(
              spec: TextSpec(text: 'smile', curve: -1),
              fontSize: 20,
            ),
            AvatarView(config: AvatarConfig(), pose: 'love'),
            AvatarView(config: AvatarConfig.random(), pose: 'wow'),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
