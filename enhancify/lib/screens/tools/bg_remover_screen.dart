import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../data/background_data.dart';
import '../../editor/color_picker.dart';
import '../../services/ai_background_service.dart';
import '../../services/bg_remover.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../export/export_screen.dart';

enum _BgKind { transparent, color, gradient, image }

enum _Panel { scenes, ai, colors, photo, layout, refine }

/// Canva-style background remover + background studio: the cut-out shows
/// right away, then the user drops the subject onto a scene (bundled
/// illustrations, AI-made photos, colors, gradients, their own photo),
/// moves / resizes it, adds a shadow, touches up edges and saves or shares.
class BgRemoverScreen extends StatefulWidget {
  const BgRemoverScreen({super.key, required this.photo});

  final Uint8List photo;

  static Future<void> open(BuildContext context, Uint8List photo) => Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'bg'),
        builder: (_) => BgRemoverScreen(photo: photo),
      ));

  @override
  State<BgRemoverScreen> createState() => _BgRemoverScreenState();
}

class _BgRemoverScreenState extends State<BgRemoverScreen> {
  BgCutout? _cut;
  ui.Image? _photoImg;
  ui.Image? _maskImg;
  String? _error;
  bool _busy = false;
  String? _busyLabel;

  // Background
  _BgKind _bg = _BgKind.transparent;
  Color _color = Colors.white;
  List<Color> _gradient = bgGradients.first.$2;
  ui.Image? _bgImg;
  String? _bgKey; // which image is loaded (asset path / file path / 'blur')
  double _bgBlur = 0; // 0..1
  String _category = bgSceneCategories.first;
  List<File> _aiSaved = const [];

  // Canvas + subject
  String _ratio = 'Original';
  Offset? _center; // fractions of the canvas; null = default placement
  double _scale = 1;
  double _rotation = 0;
  bool _flip = false;
  bool _shadow = true;

  // Gesture state
  Offset _startCenter = Offset.zero;
  double _startScale = 1, _startRotation = 0;
  bool _stroking = false;
  bool _multiTouch = false; // a pinch happened in this touch sequence

  // Refine
  _Panel _panel = _Panel.scenes;
  bool _keepBrush = false;
  double _brush = 0.03;
  final List<RefineStroke> _strokes = [];

  static const _colors = [
    Colors.white, Colors.black, Color(0xFFEA026A), Color(0xFFFFE3EF), Color(0xFFFF5C9E),
    Color(0xFFFFB547), Color(0xFFFFE38C), Color(0xFF2EC4A6), Color(0xFFA8E6B8), Color(0xFF8EC5F0),
    Color(0xFF3A7BD5), Color(0xFFB892FF), Color(0xFFE0354F), Color(0xFFF7E3C8), Color(0xFF9E9E9E),
  ];

  static const _ratios = ['Original', 'Background', '9:16', '4:5', '3:4', '1:1', '16:9'];

  @override
  void initState() {
    super.initState();
    _run();
    _loadSavedAi();
  }

  @override
  void dispose() {
    _photoImg?.dispose();
    _maskImg?.dispose();
    _bgImg?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- loading
  static Future<ui.Image> _decode(Uint8List b, {int? maxSide}) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(b);
    final desc = await ui.ImageDescriptor.encoded(buf);
    int? tw, th;
    if (maxSide != null && math.max(desc.width, desc.height) > maxSide) {
      final s = maxSide / math.max(desc.width, desc.height);
      tw = (desc.width * s).round();
      th = (desc.height * s).round();
    }
    final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
    final f = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buf.dispose();
    return f.image;
  }

  Future<void> _run() async {
    try {
      final cut = await BgRemover.cutout(widget.photo);
      final p = await _decode(cut.photo);
      final m = await _decode(cut.maskPng);
      if (!mounted) {
        p.dispose();
        m.dispose();
        return;
      }
      setState(() {
        _cut = cut;
        _photoImg = p;
        _maskImg = m;
      });
      showSnack(context, 'Background removed ✨ Now pick a new one below.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not remove the background from this photo.');
    }
  }

  Future<void> _loadSavedAi() async {
    final list = await AiBackgroundService.saved();
    if (mounted) setState(() => _aiSaved = list);
  }

