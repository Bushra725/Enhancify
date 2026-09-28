import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../avatar/avatar_panel.dart';
import '../../data/sticker_data.dart';
import '../../editor/draw.dart';
import '../../editor/editor_stage.dart';
import '../../editor/layers.dart';
import '../../editor/mask_painter.dart';
import '../../editor/overlay_controller.dart';
import '../../editor/text_templates.dart';
import '../../editor/text_view.dart';
import '../../l10n/l10n.dart';
import '../../services/app_state.dart';
import '../../services/local_enhance.dart';
import '../../services/media_service.dart';
import '../../services/object_remover.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../collage/collage_screen.dart';
import '../paywall/paywall_screen.dart';
import '../export/export_screen.dart';
import '../tools/beauty_screen.dart';
import '../tools/bg_remover_screen.dart';
import '../tools/crop_rotate_screen.dart';
import '../tools/gif_maker_screen.dart';
import '../tools/music_screen.dart';
import '../tools/passport_screen.dart';
import '../tools/remove_object_screen.dart';
import 'makeup_panel.dart';

/// On-device editor. Every tool below runs on the phone.
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.file, this.tool = 'enhance'});

  final File file;
  final String tool;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

/// One adjustment slider definition.
class _Adj {
  const _Adj(this.id, this.label, this.icon, this.min, this.max, this.neutral);
  final String id;
  final String label;
  final IconData icon;
  final double min;
  final double max;
  final double neutral;
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _engine = LocalEnhance();
  final _stageKey = GlobalKey();
  final _overlay = OverlayController();
  Uint8List? _original;
  Uint8List? _preview;
  double _aspect = 1;

  /// Aspect of the unedited photo (used to make true square / 9:16 crops).
  double _origAspect = 1;
  String _look = 'none';
  String _filter = 'none';
  String _crop = 'free';
  String _panel = 'adjust';
  String _adj = 'brightness';
  int _turns = 0;
  bool _watermark = true;
  bool _busy = false;
  bool _rendering = false;
  bool _renderAgain = false;
  String? _error;

  final Map<String, double> _values = {};

  /// Adjustment values already baked into [_preview]; the live preview
  /// matrix only applies the difference, so nothing is applied twice.
  Map<String, double> _baked = {};
  String _frame = 'none';
  bool _meme = false;
  String _memeText = '';
  bool _splash = false;
  final List<Uint8List> _history = [];
  final List<Uint8List> _future = [];
  final List<MaskOp> _mask = [];
  double _brush = 0.035;
  FillMode _fillMode = FillMode.smooth;
  bool _maskErase = false;

  static const _adjustments = [
    _Adj('brightness', 'Brightness', Icons.wb_sunny_outlined, 0.6, 1.5, 1),
    _Adj('contrast', 'Contrast', Icons.contrast, 0.6, 1.6, 1),
    _Adj('exposure', 'Exposure', Icons.exposure, -1, 1, 0),
    _Adj('saturation', 'Saturation', Icons.water_drop_outlined, 0, 2, 1),
    _Adj('vibrance', 'Vibrance', Icons.color_lens_outlined, -0.8, 0.8, 0),
    _Adj('warmth', 'Warmth', Icons.thermostat_outlined, -1, 1, 0),
    _Adj('tint', 'Tint', Icons.gradient, -40, 40, 0),
    _Adj('lightness', 'Lightness', Icons.light_mode_outlined, -0.6, 0.6, 0),
    _Adj('highlight', 'Highlights', Icons.highlight_outlined, -0.6, 0.8, 0),
    _Adj('fade', 'Fade', Icons.blur_on, 0, 1, 0),
    _Adj('grain', 'Grain', Icons.grain, 0, 30, 0),
  ];

  static const _filterKeys = {
    'none': 'filterOriginal',
    'vivid': 'filterVivid',
    'warm': 'filterWarm',
    'cool': 'filterCool',
    'bw': 'filterBw',
    'sepia': 'filterSepia',
    'vintage': 'filterVintage',
    'noir': 'filterNoir',
    'pencil': 'filterPencil',
    'cartoon': 'filterCartoon',
    'avatar3d': 'filterToon',
    'pixel': 'filterPixel',
    'clay': 'filterClay',
    'sketch': 'filterSketch',
  };

