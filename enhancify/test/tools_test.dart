import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:enhancify/avatar/avatar_model.dart';
import 'package:enhancify/l10n/l10n.dart';
import 'package:enhancify/l10n/l10n_more.dart';
import 'package:enhancify/services/beauty_service.dart';
import 'package:enhancify/services/gif_maker.dart';
import 'package:enhancify/services/inpaint_engine.dart';
import 'package:enhancify/services/local_enhance.dart';
import 'package:enhancify/services/object_remover.dart';
import 'package:enhancify/services/passport_maker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _photo({int w = 120, int h = 90}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(200, 120, 160));
  img.fillRect(im, x1: 40, y1: 30, x2: 70, y2: 60, color: img.ColorRgb8(10, 10, 10));
  return img.encodeJpg(im, quality: 95);
}

void main() {
  test('removal mask: brush + lasso are white, erase cuts back', () {
    final png = buildRemovalMask(100, 100, [
      MaskOp(MaskOpKind.lasso, 0, const [Offset(0.1, 0.1), Offset(0.4, 0.1), Offset(0.4, 0.4), Offset(0.1, 0.4)]),
      MaskOp(MaskOpKind.brush, 0.05, const [Offset(0.7, 0.7), Offset(0.8, 0.8)]),
      MaskOp(MaskOpKind.erase, 0.05, const [Offset(0.25, 0.25)]),
    ]);
    final m = img.decodePng(png)!;
    expect(m.getPixel(15, 15).r, 255); // lasso
    expect(m.getPixel(75, 75).r, 255); // brush
    expect(m.getPixel(25, 25).r, 0); // erased
    expect(m.getPixel(95, 5).r, 0); // untouched
  });

  test('Dart fill removes a dark object on a plain background', () async {
    final out = await removeMarked(_photo(), [
      MaskOp(MaskOpKind.lasso, 0, const [Offset(0.3, 0.28), Offset(0.62, 0.28), Offset(0.62, 0.7), Offset(0.3, 0.7)]),
    ]);
    final im = img.decodeImage(out)!;
    final p = im.getPixel(55, 45);
    expect(p.r, greaterThan(150)); // filled with the pink background
  });

  test('every GIF style encodes an animated GIF', () async {
    for (final s in GifStyle.values) {
      final gif = await GifMaker.make([_photo(), _photo(w: 90, h: 120)], style: s, size: 120);
      final decoded = img.decodeGif(gif)!;
      expect(decoded.numFrames, greaterThan(1), reason: s.name);
    }
  });

  test('passport sizes are right at 300 dpi', () {
    final std = PassportSpec.all.firstWhere((s) => s.id == 'std');
    expect((std.pxW, std.pxH), (413, 531));
    final us = PassportSpec.all.firstWhere((s) => s.id == 'us');
    expect((us.pxW, us.pxH), (600, 600));
  });

  test('pink watermark draws on small and large photos', () {
    for (final w in [200, 3000]) {
      final im = img.Image(width: w, height: w);
      LocalEnhance.drawWatermark(im);
      var pink = 0;
      for (var y = 0; y < im.height; y += 1) {
        for (var x = im.width ~/ 2; x < im.width; x += 1) {
          final p = im.getPixel(x, y);
          if (p.r - p.g > 60) pink++;
        }
      }
      expect(pink, greaterThan(20), reason: 'width $w');
    }
  });

  test('texture and smooth fill both repair a stripe pattern', () {
    // Vertical stripes with a hole in the middle.
    final im = img.Image(width: 160, height: 120);
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 160; x++) {
        final on = (x ~/ 8).isEven;
        im.setPixelRgb(x, y, on ? 220 : 40, on ? 60 : 40, on ? 120 : 40);
      }
    }
    final mask = img.Image(width: 160, height: 120, numChannels: 1);
    img.fillRect(mask, x1: 60, y1: 40, x2: 100, y2: 80, color: img.ColorRgb8(255, 255, 255));
    for (final mode in FillMode.values) {
      final out = fillMasked(im, mask, mode);
      // Hole is filled with image colors (not black / not magenta).
      final p = out.getPixel(80, 60);
      expect(p.r + p.g + p.b, greaterThan(90), reason: mode.name);
      // Outside the mark nothing changes.
      expect(out.getPixel(10, 10).r, im.getPixel(10, 10).r, reason: mode.name);
    }
  });

  test('every extra language has every key', () {
    final keys = moreLanguageTables.values.first.keys.toSet();
    for (final e in moreLanguageTables.entries) {
      expect(e.value.keys.toSet(), keys, reason: e.key);
      expect(moreLanguageNames.containsKey(e.key), isTrue);
    }
    expect(Tr.codes.length, greaterThan(25));
    expect(Tr('de')('settings'), 'Einstellungen');
    expect(Tr.isRtl('fa'), isTrue);
  });

  test('boy and girl avatars round-trip with gender', () {
    for (final c in [AvatarConfig.boy(), AvatarConfig.girl(), AvatarConfig.random(gender: 'boy')]) {
      final back = AvatarConfig.fromJson(c.toJson());
      expect(back.gender, c.gender);
      expect(AvatarOptions.hairStyles.contains(back.hairStyle), isTrue);
    }
    expect(AvatarConfig.random(gender: 'boy').lipstick, isFalse);
  });

  test('beauty presets are in range', () {
    for (final p in BeautySettings.presets.values) {
      for (final v in [p.smooth, p.brighten, p.even, p.eyes, p.teeth, p.bigEyes, p.slim, p.nose, p.lips]) {
        expect(v, inInclusiveRange(0, 1));
      }
    }
  });
}