  Future<void> _useImage(String key, Future<Uint8List> Function() bytes) async {
    if (_bgKey == key && _bgImg != null) {
      setState(() => _bg = _BgKind.image);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = null;
    });
    try {
      final im = await _decode(await bytes(), maxSide: 2048);
      if (!mounted) {
        im.dispose();
        return;
      }
      final old = _bgImg;
      setState(() {
        _bgImg = im;
        _bgKey = key;
        _bg = _BgKind.image;
        // Fit the canvas to the new scene and place the subject in it.
        _ratio = 'Background';
        _resetSubject();
      });
      old?.dispose();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open that background.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useScene(BgScene s) => _useImage(s.asset, () async {
        final data = await rootBundle.load(s.asset);
        return data.buffer.asUint8List();
      });

  Future<void> _useFile(File f) => _useImage(f.path, () => f.readAsBytes());

  Future<void> _pickPhoto() async {
    final f = await MediaService.pickImage();
    if (f == null) return;
    await _useFile(f);
  }

  Future<void> _useBlurredOriginal() async {
    final cut = _cut;
    if (cut == null) return;
    await _useImage('blur', () async => cut.photo);
    if (mounted) {
      setState(() {
        _bgBlur = math.max(_bgBlur, 0.6);
        _ratio = 'Original';
        _resetSubject();
      });
    }
  }

  Future<void> _generateAi(String prompt) async {
    setState(() {
      _busy = true;
      _busyLabel = 'Creating your background… (about 20 s)';
    });
    try {
      final aspect = _canvasAspect(forAi: true);
      final f = await AiBackgroundService.generate(prompt, aspect: aspect);
      if (!mounted) return;
      setState(() => _aiSaved = [f, ..._aiSaved]);
      await _useFile(f);
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error): '), ''));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _customPrompt() async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => const _PromptDialog(),
    );
    if (text == null || text.isEmpty || !mounted) return;
    await _generateAi('$text. Empty scene with open space for a person, no people, no text, photorealistic, '
        'vertical phone wallpaper.');
  }

  // --------------------------------------------------------------- canvas
  double get _photoAspect => _cut == null ? 1 : _cut!.width / _cut!.height;

  double _canvasAspect({bool forAi = false}) {
    switch (_ratio) {
      case '9:16':
        return 9 / 16;
      case '4:5':
        return 4 / 5;
      case '3:4':
        return 3 / 4;
      case '1:1':
        return 1;
      case '16:9':
        return 16 / 9;
      case 'Background':
        final b = _bgImg;
        if (b != null && !forAi) return b.width / b.height;
        return forAi ? 9 / 16 : _photoAspect;
      default:
        return forAi ? (_photoAspect < 1 ? 9 / 16 : _photoAspect) : _photoAspect;
    }
  }

  void _resetSubject() {
    _center = null;
    _scale = 1;
    _rotation = 0;
  }

  _Layout _layout(Size size) {
    // Base: subject fits inside the canvas (90%), standing on the bottom.
    final a = _photoAspect;
    var h = size.height * 0.9;
    var w = h * a;
    if (w > size.width * 0.96) {
      w = size.width * 0.96;
      h = w / a;
    }
    final c = _center ?? Offset(0.5, 1 - (h / 2) / size.height);
    return _Layout(Offset(c.dx * size.width, c.dy * size.height), w * _scale, h * _scale, _rotation, _flip);
  }

  /// Canvas point → fraction of the subject photo (for refine strokes).
  Offset _toSubject(Offset p, Size size) {
    final l = _layout(size);
    var d = p - l.center;
    final c = math.cos(-l.rotation), s = math.sin(-l.rotation);
    d = Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
    if (l.flip) d = Offset(-d.dx, d.dy);
    return Offset(((d.dx + l.w / 2) / l.w).clamp(0.0, 1.0), ((d.dy + l.h / 2) / l.h).clamp(0.0, 1.0));
  }

