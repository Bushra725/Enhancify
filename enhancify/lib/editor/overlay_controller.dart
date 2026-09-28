import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../avatar/avatar_model.dart';
import '../widgets/common.dart';
import 'draw.dart';
import 'emoji_picker.dart';
import 'layers.dart';
import 'photo_sticker.dart';
import 'sticker_picker.dart';
import 'text_sheet.dart';

/// Holds the overlay layers + drawing of one photo/collage and the actions
/// that add to them. Shared by the photo editor and the collage maker.
class OverlayController extends ChangeNotifier {
  final List<OverlayLayer> layers = [];
  final List<DrawStroke> strokes = [];
  final DrawSettings draw = DrawSettings();
  String? selectedId;
  bool drawing = false;

  /// True while exporting only the overlay (base photo hidden).
  bool hideBase = false;
  final _rand = math.Random();

  bool get hasContent => layers.isNotEmpty || strokes.isNotEmpty;

  void changed() => notifyListeners();

  void select(String? id) {
    if (selectedId == id) return;
    selectedId = id;
    notifyListeners();
  }

  void setDrawing(bool on) {
    drawing = on;
    if (on) selectedId = null;
    notifyListeners();
  }

  /// New items land near the middle, slightly scattered so they don't stack.
  Offset _spot() => Offset(0.5 + (_rand.nextDouble() - 0.5) * 0.16,
      0.45 + (_rand.nextDouble() - 0.5) * 0.16);

  void add(OverlayLayer l) {
    layers.add(l);
    selectedId = l.id;
    drawing = false;
    notifyListeners();
  }

  Future<void> addText(BuildContext context) async {
    final r = await showTextSheet(context);
    if (r == null || !context.mounted) return;
    if (r.photoSticker) {
      await addPhotoSticker(context);
      return;
    }
    final spec = r.spec;
    if (spec != null) add(OverlayLayer.text(spec, center: _spot()));
  }

  Future<void> editText(BuildContext context, OverlayLayer l) async {
    final spec = l.text;
    if (spec == null) return;
    final r = await showTextSheet(context, initial: spec);
    if (r == null || !context.mounted) return;
    if (r.photoSticker) {
      await addPhotoSticker(context);
      return;
    }
    if (r.spec != null) {
      l.text = r.spec;
      notifyListeners();
    }
  }

  Future<void> addEmoji(BuildContext context) async {
    final e = await showEmojiPicker(context);
    if (e != null) add(OverlayLayer.emoji(e, center: _spot()));
  }

  Future<void> addSticker(BuildContext context) async {
    final pick = await showStickerPicker(context);
    if (pick == null || !context.mounted) return;
    if (pick.fromPhoto) {
      await addPhotoSticker(context);
    } else if (pick.asset != null) {
      add(OverlayLayer.sticker(pick.asset!, center: _spot()));
    }
  }

  Future<void> addPhotoSticker(BuildContext context) async {
    final png = await createPhotoSticker(context);
    if (png == null) return;
    add(OverlayLayer.photo(png, center: _spot()));
    if (context.mounted) {
      showSnack(context, 'Sticker added. Pinch to resize, drag to move.');
    }
  }

  void addAvatar(AvatarConfig config, String pose) =>
      add(OverlayLayer.avatar(config, pose, center: _spot()));

  void undoStroke() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
      notifyListeners();
    }
  }

  void clearStrokes() {
    strokes.clear();
    notifyListeners();
  }
}