  String _filterKey(String id) => _filterKeys[id] ?? id;

  static const _filters = <(String, String)>[
    ('none', 'Original'), ('vivid', 'Vivid'), ('warm', 'Warm'), ('cool', 'Cool'),
    ('bw', 'B&W'), ('sepia', 'Sepia'), ('vintage', 'Vintage'), ('noir', 'Noir'),
    ('pencil', 'Pencil'), ('cartoon', 'Cartoon'), ('avatar3d', '3D Toon'),
    ('pixel', 'Pixel'), ('clay', 'Clay'), ('sketch', 'Sketch'),
  ];

  static const _quickEmoji = ['😍', '🥰', '✨', '💖', '🔥', '😂', '🌸', '🦋', '💫', '🎀', '🫶', '😎', '🌈', '👑', '💕', '🌙'];

  double _v(String id) =>
      _values[id] ?? _adjustments.firstWhere((a) => a.id == id).neutral;

  @override
  void initState() {
    super.initState();
    if (widget.tool == 'restore') {
      _look = 'restore';
      _panel = 'restore';
    } else if (widget.tool == 'enhance') {
      _look = 'enhance';
      _panel = 'enhance';
    }
    _overlay.addListener(_onOverlay);
    if (widget.tool == 'collage') {
      // The collage maker has its own screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          settings: const RouteSettings(name: 'collage'),
          builder: (_) => CollageScreen(initialPhotos: [widget.file]),
        ));
      });
      return;
    }
    _load();
  }

  void _onOverlay() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overlay.removeListener(_onOverlay);
    _overlay.dispose();
    super.dispose();
  }

  /// Width / height of an encoded image, read from its header.
  static Future<double?> _aspectOf(Uint8List bytes) async {
    try {
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final w = desc.width, h = desc.height;
      desc.dispose();
      buf.dispose();
      return w > 0 && h > 0 ? w / h : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      if (!mounted) return;
      final photo = Uint8List.fromList(bytes);
      final a = await _aspectOf(photo) ?? 1;
      if (!mounted) return;
      setState(() {
        _original = photo;
        _preview = photo;
        _aspect = a;
        _origAspect = a;
      });
      if (widget.tool == 'crop' || widget.tool == 'rotate') {
        await _openCrop(rotate: widget.tool == 'rotate');
        return;
      }
      if (widget.tool == 'edit') return;
      await _render();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this photo.');
    }
  }

  /// Centered crop box (fractions) giving a true 1:1 or 9:16 result.
  (double, double, double, double) get _cropBox {
    final a = _turns.isOdd ? 1 / _origAspect : _origAspect;
    (double, double, double, double) fit(double t) {
      if (a > t) {
        final m = (1 - t / a) / 2;
        return (m, 0, 1 - m, 1);
      }
      final m = (1 - a / t) / 2;
      return (0, m, 1, 1 - m);
    }

    switch (_crop) {
      case 'square':
        return fit(1);
      case 'story':
        return fit(9 / 16);
      default:
        return (0, 0, 1, 1);
    }
  }

  /// Bakes the current edit. [maxSide] 900 for the preview, larger to save.
  Future<List<int>> _bakeWith(Uint8List src, {int maxSide = 900, bool? watermark}) {
    final box = _cropBox;
    final pro = context.read<AppState>().isPro;
    return _engine.bakeOffUi(
      src,
      look: _look,
      brightness: _v('brightness'),
      contrast: _v('contrast'),
      exposure: _v('exposure'),
      lightness: _v('lightness'),
      highlight: _v('highlight'),
      saturation: _v('saturation'),
      vibrance: _v('vibrance'),
      tint: _v('tint'),
      fade: _v('fade'),
      grain: _v('grain'),
      warmth: _v('warmth'),
      filter: _filter,
      frame: _frame,
      text: _meme ? _memeText : '',
      meme: _meme,
      watermark: watermark ?? (pro ? _watermark : true),
      quarterTurns: _turns,
      cropLeft: box.$1,
      cropTop: box.$2,
      cropRight: box.$3,
      cropBottom: box.$4,
      maxSide: maxSide,
    );
  }

  Future<void> _render() async {
    final src = _original;
    if (src == null) return;
    if (_rendering) {
      _renderAgain = true;
      return;
    }
    _rendering = true;
    if (mounted) setState(() => _busy = true);
    try {
      while (mounted) {
        _renderAgain = false;
        final current = _original;
        if (current == null) break;
        final snapshot = Map<String, double>.of(_values);
        final bytes = await _bakeWith(current, watermark: false);
        if (!mounted) return;
        if (_renderAgain) continue;
        final out = Uint8List.fromList(bytes);
        final a = await _aspectOf(out);
        if (!mounted) return;
        setState(() {
          _preview = out;
          _baked = snapshot;
          _error = null;
          if (a != null) _aspect = a;
        });
        break;
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not edit this photo.');
    } finally {
      _rendering = false;
      if (mounted) setState(() => _busy = false);
      if (_renderAgain && mounted) {
        _render();
      }
    }
  }

  Future<File> _write(List<int> bytes, String ext) async {
    final out = File('${Directory.systemTemp.path}/edit_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  /// Renders the finished photo at full resolution (up to [maxSide] px).
  /// Text, stickers and drawings are rendered on top at the same resolution.
  Future<File?> _renderFinal({int maxSide = 3072}) async {
    final src = _original;
    if (src == null) return null;
    final full = Uint8List.fromList(await _bakeWith(src, maxSide: maxSide));
    if (!_overlay.hasContent) return _write(full, 'jpg');
    final codec = await ui.instantiateImageCodec(full);
    final frame = await codec.getNextFrame();
    final fullWidth = frame.image.width;
    frame.image.dispose();
    codec.dispose();
    final overlay = await captureStage(_stageKey, _overlay,
        targetWidth: fullWidth.toDouble(), overlayOnly: true);
    if (overlay == null) return null;
    final png = await compositeOverlay(full, overlay);
    return _write(png, 'png');
  }

  /// "Done": render, then open the save / share / post screen.
  Future<void> _done() async {
    if (_original == null) return;
    setState(() => _busy = true);
    try {
      final file = await _renderFinal();
      if (!mounted) return;
      if (file == null) {
        showSnack(context, 'Could not render the photo. Please try again.');
        return;
      }
      setState(() => _busy = false);
      await ExportScreen.open(context, file);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not render this photo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens a tool screen with the current edit rendered to a file.
  Future<void> _withRendered(int maxSide, Future<void> Function(File file) open) async {
    if (_original == null || _busy) return;
    setState(() => _busy = true);
    File? file;
    try {
      file = await _renderFinal(maxSide: maxSide);
    } catch (_) {
      file = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (file == null) {
      showSnack(context, 'Could not render the photo. Please try again.');
      return;
    }
    await open(file);
  }

  Future<void> _openCrop({bool rotate = false}) async {
    final src = _original;
    if (src == null || _busy) return;
    final out = await CropRotateScreen.open(context, src, rotate: rotate);
    if (out == null || !mounted) return;
    _replaceOriginal(out);
    final a = await _aspectOf(out);
    if (!mounted) return;
    setState(() {
      _crop = 'free';
      _turns = 0;
      if (a != null) {
        _origAspect = a;
        _aspect = a;
      }
    });
    await _render();
  }

  Future<void> _openBeauty() async {
    final src = _original;
    if (src == null || _busy) return;
    final out = await BeautyScreen.open(context, src);
    if (out == null || !mounted) return;
    _replaceOriginal(out);
    await _render();
    if (mounted) showSnack(context, context.tr('beautyApplied'));
  }

  Future<void> _openRemover() async {
    final src = _original;
    if (src == null || _busy) return;
    final out = await RemoveObjectScreen.open(context, src);
    if (out == null || !mounted) return;
    _replaceOriginal(out);
    await _render();
    if (mounted) showSnack(context, 'Object removed ✨');
  }

  Future<void> _music() => _withRendered(1600, (file) async {
        await Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: 'music'),
          builder: (_) => MusicScreen(image: file),
        ));
      });

  /// Canva-style remover: shows the cut-out right away, then save/share.
  Future<void> _removeBackground() async {
    final src = _original;
    if (src == null || _busy) return;
    setState(() => _busy = true);
    Uint8List? photo;
    try {
      photo = Uint8List.fromList(await _bakeWith(src, maxSide: 2048, watermark: false));
    } catch (_) {
      photo = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final p = photo;
    if (p == null) {
      showSnack(context, 'Could not read this photo.');
      return;
    }
    await BgRemoverScreen.open(context, p);
  }

  Future<void> _gif() => _withRendered(900, (file) async {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: 'gif'),
          builder: (_) => GifMakerScreen(photos: [bytes]),
        ));
      });

  void _remember() {
    final src = _original;
    if (src == null) return;
    _history.add(Uint8List.fromList(src));
    if (_history.length > 20) _history.removeAt(0);
    _future.clear();
  }

  void _replaceOriginal(List<int> bytes) {
    _remember();
    _original = Uint8List.fromList(bytes);
  }

  Offset _photoPoint(Offset local) {
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width == 0 || box.size.height == 0) {
      return Offset.zero;
    }
    return Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
  }

  Future<void> _runRemove() async {
    final src = _original;
    if (src == null || !_mask.any((o) => o.kind != MaskOpKind.erase)) {
      showSnack(context, 'Paint over the spots you want to fix.');
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    try {
      final bytes = await removeMarked(src, List<MaskOp>.of(_mask), mode: _fillMode);
      _mask.clear();
      _replaceOriginal(bytes);
      await _render();
      if (mounted) showSnack(context, 'Marks removed.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not remove that area.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undo() {
    if (_history.isEmpty || _original == null) return;
    _future.add(Uint8List.fromList(_original!));
    _original = _history.removeLast();
    _render();
  }

  void _redo() {
    if (_future.isEmpty) return;
    _history.add(Uint8List.fromList(_original!));
    _original = _future.removeLast();
    _render();
  }

  Future<void> _splashAt(Offset local) async {
    final src = _original;
    final shown = _preview;
    if (src == null || shown == null) return;
    final pt = _photoPoint(local);
    final color = _engine.sampleColor(shown, pt.dx, pt.dy);
    setState(() {
      _busy = true;
      _splash = false;
    });
    try {
      _replaceOriginal(await _engine.colorSplashOffUi(
        src,
        r: color.$1,
        g: color.$2,
        b: color.$3,
      ));
      await _render();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redEye() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      _replaceOriginal(await _engine.redEyeOffUi(src));
      await _render();
      if (mounted) showSnack(context, 'Red-eye reduced in the eye area.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blend() async {
    final extra = await MediaService.pickImage();
    if (extra == null || _original == null) return;
    setState(() => _busy = true);
    try {
      _replaceOriginal(_engine.doubleExposure(_original!, await extra.readAsBytes()));
      await _render();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passport() async {
    final src = _original;
    if (src == null || _busy) return;
    setState(() => _busy = true);
    Uint8List? photo;
    try {
      // Colour edits yes, stickers/text no (not allowed on ID photos).
      // No brand watermark either: it would end up on the ID photo.
      photo = Uint8List.fromList(await _bakeWith(src, maxSide: 1600, watermark: false));
    } catch (_) {
      photo = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final baked = photo;
    if (baked == null) {
      showSnack(context, 'Could not read this photo.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: 'passport'),
      builder: (_) => PassportScreen(photo: baked),
    ));
  }

  Future<void> _toggleMeme() async {
    if (_meme) {
      setState(() => _meme = false);
      await _render();
      return;
    }
    final caption = await showDialog<String>(
      context: context,
      builder: (_) => const _MemeBarsDialog(),
    );
    if (caption == null || caption.isEmpty || !mounted) return;
    setState(() {
      _meme = true;
      _memeText = caption;
      _error = null;
    });
    await _render();
    if (mounted && _error != null) {
      showSnack(context, _error!);
    }
  }

  Future<void> _exif() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    final tags = await _engine.readExifOffUi(src);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('photoDetails')),
        content: SizedBox(
          width: 320,
          child: tags.isEmpty
              ? Text(context.tr('noExif'))
              : SingleChildScrollView(
                  child: Text(tags.entries.map((e) => '${e.key}\n${e.value}').join('\n\n')),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              _replaceOriginal(_engine.stripAndCompress(src));
              if (ctx.mounted) Navigator.pop(ctx);
              await _render();
              if (mounted) showSnack(context, 'Metadata removed and photo compressed.');
            },
            child: Text(context.tr('stripMeta')),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('close'))),
        ],
      ),
    );
  }

  Future<void> _batch() async {
    final files = await MediaService.pickImages(limit: 8);
    if (files.isEmpty) return;
    setState(() => _busy = true);
    var saved = 0;
    for (final f in files) {
      try {
        final jpg = _engine.stripAndCompress(await f.readAsBytes());
        final out = await _write(jpg, 'jpg');
        if (await MediaService.saveToGallery(out) == null) saved++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _busy = false);
      showSnack(context, 'Compressed and saved $saved photo${saved == 1 ? '' : 's'}.');
    }
  }

  void _openPanel(String id) {
    if (id == 'remove') {
      _openRemover();
      return;
    }
    if (id == 'crop') {
      _openCrop();
      return;
    }
    if (id == 'beauty') {
      _openBeauty();
      return;
    }
    setState(() => _panel = id);
    _overlay.setDrawing(id == 'draw');
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
        actions: [
          IconButton(onPressed: _history.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(onPressed: _future.isEmpty ? null : _redo, icon: const Icon(Icons.redo)),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: preview == null || _busy ? null : _done,
              child: Text(context.tr('done')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: preview == null
                    ? Text(_error ?? 'Opening photo...')
                    : AspectRatio(
                        aspectRatio: _aspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              EditorStage(
                                controller: _overlay,
                                boundaryKey: _stageKey,
                                child: ColorFiltered(
                                  colorFilter: ColorFilter.matrix(_previewMatrix()),
                                  child: Image.memory(preview,
                                      fit: BoxFit.fill, gaplessPlayback: true),
                                ),
                              ),
                              if (_watermark)
                                const Positioned(
                                  right: 10,
                                  bottom: 8,
                                  child: Text(
                                    'Enhancify',
                                    style: TextStyle(
                                      color: Color(0xFFEA026A),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      shadows: [Shadow(color: Colors.white, blurRadius: 2)],
                                    ),
                                  ),
                                ),
                              if (widget.tool == 'restore' || _splash)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: _splash ? (d) => _splashAt(d.localPosition) : null,
                                  onPanStart: widget.tool == 'restore' && !_splash
                                      ? (d) => setState(() => _mask.add(MaskOp(
                                          _maskErase ? MaskOpKind.erase : MaskOpKind.brush,
                                          _brush,
                                          [_photoPoint(d.localPosition)])))
                                      : null,
                                  onPanUpdate: widget.tool == 'restore' && !_splash
                                      ? (d) => setState(() {
                                            if (_mask.isNotEmpty) _mask.last.points.add(_photoPoint(d.localPosition));
                                          })
                                      : null,
                                  child: CustomPaint(painter: MaskOpsPainter(_mask)),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
          if (_splash)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(context.tr('tapColor'),
                  style: TextStyle(color: palette.textSecondary)),
            ),
          if (!_focusedTool)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [
                  _tab(Icons.tune, context.tr('adjust'), 'adjust'),
                  _tab(Icons.filter_vintage_outlined, context.tr('filter'), 'filter'),
                  _tab(Icons.auto_awesome_outlined, context.tr('beauty'), 'beauty'),
                  _tab(Icons.crop_rotate, context.tr('crop'), 'crop'),
                  _tab(Icons.auto_fix_high, context.tr('remove'), 'remove'),
                  _tab(Icons.text_fields, context.tr('text'), 'text'),
                  _tab(Icons.emoji_emotions_outlined, context.tr('emoji'), 'emoji'),
                  _tab(Icons.auto_awesome, context.tr('stickers'), 'sticker'),
                  _tab(Icons.face_retouching_natural, context.tr('avatar'), 'avatar'),
                  _tab(Icons.brush_outlined, context.tr('draw'), 'draw'),
                  _tab(Icons.face_2_outlined, context.tr('makeup'), 'makeup'),
                  _tab(Icons.more_horiz, context.tr('more'), 'more'),
                ],
              ),
            ),
          SizedBox(
            height: _panelHeight,
            child: SafeArea(top: false, child: _panelBody()),
          ),
        ],
      ),
    );
  }

  double get _panelHeight {
    switch (_panel) {
      case 'makeup':
      case 'restore':
        return 280;
      case 'draw':
        return 240;
      case 'text':
      case 'sticker':
        return 196;
      case 'avatar':
        return 200;
      default:
        return 170;
    }
  }

  Widget _tab(IconData icon, String label, String id) {
    final sel = _panel == id;
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16, color: sel ? Colors.white : AppColors.primary),
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: sel ? Colors.white : palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) => _openPanel(id),
      ),
    );
  }

  bool get _focusedTool => widget.tool == 'restore' || widget.tool == 'enhance';

  String get _screenTitle {
    switch (widget.tool) {
      case 'restore':
        return context.tr('restore');
      case 'enhance':
        return context.tr('enhance');
      default:
        return context.tr('editPhoto');
    }
  }

  Widget _panelBody() {
    final palette = context.palette;
    switch (_panel) {
      case 'filter':
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          children: [
            for (final (id, _) in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(context.tr(_filterKey(id))),
                  selected: _filter == id,
                  onSelected: (_) {
                    setState(() => _filter = id);
                    _render();
                  },
                ),
              ),
          ],
        );
      case 'text':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () => _overlay.addText(context),
                      icon: const Icon(Icons.text_fields),
                      label: Text(context.tr('addText')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _overlay.addPhotoSticker(context),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(context.tr('photoSticker')),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              child: Text(context.tr('popularStyles'),
                  style: TextStyle(fontSize: 12, color: palette.textMuted)),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: textTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final spec = textTemplates[i].build();
                  final light = spec.color.computeLuminance() > 0.6 &&
                      spec.bg != TextBg.label &&
                      spec.bg != TextBg.tiles;
                  return GestureDetector(
                    onTap: () => _overlay.add(OverlayLayer.text(textTemplates[i].build())),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.all(8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: light ? const Color(0xFF8C6B7A) : palette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.border),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: TextLayerView(spec: spec, fontSize: 18, maxWidth: 220),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      case 'emoji':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => _overlay.addEmoji(context),
                icon: const Icon(Icons.emoji_emotions_outlined),
                label: Text(context.tr('allEmoji')),
              ),
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final e in _quickEmoji)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _overlay.add(OverlayLayer.emoji(e)),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                ],
              ),
            ),
          ],
        );
      case 'sticker':
        final quick = [for (final c in stickerCategories) ...c.assets.take(4)];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () => _overlay.addSticker(context),
                      icon: const Icon(Icons.grid_view_rounded),
                      label: Text(context.tr('allStickers')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _overlay.addPhotoSticker(context),
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(context.tr('fromMyPhoto')),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: quick.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _overlay.add(OverlayLayer.sticker(quick[i])),
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(quick[i], fit: BoxFit.contain, cacheWidth: 180),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'avatar':
        return AvatarPanel(onPick: _overlay.addAvatar);
      case 'makeup':
        final photo = _original;
        if (photo == null) return const SizedBox.shrink();
        return MakeupPanel(
          photo: photo,
          onPreview: (bytes) async {
            final a = await _aspectOf(bytes);
            if (!mounted) return;
            setState(() {
              _preview = bytes;
              _baked = const {};
              if (a != null) _aspect = a;
            });
          },
          onApply: (bytes) {
            _replaceOriginal(bytes);
            _render();
          },
        );
      case 'draw':
        return DrawPanel(
          settings: _overlay.draw,
          onChanged: () => setState(() {}),
          onUndo: _overlay.undoStroke,
          onClear: _overlay.clearStrokes,
          canUndo: _overlay.strokes.isNotEmpty,
        );
      case 'restore':
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          children: [
            Text(context.tr('restoreBlurb')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _action(_look == 'restore' ? 'Restore on' : 'Restore photo', () {
                  setState(() => _look = _look == 'restore' ? 'none' : 'restore');
                  _render();
                }),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Brush'),
                Expanded(
                  child: Slider(
                    value: _brush,
                    min: 0.012,
                    max: 0.09,
                    onChanged: (v) => setState(() => _brush = v),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(context.tr('paint')),
                  avatar: const Icon(Icons.brush, size: 16),
                  selected: !_maskErase,
                  onSelected: (_) => setState(() => _maskErase = false),
                ),
                ChoiceChip(
                  label: Text(context.tr('eraser')),
                  avatar: const Icon(Icons.auto_fix_off, size: 16),
                  selected: _maskErase,
                  onSelected: (_) => setState(() => _maskErase = true),
                ),
                ChoiceChip(
                  label: Text(context.tr('smoothFill')),
                  tooltip: 'Seamless blend of the colors around. Best for scratches, dust and spots.',
                  selected: _fillMode == FillMode.smooth,
                  onSelected: (_) => setState(() => _fillMode = FillMode.smooth),
                ),
                ChoiceChip(
                  label: Text(context.tr('textureFill')),
                  tooltip: 'Rebuilds the area from matching texture in the photo (like Photoshop content-aware fill).',
                  selected: _fillMode == FillMode.texture,
                  onSelected: (_) => setState(() => _fillMode = FillMode.texture),
                ),
                ActionChip(
                  label: Text(context.tr('undoMark')),
                  onPressed: _mask.isEmpty ? null : () => setState(() => _mask.removeLast()),
                ),
                ActionChip(
                  label: Text(context.tr('clearMask')),
                  onPressed: () => setState(() => _mask.clear()),
                ),
                ActionChip(
                  label: Text(_busy ? '…' : context.tr('fillMarked')),
                  onPressed: _busy ? null : _runRemove,
                ),
              ],
            ),
          ],
        );
      case 'enhance':
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          children: [
            Text(context.tr('enhanceBlurb')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              _action(_look == 'enhance' ? context.tr('enhanceOn') : context.tr('enhancePhoto'), () {
                setState(() => _look = _look == 'enhance' ? 'none' : 'enhance');
                _render();
              }),
            ]),
          ],
        );
      case 'more':
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('watermark')),
              value: _watermark,
              onChanged: (v) async {
                if (!v && !context.read<AppState>().isPro) {
                  await openPaywall(context, preferPro: true);
                  if (!mounted || !context.read<AppState>().isPro) return;
                }
                setState(() => _watermark = v);
                _render();
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _action(context.tr('cropRatio'), () => _openCrop()),
                _action(context.tr('rotateFlip'), () => _openCrop(rotate: true)),
                _action(context.tr('removeObject'), _openRemover),
                _action(context.tr('changeBg'), _removeBackground),
                _action(context.tr('makeGif'), _gif),
                _action(context.tr('addMusic'), _music),
                _action(context.tr('redEye'), _redEye),
                _action(context.tr('colorSplash'), () => setState(() => _splash = true)),
                _action(context.tr('doubleExposure'), _blend),
                _action(context.tr('passport'), _passport),
                _action('EXIF', _exif),
                _action(context.tr('batchCompress'), _batch),
                _action('${context.tr('frame')}: $_frame', () {
                  const frames = ['none', 'white', 'black', 'polaroid', 'vignette'];
                  final i = frames.indexOf(_frame);
                  setState(() => _frame = frames[(i + 1) % frames.length]);
                  _render();
                }),
                _action(_meme ? context.tr('memeOn') : context.tr('memeBars'), _toggleMeme),
              ],
            ),
          ],
        );
      default:
        return _adjustPanel();
    }
  }

  /// One adjustment at a time: pick it from the row, drag the slider.
  /// Nothing here is wider than the screen.
  Widget _adjustPanel() {
    final palette = context.palette;
    final a = _adjustments.firstWhere((x) => x.id == _adj);
    final value = _v(a.id).clamp(a.min, a.max);
    final span = a.max - a.min;
    final pct = ((value - a.neutral) / (span / 2) * 100).round();
    return Column(
      children: [
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _adjustments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final x = _adjustments[i];
              final sel = x.id == _adj;
              final changed = (_v(x.id) - x.neutral).abs() > 0.001;
              return GestureDetector(
                onTap: () => setState(() => _adj = x.id),
                child: SizedBox(
                  width: 66,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? AppColors.primary : palette.surface,
                          border: Border.all(
                              color: changed ? AppColors.primary : palette.border,
                              width: 1.5),
                        ),
                        child: Icon(x.icon,
                            size: 20, color: sel ? Colors.white : palette.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(context.tr(x.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(pct > 0 ? '+$pct' : '$pct',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: a.min,
                  max: a.max,
                  onChanged: (v) => setState(() => _values[a.id] = v),
                  onChangeEnd: (_) => _render(),
                ),
              ),
              IconButton(
                tooltip: 'Reset',
                onPressed: () {
                  setState(() => _values.remove(a.id));
                  _render();
                },
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _b(String id) =>
      _baked[id] ?? _adjustments.firstWhere((a) => a.id == id).neutral;

  /// Instant preview while a slider moves (the exact result is baked on
  /// release). Mirrors LocalEnhance._grade and only applies the change since
  /// the last bake, so nothing is applied twice.
  List<double> _previewMatrix() {
    double ratio(String id) {
      final b = _b(id);
      return b.abs() < 1e-3 ? 1.0 : _v(id) / b;
    }

    final c = ratio('contrast');
    final s = ratio('saturation') *
        (1 + 0.45 * _v('vibrance')) /
        (1 + 0.45 * _b('vibrance'));
    final gain = ratio('brightness') *
        (1 + 0.35 * _v('lightness')) /
        (1 + 0.35 * _b('lightness')) *
        math
            .pow(2, (_v('exposure') - _b('exposure')) +
                0.55 * (_v('highlight') - _b('highlight')))
            .toDouble();
    final k = c * gain;
    final pivot = 127.5 * (1 - c) * gain;
    final warm = (_v('warmth') - _b('warmth')) * 30;
    const lumR = 0.213, lumG = 0.715, lumB = 0.072;
    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;
    return <double>[
      (sr + s) * k, sg * k, sb * k, 0, pivot + warm,
      sr * k, (sg + s) * k, sb * k, 0, pivot,
      sr * k, sg * k, (sb + s) * k, 0, pivot - warm,
      0, 0, 0, 1, 0,
    ];
  }

  Widget _action(String label, VoidCallback onTap) {
    return ActionChip(label: Text(label), onPressed: _busy ? null : onTap);
  }
}

/// Owns its text fields until the route is gone, so Add does not dispose them mid-animation.
class _MemeBarsDialog extends StatefulWidget {
  const _MemeBarsDialog();

  @override
  State<_MemeBarsDialog> createState() => _MemeBarsDialogState();
}

class _MemeBarsDialogState extends State<_MemeBarsDialog> {
  final _top = TextEditingController();
  final _bottom = TextEditingController();

  @override
  void dispose() {
    _top.dispose();
    _bottom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(context.tr('memeBars')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _top,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: context.tr('topLine')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bottom,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: context.tr('bottomLine')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        TextButton(
          onPressed: () {
            final caption = '${_top.text.trim()}\n${_bottom.text.trim()}'.trim();
            Navigator.pop(context, caption);
          },
          child: Text(context.tr('add')),
        ),
      ],
    );
  }
}