  void _onScaleStart(ScaleStartDetails d, Size size) {
    _startCenter = _center ?? (_layout(size).center.scale(1 / size.width, 1 / size.height));
    _startScale = _scale;
    _startRotation = _rotation;
    // The recognizer restarts (onEnd + onStart) whenever a finger is added or
    // lifted. A second finger turns a just-started stroke into a pinch, and
    // the finger left after a pinch must not start painting.
    if (d.pointerCount > 1) {
      if (_stroking && _strokes.isNotEmpty && _strokes.last.points.length < 4) {
        setState(_strokes.removeLast);
      }
      _multiTouch = true;
    }
    _stroking = false;
    if (_panel == _Panel.refine && d.pointerCount == 1 && !_multiTouch) {
      _stroking = true;
      setState(() => _strokes.add(RefineStroke(
            keep: _keepBrush,
            width: _brush / math.max(0.2, _scale),
            points: [_toSubject(d.localFocalPoint, size)],
          )));
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_stroking && d.pointerCount == 1) {
      setState(() => _strokes.last.points.add(_toSubject(d.localFocalPoint, size)));
      return;
    }
    if (_stroking && d.pointerCount > 1) {
      // A second finger arrived: this is a pinch, not a brush stroke.
      _stroking = false;
      if (_strokes.isNotEmpty && _strokes.last.points.length < 4) _strokes.removeLast();
    }
    setState(() {
      _startCenter += Offset(d.focalPointDelta.dx / size.width, d.focalPointDelta.dy / size.height);
      _center = Offset(_startCenter.dx.clamp(-0.2, 1.2), _startCenter.dy.clamp(-0.2, 1.4));
      if (d.pointerCount > 1) {
        _scale = (_startScale * d.scale).clamp(0.2, 4.0);
        _rotation = _startRotation + d.rotation;
      }
    });
  }

  _ScenePainter _painter({required bool preview}) => _ScenePainter(
        photo: _photoImg!,
        mask: _maskImg!,
        strokes: _strokes,
        strokeSig: _strokes.fold(_strokes.length, (a, s) => a * 31 + s.points.length),
        bg: _bg,
        color: _color,
        gradient: _gradient,
        bgImage: _bg == _BgKind.image ? _bgImg : null,
        bgBlur: _bgBlur,
        layout: _layout,
        shadow: _shadow,
        preview: preview,
        ghost: preview && _panel == _Panel.refine,
      );

