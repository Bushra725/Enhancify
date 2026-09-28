import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../avatar/avatar_panel.dart';
import '../../editor/draw.dart';
import '../../editor/editor_stage.dart';
import '../../editor/overlay_controller.dart';
import '../../l10n/l10n.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../export/export_screen.dart';
import 'collage_art.dart';
import 'collage_templates.dart';

/// Collage maker with Pinterest-style templates, backgrounds, text,
/// emoji, stickers, avatar and drawing. Saves a 2160 px wide image.
class CollageScreen extends StatefulWidget {
  const CollageScreen({super.key, this.initialPhotos = const []});
  final List<File> initialPhotos;

  @override
  State<CollageScreen> createState() => _CollageScreenState();
}

class _CollageScreenState extends State<CollageScreen> {
  final _overlay = OverlayController();
  final _stageKey = GlobalKey();
  CollageTemplate _t = collageTemplates.first;
  final List<Uint8List?> _slots = [];

  /// Every photo the user added, so switching layouts never loses any.
  final List<Uint8List> _pool = [];
  final List<TransformationController> _zoom = [];
  final Set<String> _seededIds = {};
  Color? _bgOverride;
  double _gap = 6;
  String _panel = 'layouts';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _overlay.addListener(_onOverlay);
    _resizeSlots();
    _seed();
    _loadInitial();
  }

  void _onOverlay() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overlay.removeListener(_onOverlay);
    _overlay.dispose();
    for (final z in _zoom) {
      z.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final photos = <Uint8List>[];
    for (final f in widget.initialPhotos) {
      try {
        photos.add(Uint8List.fromList(await f.readAsBytes()));
      } catch (_) {}
    }
    if (!mounted || photos.isEmpty) return;
    // Start with a layout that has room for every photo.
    if (photos.length > _t.slotCount) {
      final fit = collageTemplates.firstWhere(
        (t) => t.slotCount >= photos.length && !t.hasPhotoBackground,
        orElse: () => collageTemplates.first,
      );
      if (fit.id != _t.id) _useTemplate(fit);
    }
    for (final p in photos) {
      _put(p);
    }
  }

  /// Puts a photo in the first empty slot. Returns false if all are full.
  bool _put(Uint8List bytes) {
    if (!_pool.contains(bytes)) _pool.add(bytes);
    final i = _slots.indexWhere((s) => s == null);
    if (i < 0) return false;
    setState(() {
      _slots[i] = bytes;
      _zoom[i].value = Matrix4.identity();
    });
    return true;
  }

  void _resizeSlots() {
    // Photos currently shown first (in order), then the rest of the pool.
    final shown = _slots.whereType<Uint8List>().toList();
    final keep = [...shown, ..._pool.where((p) => !shown.contains(p))];
    _slots
      ..clear()
      ..addAll(keep.take(_t.slotCount));
    while (_slots.length < _t.slotCount) {
      _slots.add(null);
    }
    while (_zoom.length < _slots.length) {
      _zoom.add(TransformationController());
    }
    while (_zoom.length > _slots.length) {
      _zoom.removeLast().dispose();
    }
    for (final z in _zoom) {
      z.value = Matrix4.identity();
    }
  }

  /// Replaces the previous template's text/stickers with the new ones.
  /// Items the user added themselves are kept.
  void _seed() {
    _overlay.layers.removeWhere((l) => _seededIds.contains(l.id));
    _seededIds.clear();
    final made = [for (final s in _t.seeds) s.make()];
    _seededIds.addAll(made.map((l) => l.id));
    _overlay.layers.insertAll(0, made);
    _overlay.selectedId = null;
    _overlay.changed();
  }

  void _useTemplate(CollageTemplate t) {
    setState(() {
      _t = t;
      _bgOverride = null;
      _resizeSlots();
    });
    _seed();
    if (t.tip != null) showSnack(context, t.tip!);
  }

  Future<void> _addPhotos() async {
    final free = _slots.where((s) => s == null).length;
    if (free == 0) {
      showSnack(context, 'All frames are full. Pick a layout with more frames or tap a photo to replace it.');
      return;
    }
    final files = await MediaService.pickImages(limit: free);
    for (final f in files) {
      if (!mounted) return;
      _put(Uint8List.fromList(await f.readAsBytes()));
    }
  }

  Future<void> _pickInto(int i) async {
    final f = await MediaService.pickImage();
    if (f == null || !mounted) return;
    final bytes = Uint8List.fromList(await f.readAsBytes());
    if (!mounted) return;
    final old = _slots[i];
    setState(() {
      if (old != null) _pool.remove(old);
      _pool.add(bytes);
      _slots[i] = bytes;
      _zoom[i].value = Matrix4.identity();
    });
  }

  Future<void> _slotMenu(int i) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(context.tr('replacePhoto')),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            ListTile(
              leading: const Icon(Icons.zoom_out_map),
              title: Text(context.tr('resetZoom')),
              subtitle: Text(context.tr('pinchHint')),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.primary),
              title: Text(context.tr('removePhoto')),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'replace':
        await _pickInto(i);
      case 'reset':
        setState(() => _zoom[i].value = Matrix4.identity());
      case 'remove':
        setState(() {
          final old = _slots[i];
          if (old != null) _pool.remove(old);
          _slots[i] = null;
          _zoom[i].value = Matrix4.identity();
        });
    }
  }

  Future<void> _save() async {
    if (_slots.every((s) => s == null)) {
      showSnack(context, 'Add some photos first.');
      return;
    }
    setState(() => _saving = true);
    try {
      final png = await captureStage(_stageKey, _overlay, targetWidth: 2160);
      if (png == null) {
        if (mounted) showSnack(context, 'Could not save. Please try again.');
        return;
      }
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      setState(() => _saving = false);
      await ExportScreen.open(context, file);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not render the collage.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openPanel(String id) {
    setState(() => _panel = id);
    _overlay.setDrawing(id == 'draw');
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final filled = _slots.where((s) => s != null).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('collage')),
        actions: [
          IconButton(
            tooltip: 'Add photos',
            onPressed: _addPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.tr('done')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _t.aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: EditorStage(
                      controller: _overlay,
                      boundaryKey: _stageKey,
                      child: _board(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '$filled of ${_slots.length} photos · tap a frame to add · pinch to zoom',
              style: TextStyle(fontSize: 12, color: context.palette.textMuted),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                _tab(Icons.dashboard_customize_outlined, 'Layouts', 'layouts'),
                _tab(Icons.format_color_fill, 'Background', 'bg'),
                _tab(Icons.text_fields, 'Text', 'text'),
                _tab(Icons.emoji_emotions_outlined, 'Emoji', 'emoji'),
                _tab(Icons.auto_awesome, 'Stickers', 'sticker'),
                _tab(Icons.face_retouching_natural, 'Avatar', 'avatar'),
                _tab(Icons.brush_outlined, 'Draw', 'draw'),
              ],
            ),
          ),
          SizedBox(
            height: _panel == 'layouts' ? 150 : (_panel == 'draw' ? 240 : (_panel == 'avatar' ? 196 : 150)),
            child: SafeArea(top: false, child: _panelBody()),
          ),
        ],
      ),
    );
  }

  Widget _tab(IconData icon, String label, String id) {
    final sel = _panel == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16, color: sel ? Colors.white : AppColors.primary),
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
            color: sel ? Colors.white : context.palette.textPrimary,
            fontWeight: FontWeight.w600),
        onSelected: (_) => _openPanel(id),
      ),
    );
  }

  Widget _panelBody() {
    final palette = context.palette;
    switch (_panel) {
      case 'bg':
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          children: [
            ColorRow(
              selected: _bgOverride ?? _t.bgColor,
              onPick: (c) => setState(() => _bgOverride = c),
            ),
            if (_t.adjustableGap)
              Row(
                children: [
                  Text(context.tr('spacing')),
                  Expanded(
                    child: Slider(
                      value: _gap,
                      min: 0,
                      max: 24,
                      onChanged: (v) => setState(() => _gap = v),
                    ),
                  ),
                ],
              )
            else if (_t.bg == BgKind.photo || _t.bg == BgKind.blurPhoto)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t.bg == BgKind.photo
                      ? 'This layout uses your first photo as the background. Tap the background to change it.'
                      : 'The background is a soft blur of your first photo.',
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              ),
          ],
        );
      case 'text':
        return _actions([
          ('Add text', Icons.text_fields, () => _overlay.addText(context)),
          ('Photo sticker', Icons.add_photo_alternate_outlined, () => _overlay.addPhotoSticker(context)),
        ]);
      case 'emoji':
        return _actions([
          ('All emoji', Icons.emoji_emotions_outlined, () => _overlay.addEmoji(context)),
        ]);
      case 'sticker':
        return _actions([
          ('Aesthetic stickers', Icons.auto_awesome, () => _overlay.addSticker(context)),
          ('From my photo', Icons.person_add_alt, () => _overlay.addPhotoSticker(context)),
        ]);
      case 'avatar':
        return AvatarPanel(onPick: _overlay.addAvatar);
      case 'draw':
        return DrawPanel(
          settings: _overlay.draw,
          onChanged: () => setState(() {}),
          onUndo: _overlay.undoStroke,
          onClear: _overlay.clearStrokes,
          canUndo: _overlay.strokes.isNotEmpty,
        );
      default:
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          itemCount: collageTemplates.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final t = collageTemplates[i];
            final sel = t.id == _t.id;
            return GestureDetector(
              onTap: () => _useTemplate(t),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? AppColors.primary : palette.border,
                          width: sel ? 2.5 : 1,
                        ),
                      ),
                      child: AspectRatio(
                        aspectRatio: t.aspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _TemplateThumb(t),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(t.name,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                          color: sel ? AppColors.primary : palette.textPrimary)),
                ],
              ),
            );
          },
        );
    }
  }

  Widget _actions(List<(String, IconData, VoidCallback)> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final (label, icon, onTap) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blush,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: onTap,
                  icon: Icon(icon),
                  label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ the board
  Widget _board() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final bgColor = _bgOverride ?? _t.bgColor;
      final frameOffset = _t.hasPhotoBackground ? 1 : 0;
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: _background(bgColor, w)),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                  painter: DecoPainter(_t.decos.where((d) => !d.front).toList())),
            ),
          ),
          for (var i = 0; i < _t.frames.length; i++)
            _frame(i + frameOffset, _t.frames[i], w, h),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                  painter: DecoPainter(_t.decos.where((d) => d.front).toList())),
            ),
          ),
        ],
      );
    });
  }

  Widget _background(Color color, double boardW) {
    switch (_t.bg) {
      case BgKind.paper:
        return CustomPaint(painter: PaperPainter(color));
      case BgKind.grid:
        return CustomPaint(painter: GridPainter(color));
      case BgKind.blurPhoto:
        final src = _slots.isNotEmpty ? _slots.first : null;
        if (src == null) return ColoredBox(color: color);
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.mirror),
              child: Image.memory(src, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 600),
            ),
            ColoredBox(color: _bgOverride?.withValues(alpha: 0.55) ?? _t.tint ?? Colors.transparent),
          ],
        );
      case BgKind.photo:
        final src = _slots.isNotEmpty ? _slots.first : null;
        return GestureDetector(
          onTap: () => src == null ? _pickInto(0) : _slotMenu(0),
          child: src == null
              ? Container(
                  color: color == Colors.white ? AppColors.blush : color,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.all(10),
                  child: const _AddHint(label: 'Tap to add background photo'),
                )
              : InteractiveViewer(
                  transformationController: _zoom[0],
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: Image.memory(src,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        cacheWidth: (boardW * 4).round().clamp(600, 2600)),
                  ),
                ),
        );
      case BgKind.color:
        return ColoredBox(color: color);
    }
  }

  Widget _frame(int slot, CFrame f, double w, double h) {
    var rect = Rect.fromLTWH(f.x * w, f.y * h, f.w * w, f.h * h);
    if (_t.adjustableGap) {
      rect = rect.deflate(_gap / 2);
      // Keep the outer margin equal to the inner gap.
      rect = Rect.fromLTRB(
        f.x == 0 ? rect.left + _gap / 2 : rect.left,
        f.y == 0 ? rect.top + _gap / 2 : rect.top,
        f.x + f.w >= 0.999 ? rect.right - _gap / 2 : rect.right,
        f.y + f.h >= 0.999 ? rect.bottom - _gap / 2 : rect.bottom,
      );
    }
    if (rect.width <= 2 || rect.height <= 2) return const SizedBox.shrink();
    return Positioned.fromRect(
      rect: rect,
      child: Transform.rotate(
        angle: f.rot * math.pi / 180,
        child: _frameBody(slot, f, rect.size),
      ),
    );
  }

  Widget _frameBody(int slot, CFrame f, Size size) {
    final bytes = slot < _slots.length ? _slots[slot] : null;
    final short = math.min(size.width, size.height);
    final photo = bytes == null
        ? Container(
            color: const Color(0xFFFFE3EF),
            alignment: Alignment.center,
            child: const _AddHint(label: 'Add'),
          )
        : InteractiveViewer(
            transformationController: _zoom[slot],
            minScale: 1,
            maxScale: 5,
            child: SizedBox.expand(
              child: Image.memory(bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: (size.width * 6).round().clamp(300, 2400)),
            ),
          );

    Widget body;
    switch (f.style) {
      case FrameStyle.plain:
        body = ClipRect(child: photo);
      case FrameStyle.rounded:
        body = ClipRRect(
            borderRadius: BorderRadius.circular(short * f.radius), child: photo);
      case FrameStyle.circle:
        body = Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: ClipOval(child: photo),
        );
      case FrameStyle.bordered:
        body = Container(
          padding: EdgeInsets.all(short * 0.035),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: ClipRect(child: photo),
        );
      case FrameStyle.polaroid:
        final pad = short * 0.06;
        body = Container(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad * 3.2),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: ClipRect(child: photo),
        );
      case FrameStyle.scallop:
        body = Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(clipper: PathClipper(scallopPath), child: photo),
            IgnorePointer(
              child: CustomPaint(
                painter: PathBorderPainter(scallopPath, width: math.max(2.5, short * 0.025)),
              ),
            ),
          ],
        );
      case FrameStyle.arch:
        body = Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(clipper: PathClipper(archPath), child: photo),
            IgnorePointer(
              child: CustomPaint(
                painter: PathBorderPainter(archPath, width: math.max(2.5, short * 0.03)),
              ),
            ),
          ],
        );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => bytes == null ? _pickInto(slot) : _slotMenu(slot),
      child: body,
    );
  }
}

