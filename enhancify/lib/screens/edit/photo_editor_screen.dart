import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/object_remover.dart';
import '../../services/local_enhance.dart';
import '../../services/media_service.dart';
import '../../widgets/common.dart';
import 'makeup_panel.dart';

/// On-device editor. Every tool below runs on the phone.
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.file, this.tool = 'enhance'});

  final File file;
  final String tool;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _engine = LocalEnhance();
  final _text = TextEditingController();
  final _previewKey = GlobalKey();
  Uint8List? _original;
  Uint8List? _preview;
  String _look = 'none';
  String _filter = 'none';
  String _sticker = '';
  String _crop = 'free';
  String _panel = 'adjust';
  int _turns = 0;
  bool _watermark = false;
  bool _busy = false;
  String? _error;

  double _brightness = 1;
  double _contrast = 1;
  double _exposure = 0;
  double _lightness = 0;
  double _highlight = 0;
  double _saturation = 1;
  double _vibrance = 0;
  double _tint = 0;
  double _fade = 0;
  double _grain = 0;
  double _warmth = 0;
  String _frame = 'none';
  bool _meme = false;
  bool _splash = false;
  String _collageLayout = 'grid';
  final List<Uint8List> _history = [];
  final List<Uint8List> _future = [];
  final List<List<Offset>> _strokes = [];
  final List<List<Offset>> _mask = [];
  double _brush = 0.035;
  bool _telea = true;

  static const _filters = ['none', 'vivid', 'warm', 'cool', 'bw', 'sepia', 'vintage', 'noir', 'pencil', 'cartoon'];
  static const _avatars = ['avatar3d', 'pixel', 'clay', 'sketch'];

  @override
  void initState() {
    super.initState();
    if (widget.tool == 'restore') _look = 'restore';
    if (widget.tool == 'enhance') _look = 'enhance';
    if (widget.tool == 'crop') _crop = 'square';
    if (widget.tool == 'rotate') _turns = 1;
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      if (!mounted) return;
      setState(() => _original = Uint8List.fromList(bytes));
      await _render();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this photo.');
    }
  }

  (double, double, double, double) get _cropBox {
    switch (_crop) {
      case 'square':
        return (0.12, 0.12, 0.88, 0.88);
      case 'story':
        return (0.18, 0.02, 0.82, 0.98);
      default:
        return (0, 0, 1, 1);
    }
  }

  Future<void> _render() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    final box = _cropBox;
    final bytes = _engine.bake(
      src,
      look: _look,
      brightness: _brightness,
      contrast: _contrast,
      exposure: _exposure,
      lightness: _lightness,
      highlight: _highlight,
      saturation: _saturation,
      vibrance: _vibrance,
      tint: _tint,
      fade: _fade,
      grain: _grain,
      warmth: _warmth,
      filter: _filter,
      frame: _frame,
      meme: _meme,
      text: _text.text,
      sticker: _sticker,
      watermark: _watermark,
      quarterTurns: _turns,
      cropLeft: box.$1,
      cropTop: box.$2,
      cropRight: box.$3,
      cropBottom: box.$4,
    );
    if (!mounted) return;
    setState(() {
      _preview = Uint8List.fromList(bytes);
      _busy = false;
    });
  }

  Future<File> _write(List<int> bytes, String ext) async {
    final out = File('${widget.file.parent.path}/edit_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  Future<void> _save() async {
    if (_strokes.isNotEmpty) {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final shot = await boundary.toImage(pixelRatio: 2);
        final data = await shot.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) {
          final file = await _write(data.buffer.asUint8List(), 'png');
          final err = await MediaService.saveToGallery(file);
          if (!mounted) return;
          showSnack(context, err ?? 'Saved with your drawing.');
          return;
        }
      }
    }
    final bytes = _preview;
    if (bytes == null) return;
    final file = await _write(bytes, 'jpg');
    final err = await MediaService.saveToGallery(file);
    if (!mounted) return;
    showSnack(context, err ?? 'Saved to your gallery.');
  }

  Future<void> _savePng(List<int> bytes, String ok) async {
    final file = await _write(bytes, 'png');
    final err = await MediaService.saveToGallery(file);
    if (!mounted) return;
    showSnack(context, err ?? ok);
  }

  Future<void> _removeBackground() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      final png = _engine.removeBackground(src);
      await _savePng(png, 'Sticker saved. Plain backgrounds work best.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gif() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      final gif = _engine.makeGif(src);
      final file = await _write(gif, 'gif');
      final err = await MediaService.saveToGallery(file);
      if (mounted) showSnack(context, err ?? 'GIF saved to your gallery.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    _strokes.clear();
  }

  Offset _photoPoint(Offset local) {
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width == 0 || box.size.height == 0) {
      return Offset.zero;
    }
    return Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
  }

  Future<void> _runRemove() async {
    final src = _preview ?? _original;
    if (src == null || _mask.isEmpty) {
      showSnack(context, 'Paint over the object you want to remove.');
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    try {
      final bytes = await removePaintedObject(
        src,
        _mask,
        brushFraction: _brush,
        telea: _telea,
      );
      _mask.clear();
      _replaceOriginal(bytes);
      await _render();
      if (mounted) showSnack(context, _telea ? 'Removed with Telea.' : 'Removed with Navier-Stokes.');
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

  Future<void> _splashAt(Offset local, Offset _) async {
    final src = _original;
    final box = context.findRenderObject() as RenderBox?;
    if (src == null || box == null) return;
    final fx = (local.dx / box.size.width).clamp(0.0, 1.0);
    final fy = (local.dy / box.size.height).clamp(0.0, 1.0);
    final color = _engine.sampleColor(src, fx, fy);
    setState(() {
      _busy = true;
      _splash = false;
    });
    try {
      _replaceOriginal(_engine.colorSplash(src, r: color.$1, g: color.$2, b: color.$3));
      await _render();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _redEye() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      _replaceOriginal(_engine.redEye(src));
      await _render();
      if (mounted) showSnack(context, 'Red-eye reduced in the eye area.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
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
    }
  }

  Future<void> _passport() async {
    final src = _original;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      final jpg = _engine.passport(src);
      final file = await _write(jpg, 'jpg');
      final err = await MediaService.saveToGallery(file);
      if (mounted) showSnack(context, err ?? 'Passport photo saved.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exif() async {
    final src = _original;
    if (src == null) return;
    final tags = _engine.readExif(src);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Photo details'),
        content: SizedBox(
          width: 320,
          child: tags.isEmpty
              ? const Text('No EXIF metadata on this photo.')
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
            child: const Text('Strip metadata'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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

  Future<void> _collage() async {
    final more = await MediaService.pickImages(limit: 5);
    if (more.isEmpty || _original == null) return;
    setState(() => _busy = true);
    try {
      final parts = <List<int>>[_original!];
      for (final f in more) {
        parts.add(await f.readAsBytes());
      }
      final jpg = _engine.collage(parts, layout: _collageLayout);
      final file = await _write(jpg, 'jpg');
      final err = await MediaService.saveToGallery(file);
      if (mounted) showSnack(context, err ?? 'Collage saved.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit photo'),
        actions: [
          IconButton(onPressed: _history.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(onPressed: _future.isEmpty ? null : _redo, icon: const Icon(Icons.redo)),
          TextButton(onPressed: preview == null || _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: preview == null
                  ? Text(_error ?? 'Opening photo...')
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: RepaintBoundary(
                        key: _previewKey,
                        child: GestureDetector(
                        onTapDown: _splash ? (d) => _splashAt(d.localPosition, d.localPosition) : null,
                        onPanStart: _panel == 'draw'
                            ? (d) => setState(() => _strokes.add([d.localPosition]))
                            : _panel == 'object'
                                ? (d) => setState(() => _mask.add([_photoPoint(d.localPosition)]))
                                : null,
                        onPanUpdate: _panel == 'draw'
                            ? (d) => setState(() => _strokes.last.add(d.localPosition))
                            : _panel == 'object'
                                ? (d) => setState(() => _mask.last.add(_photoPoint(d.localPosition)))
                                : null,
                        child: Stack(
                          children: [
                            Image.memory(preview, fit: BoxFit.contain),
                            Positioned.fill(
                              child: CustomPaint(painter: _DoodlePainter(_strokes)),
                            ),
                            if (_panel == 'object')
                              Positioned.fill(
                                child: CustomPaint(painter: _MaskPainter(_mask, _brush)),
                              ),
                          ],
                        ),
                        ),
                      ),
                    ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _tab('Adjust', 'adjust'),
                _tab('Filter', 'filter'),
                _tab('Avatar', 'avatar'),
                _tab('Text', 'text'),
                _tab('Sticker', 'sticker'),
                _tab('Draw', 'draw'),
                _tab('Makeup', 'makeup'),
                _tab('Object', 'object'),
                _tab('More', 'more'),
              ],
            ),
          ),
          SizedBox(height: _panel == 'makeup' ? 250 : 210, child: _panelBody()),
        ],
      ),
    );
  }

  Widget _tab(String label, String id) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: _panel == id,
        onSelected: (_) => setState(() => _panel = id),
      ),
    );
  }

  Widget _panelBody() {
    switch (_panel) {
      case 'filter':
        return _chips(_filters, _filter, (v) {
          setState(() => _filter = v);
          _render();
        });
      case 'avatar':
        return _chips(['none', ..._avatars], _filter, (v) {
          setState(() => _filter = v);
          _render();
        });
      case 'text':
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(hintText: 'Type text to put on the photo'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _render, child: const Text('Add')),
            ],
          ),
        );
      case 'sticker':
        return _chips(const ['', 'STAR', 'HEART', 'WOW', 'COOL', 'LOVE', 'YES', 'OK'], _sticker, (v) {
          setState(() => _sticker = v);
          _render();
        });
      case 'object':
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('Paint over a small object on a simple background, then tap Remove.'),
            ),
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
              children: [
                ChoiceChip(
                  label: const Text('Telea'),
                  selected: _telea,
                  onSelected: (_) => setState(() => _telea = true),
                ),
                ChoiceChip(
                  label: const Text('Navier-Stokes'),
                  selected: !_telea,
                  onSelected: (_) => setState(() => _telea = false),
                ),
                ActionChip(
                  label: const Text('Clear mask'),
                  onPressed: () => setState(() => _mask.clear()),
                ),
                ActionChip(
                  label: Text(_busy ? 'Removing...' : 'Remove'),
                  onPressed: _busy ? null : _runRemove,
                ),
              ],
            ),
          ],
        );
      case 'makeup':
        final photo = _original;
        if (photo == null) return const SizedBox.shrink();
        return MakeupPanel(
          photo: photo,
          onPreview: (bytes) => setState(() => _preview = bytes),
          onApply: (bytes) {
            _replaceOriginal(bytes);
            _render();
          },
        );
      case 'draw':
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Draw on the photo with your finger. Undo removes the last baked edit, not each stroke, until you save.'),
        );
      case 'more':
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            SwitchListTile(
              title: const Text('Watermark'),
              value: _watermark,
              onChanged: (v) {
                setState(() => _watermark = v);
                _render();
              },
            ),
            Wrap(
              spacing: 8,
              children: [
                _action('Enhance', () {
                  setState(() => _look = _look == 'enhance' ? 'none' : 'enhance');
                  _render();
                }),
                _action('Restore', () {
                  setState(() => _look = _look == 'restore' ? 'none' : 'restore');
                  _render();
                }),
                _action(_crop == 'free' ? 'Crop' : _crop, () {
                  setState(() => _crop = _crop == 'free' ? 'square' : (_crop == 'square' ? 'story' : 'free'));
                  _render();
                }),
                _action('Rotate', () {
                  setState(() => _turns += 1);
                  _render();
                }),
                _action('Remove background', _removeBackground),
                _action('Make GIF', _gif),
                _action('Collage', _collage),
                _action('Red-eye', _redEye),
                _action('Color splash', () => setState(() => _splash = true)),
                _action('Double exposure', _blend),
                _action('Passport photo', _passport),
                _action('EXIF', _exif),
                _action('Batch compress', _batch),
                _action('Save sticker', _removeBackground),
                _action(_frame, () {
                  const frames = ['none', 'white', 'black', 'polaroid', 'vignette'];
                  final i = frames.indexOf(_frame);
                  setState(() => _frame = frames[(i + 1) % frames.length]);
                  _render();
                }),
                _action(_collageLayout, () {
                  const layouts = ['grid', 'mosaic', 'polaroid', 'story'];
                  final i = layouts.indexOf(_collageLayout);
                  setState(() => _collageLayout = layouts[(i + 1) % layouts.length]);
                }),
                _action(_meme ? 'Meme on' : 'Meme bars', () {
                  setState(() => _meme = !_meme);
                  _render();
                }),
              ],
            ),
          ],
        );
      default:
        return ListView(
          children: [
            _slider('Exposure', _exposure, -1, 1, (v) => _exposure = v),
            _slider('Brightness', _brightness, 0.6, 1.5, (v) => _brightness = v),
            _slider('Contrast', _contrast, 0.6, 1.6, (v) => _contrast = v),
            _slider('Lightness', _lightness, -0.6, 0.6, (v) => _lightness = v),
            _slider('Highlight', _highlight, -0.6, 0.8, (v) => _highlight = v),
            _slider('Saturation', _saturation, 0, 2, (v) => _saturation = v),
            _slider('Vibrance', _vibrance, -0.8, 0.8, (v) => _vibrance = v),
            _slider('Tint', _tint, -40, 40, (v) => _tint = v),
            _slider('Fade', _fade, 0, 1, (v) => _fade = v),
            _slider('Grain', _grain, 0, 30, (v) => _grain = v),
            _slider('Warmth', _warmth, -1, 1, (v) => _warmth = v),
          ],
        );
    }
  }

  Widget _slider(String label, double value, double min, double max, void Function(double) set) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => setState(() => set(v)),
            onChangeEnd: (_) => _render(),
          ),
        ),
      ],
    );
  }

  Widget _chips(List<String> values, String selected, void Function(String) onPick) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      children: [
        for (final v in values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(v.isEmpty ? 'None' : v),
              selected: selected == v,
              onSelected: (_) => onPick(v),
            ),
          ),
      ],
    );
  }

  Widget _action(String label, VoidCallback onTap) {
    return ActionChip(label: Text(label), onPressed: _busy ? null : onTap);
  }
}

class _MaskPainter extends CustomPainter {
  _MaskPainter(this.strokes, this.brush);
  final List<List<Offset>> strokes;
  final double brush;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x88E8274B);
    final strokePaint = Paint()
      ..color = const Color(0x88E8274B)
      ..strokeWidth = size.width * brush * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final radius = size.width * brush;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        final p = stroke.first;
        canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), radius, fill);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) => true;
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8274B)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter oldDelegate) => true;
}