  // --------------------------------------------------------------- export
  Future<void> _done() async {
    if (_cut == null) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Saving…';
    });
    try {
      final aspect = _canvasAspect();
      const long = 2048.0;
      final size = aspect >= 1 ? Size(long, long / aspect) : Size(long * aspect, long);
      final w = size.width.round(), h = size.height.round();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      _painter(preview: false).paint(canvas, Size(w.toDouble(), h.toDouble()));
      final pic = rec.endRecording();
      final image = await pic.toImage(w, h);
      pic.dispose();
      late Uint8List bytes;
      late String ext;
      if (_bg == _BgKind.transparent) {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data!.buffer.asUint8List();
        ext = 'png';
      } else {
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final rgba = raw!.buffer.asUint8List();
        bytes = await _jpegAsync(rgba, w, h);
        ext = 'jpg';
      }
      image.dispose();
      final file = File('${Directory.systemTemp.path}/cutout_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() => _busy = false);
      await ExportScreen.open(context, file, title: 'New background');
    } catch (_) {
      if (mounted) showSnack(context, 'Could not save the picture.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  // ------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ready = _cut != null && _photoImg != null && _maskImg != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background'),
        actions: [
          if (_panel == _Panel.refine)
            IconButton(
              tooltip: 'Undo',
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
              icon: const Icon(Icons.undo),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: !ready || _busy ? null : _done,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(child: ready ? _stage() : _loading()),
              ),
            ),
            if (_busy)
              Column(
                children: [
                  const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
                  if (_busyLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_busyLabel!, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                    ),
                ],
              ),
            if (ready) ...[
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: [
                    _tab(_Panel.scenes, Icons.auto_awesome_mosaic, 'Scenes'),
                    _tab(_Panel.ai, Icons.auto_awesome, 'AI'),
                    _tab(_Panel.colors, Icons.palette_outlined, 'Colors'),
                    _tab(_Panel.photo, Icons.image_outlined, 'Photo & blur'),
                    _tab(_Panel.layout, Icons.aspect_ratio, 'Layout'),
                    _tab(_Panel.refine, Icons.brush, 'Refine'),
                  ],
                ),
              ),
              SizedBox(height: 150, child: _panelBody(palette)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tab(_Panel p, IconData icon, String label) {
    final sel = _panel == p;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16, color: sel ? Colors.white : AppColors.primary),
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(color: sel ? Colors.white : context.palette.textPrimary, fontWeight: FontWeight.w600),
        onSelected: (_) => setState(() => _panel = p),
      ),
    );
  }

  Widget _loading() {
    if (_error != null) return Text(_error!, textAlign: TextAlign.center);
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.5, child: Image.memory(widget.photo, fit: BoxFit.contain)),
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 12),
            Text('Removing background…', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  Widget _stage() {
    return AspectRatio(
      aspectRatio: _canvasAspect(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) => _onScaleStart(d, size),
            onScaleUpdate: (d) => _onScaleUpdate(d, size),
            onScaleEnd: (d) {
              // pointerCount = fingers still down; > 0 means onScaleStart
              // follows right away with the new finger set.
              if (d.pointerCount == 0) {
                _stroking = false;
                _multiTouch = false;
              }
            },
            onDoubleTap: () => setState(_resetSubject),
            child: CustomPaint(size: size, painter: _painter(preview: true)),
          );
        }),
      ),
    );
  }

  Widget _panelBody(AppPalette palette) {
    switch (_panel) {
      case _Panel.scenes:
        return _scenesPanel(palette);
      case _Panel.ai:
        return _aiPanel(palette);
      case _Panel.colors:
        return _colorsPanel(palette);
      case _Panel.photo:
        return _photoPanel(palette);
      case _Panel.layout:
        return _layoutPanel(palette);
      case _Panel.refine:
        return _refinePanel(palette);
    }
  }

  Widget _thumb({
    required Widget child,
    required bool selected,
    required VoidCallback onTap,
    String? label,
    double w = 64,
    double h = 96,
  }) {
    final palette = context.palette;
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 3 : 1),
              ),
              child: child,
            ),
            if (label != null)
              SizedBox(
                width: w + 8,
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scenesPanel(AppPalette palette) {
    final scenes = bgScenes.where((s) => s.category == _category).toList();
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final c in bgSceneCategories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    selected: _category == c,
                    showCheckmark: false,
                    selectedColor: AppColors.blush,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            children: [
              for (final s in scenes)
                _thumb(
                  label: s.label,
                  h: 84,
                  w: 48,
                  selected: _bg == _BgKind.image && _bgKey == s.asset,
                  onTap: () => _useScene(s),
                  child: Image.asset(s.asset, fit: BoxFit.cover, cacheWidth: 160),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiPanel(AppPalette palette) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      children: [
        _thumb(
          label: 'Describe',
          selected: false,
          onTap: _customPrompt,
          child: const Icon(Icons.edit_note, color: AppColors.primary, size: 30),
        ),
        for (final f in _aiSaved)
          _thumb(
            label: 'Saved',
            selected: _bg == _BgKind.image && _bgKey == f.path,
            onTap: () => _useFile(f),
            child: Image.file(f, fit: BoxFit.cover, cacheWidth: 160),
          ),
        for (final t in aiBgThemes)
          _thumb(
            label: t.label,
            selected: false,
            onTap: () => _generateAi(t.prompt),
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: AppColors.blushGradient),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.icon, color: AppColors.primary),
                  const SizedBox(height: 4),
                  const Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _colorsPanel(AppPalette palette) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
      children: [
        _thumb(
          label: 'None',
          w: 52,
          h: 52,
          selected: _bg == _BgKind.transparent,
          onTap: () => setState(() => _bg = _BgKind.transparent),
          child: CustomPaint(painter: _CheckerPainter()),
        ),
        _thumb(
          label: 'Custom',
          w: 52,
          h: 52,
          selected: false,
          onTap: () async {
            final c = await showColorPickerSheet(context, _color);
            if (c != null && mounted) {
              setState(() {
                _color = c;
                _bg = _BgKind.color;
              });
            }
          },
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: SweepGradient(colors: [
                Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
                Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
              ]),
            ),
            child: Icon(Icons.colorize, color: Colors.white),
          ),
        ),
        for (final (name, cs) in bgGradients)
          _thumb(
            label: name,
            w: 52,
            h: 52,
            selected: _bg == _BgKind.gradient && identical(_gradient, cs),
            onTap: () => setState(() {
              _gradient = cs;
              _bg = _BgKind.gradient;
            }),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: cs),
              ),
            ),
          ),
        for (final c in _colors)
          _thumb(
            label: '',
            w: 52,
            h: 52,
            selected: _bg == _BgKind.color && _color.toARGB32() == c.toARGB32(),
            onTap: () => setState(() {
              _color = c;
              _bg = _BgKind.color;
            }),
            child: ColoredBox(color: c),
          ),
      ],
    );
  }

  Widget _photoPanel(AppPalette palette) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('My photo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _useBlurredOriginal,
                icon: const Icon(Icons.blur_on),
                label: const Text('Blur original'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 92, child: Text('Background blur', style: TextStyle(fontSize: 12, color: palette.textSecondary))),
            Expanded(
              child: Slider(
                value: _bgBlur,
                activeColor: AppColors.primary,
                onChanged: _bg == _BgKind.image ? (v) => setState(() => _bgBlur = v) : null,
              ),
            ),
          ],
        ),
        Text('Blur works on scenes, AI and photo backgrounds (portrait look).',
            style: TextStyle(fontSize: 11, color: palette.textMuted)),
      ],
    );
  }

  Widget _layoutPanel(AppPalette palette) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final r in _ratios)
                if (r != 'Background' || _bg == _BgKind.image)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(r == 'Background' ? 'Fit scene' : r),
                      selected: _ratio == r,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(color: _ratio == r ? Colors.white : palette.textPrimary),
                      onSelected: (_) => setState(() {
                        _ratio = r;
                        _resetSubject();
                      }),
                    ),
                  ),
            ],
          ),
        ),
        Row(
          children: [
            SizedBox(width: 46, child: Text('Size', style: TextStyle(fontSize: 12, color: palette.textSecondary))),
            Expanded(
              child: Slider(
                value: _scale.clamp(0.2, 2.5),
                min: 0.2,
                max: 2.5,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _scale = v),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              avatar: const Icon(Icons.contrast, size: 16),
              label: const Text('Shadow'),
              selected: _shadow,
              onSelected: (v) => setState(() => _shadow = v),
            ),
            ActionChip(
              avatar: const Icon(Icons.flip, size: 16),
              label: const Text('Flip'),
              onPressed: () => setState(() => _flip = !_flip),
            ),
            ActionChip(
              avatar: const Icon(Icons.center_focus_strong, size: 16),
              label: const Text('Reset'),
              onPressed: () => setState(() {
                _resetSubject();
                _flip = false;
              }),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Drag to move · pinch to resize or turn · double-tap to reset',
              style: TextStyle(fontSize: 11, color: palette.textMuted)),
        ),
      ],
    );
  }

  Widget _refinePanel(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              ChoiceChip(
                avatar: Icon(Icons.auto_fix_off, size: 16, color: !_keepBrush ? Colors.white : AppColors.primary),
                label: const Text('Erase'),
                selected: !_keepBrush,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(color: !_keepBrush ? Colors.white : palette.textPrimary),
                onSelected: (_) => setState(() => _keepBrush = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: Icon(Icons.brush, size: 16, color: _keepBrush ? Colors.white : AppColors.primary),
                label: const Text('Restore'),
                selected: _keepBrush,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(color: _keepBrush ? Colors.white : palette.textPrimary),
                onSelected: (_) => setState(() => _keepBrush = true),
              ),
              const Spacer(),
              TextButton(
                onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
                child: const Text('Reset'),
              ),
            ],
          ),
          Row(
            children: [
              Text('Size', style: TextStyle(color: palette.textSecondary)),
              Expanded(
                child: Slider(
                  value: _brush,
                  min: 0.008,
                  max: 0.08,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _brush = v),
                ),
              ),
            ],
          ),
          Text('Paint with one finger · pinch with two to zoom the subject',
              style: TextStyle(fontSize: 11, color: palette.textMuted)),
        ],
      ),
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog();

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Describe a background'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'e.g. a cozy café with fairy lights and plants'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Top level so the isolate closure can't capture the State object.
Future<Uint8List> _jpegAsync(Uint8List rgba, int w, int h) => Isolate.run(() => _jpeg(rgba, w, h));