class _AddHint extends StatelessWidget {
  const _AddHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_circle, color: AppColors.primary, size: 22),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Small non-interactive preview of a template for the layout picker.
class _TemplateThumb extends StatelessWidget {
  const _TemplateThumb(this.t);
  final CollageTemplate t;

  static const _fills = [
    Color(0xFFFF9CC5), Color(0xFFB892FF), Color(0xFFFFB547),
    Color(0xFF8EC5F0), Color(0xFF9DB89A), Color(0xFFFF7A9A),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      Widget bg;
      switch (t.bg) {
        case BgKind.paper:
          bg = CustomPaint(painter: PaperPainter(t.bgColor));
        case BgKind.grid:
          bg = CustomPaint(painter: GridPainter(t.bgColor));
        case BgKind.photo:
          bg = const DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF7FB77E), Color(0xFF3E6B45)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)));
        case BgKind.blurPhoto:
          bg = ColoredBox(color: t.bgColor);
        case BgKind.color:
          bg = ColoredBox(color: t.bgColor);
      }
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: bg),
          for (var i = 0; i < t.frames.length; i++)
            Positioned(
              left: t.frames[i].x * w + (t.adjustableGap ? 1 : 0),
              top: t.frames[i].y * h + (t.adjustableGap ? 1 : 0),
              width: t.frames[i].w * w - (t.adjustableGap ? 2 : 0),
              height: t.frames[i].h * h - (t.adjustableGap ? 2 : 0),
              child: Transform.rotate(
                angle: t.frames[i].rot * math.pi / 180,
                child: Container(
                  padding: t.frames[i].style == FrameStyle.polaroid
                      ? const EdgeInsets.fromLTRB(1.5, 1.5, 1.5, 4)
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: t.frames[i].style == FrameStyle.polaroid
                        ? Colors.white
                        : _fills[i % _fills.length],
                    shape: t.frames[i].style == FrameStyle.circle
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    borderRadius: t.frames[i].style == FrameStyle.rounded ||
                            t.frames[i].style == FrameStyle.scallop
                        ? BorderRadius.circular(4)
                        : (t.frames[i].style == FrameStyle.arch
                            ? BorderRadius.vertical(top: Radius.circular(t.frames[i].w * w / 2))
                            : null),
                  ),
                  child: t.frames[i].style == FrameStyle.polaroid
                      ? ColoredBox(color: _fills[i % _fills.length])
                      : null,
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(painter: DecoPainter(t.decos)),
          ),
        ],
      );
    });
  }
}