Uint8List _jpeg(Uint8List rgba, int w, int h) {
  final im = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, bytesOffset: rgba.offsetInBytes, numChannels: 4, order: img.ChannelOrder.rgba);
  return img.encodeJpg(im.convert(numChannels: 3), quality: 93);
}

/// Where the subject sits on the canvas (canvas pixels).
class _Layout {
  const _Layout(this.center, this.w, this.h, this.rotation, this.flip);
  final Offset center;
  final double w;
  final double h;
  final double rotation;
  final bool flip;
}

/// Background + (shadow) + subject (photo × mask × refine strokes).
/// Resolution independent, so the same painter renders the preview and the
/// 2048 px export.
class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.photo,
    required this.mask,
    required this.strokes,
    required this.strokeSig,
    required this.bg,
    required this.color,
    required this.gradient,
    required this.bgImage,
    required this.bgBlur,
    required this.layout,
    required this.shadow,
    required this.preview,
    required this.ghost,
  });

  final ui.Image photo;
  final ui.Image mask;
  final List<RefineStroke> strokes;
  final int strokeSig;
  final _BgKind bg;
  final Color color;
  final List<Color> gradient;
  final ui.Image? bgImage;
  final double bgBlur;
  final _Layout Function(Size) layout;
  final bool shadow;
  final bool preview;
  final bool ghost;

  static const _lumaToAlpha = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    1, 0, 0, 0, 0, //
  ]);

  static const _lumaToShadow = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0.42, 0, 0, 0, 0, //
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    // ---- background
    switch (bg) {
      case _BgKind.transparent:
        if (preview) _CheckerPainter().paint(canvas, size);
      case _BgKind.color:
        canvas.drawRect(dst, Paint()..color = color);
      case _BgKind.gradient:
        canvas.drawRect(
          dst,
          Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), gradient),
        );
      case _BgKind.image:
        final b = bgImage;
        if (b != null) {
          // Cover-fit.
          final s = math.max(size.width / b.width, size.height / b.height);
          final sw = size.width / s, sh = size.height / s;
          final src = Rect.fromLTWH((b.width - sw) / 2, (b.height - sh) / 2, sw, sh);
          final sigma = bgBlur * size.shortestSide * 0.025;
          final p = Paint()..filterQuality = FilterQuality.medium;
          if (sigma > 0.3) {
            canvas.saveLayer(dst, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
            canvas.drawImageRect(b, src, dst.inflate(sigma * 2), p);
            canvas.restore();
          } else {
            canvas.drawImageRect(b, src, dst, p);
          }
        }
    }

    // ---- subject
    final l = layout(size);
    final rect = Rect.fromCenter(center: Offset.zero, width: l.w, height: l.h);
    final maskSrc = Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble());
    final photoSrc = Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble());
    canvas.save();
    canvas.translate(l.center.dx, l.center.dy);
    canvas.rotate(l.rotation);
    if (l.flip) canvas.scale(-1, 1);

    if (shadow && bg != _BgKind.transparent) {
      final sig = l.w * 0.025;
      canvas.saveLayer(rect.inflate(sig * 4).shift(Offset(l.w * 0.03, l.h * 0.015)),
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sig, sigmaY: sig));
      canvas.drawImageRect(mask, maskSrc, rect.shift(Offset(l.w * 0.03, l.h * 0.015)),
          Paint()..colorFilter = _lumaToShadow);
      canvas.restore();
    }

    canvas.saveLayer(rect, Paint());
    canvas.drawImageRect(mask, maskSrc, rect, Paint()
      ..colorFilter = _lumaToAlpha
      ..filterQuality = FilterQuality.medium);
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final w = l.w * s.width * 2;
      final paint = Paint()
        ..color = Colors.white
        ..blendMode = s.keep ? BlendMode.srcOver : BlendMode.clear
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final pts = [for (final p in s.points) Offset(rect.left + p.dx * l.w, rect.top + p.dy * l.h)];
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, w / 2, paint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(Path()..addPolygon(pts, false), paint);
      }
    }
    canvas.drawImageRect(photo, photoSrc, rect, Paint()
      ..blendMode = BlendMode.srcIn
      ..filterQuality = FilterQuality.medium);
    canvas.restore();
    if (ghost) {
      canvas.drawImageRect(photo, photoSrc, rect, Paint()..color = const Color(0x2E000000));
    }
    canvas.restore();
  }

  // The layout is a closure over live state, so always repaint (cheap).
  @override
  bool shouldRepaint(covariant _ScenePainter o) => true;
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()..color = const Color(0xFFE6E6E6);
    const c = 12.0;
    for (var y = 0.0; y < size.height; y += c) {
      for (var x = ((y / c).floor().isOdd ? c : 0.0); x < size.width; x += c * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, c, c), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
