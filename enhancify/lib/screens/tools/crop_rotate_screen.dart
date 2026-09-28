import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Crop with aspect-ratio presets, rotate 90° left/right, flip, and
/// straighten by any angle (slider or two-finger twist). Returns the new
/// photo bytes, or null if cancelled.
class CropRotateScreen extends StatefulWidget {
  const CropRotateScreen({super.key, required this.photo, this.startOnRotate = false});

  final Uint8List photo;
  final bool startOnRotate;

  static Future<Uint8List?> open(BuildContext context, Uint8List photo, {bool rotate = false}) =>
      Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => CropRotateScreen(photo: photo, startOnRotate: rotate)),
      );

  @override
  State<CropRotateScreen> createState() => _CropRotateScreenState();
}

class _Ratio {
  const _Ratio(this.label, this.value, this.icon);
  final String label;

  /// width / height; 0 = free, -1 = original.
  final double value;
  final IconData icon;
}

enum _Drag { none, move, tl, tr, bl, br, l, r, t, b }

class _CropRotateScreenState extends State<CropRotateScreen> {
  static const _ratios = [
    _Ratio('Free', 0, Icons.crop_free),
    _Ratio('Original', -1, Icons.crop_original),
    _Ratio('1:1', 1, Icons.crop_square),
    _Ratio('4:5', 4 / 5, Icons.crop_portrait),
    _Ratio('3:4', 3 / 4, Icons.crop_portrait),
    _Ratio('2:3', 2 / 3, Icons.crop_portrait),
    _Ratio('9:16', 9 / 16, Icons.smartphone),
    _Ratio('16:9', 16 / 9, Icons.crop_landscape),
    _Ratio('4:3', 4 / 3, Icons.crop_landscape),
    _Ratio('3:2', 3 / 2, Icons.crop_landscape),
    _Ratio('5:4', 5 / 4, Icons.crop_landscape),
  ];

  int _imgW = 1, _imgH = 1;
  bool _ready = false;
  bool _busy = false;
  late bool _rotateTab = widget.startOnRotate;

  int _turns = 0; // clockwise quarter turns
  bool _flipX = false, _flipY = false;
  double _angle = 0; // degrees, clockwise

  _Ratio _ratio = _ratios.first;
  Rect _box = const Rect.fromLTRB(0, 0, 1, 1); // fractions of the frame

  _Drag _drag = _Drag.none;
  double _angleAtStart = 0;
  Size _frame = Size.zero;

  @override
  void initState() {
    super.initState();
    _readSize();
  }

  late Uint8List _photo = widget.photo;

  /// Reads the size, and bakes any EXIF rotation into the pixels so the
  /// preview and the export always agree.
  Future<void> _readSize() async {
    try {
      final src = widget.photo;
      final r = await _uprightAsync(src);
      if (r != null) {
        _photo = r.$1;
        _imgW = r.$2;
        _imgH = r.$3;
      }
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  /// Width / height of the photo after the quarter turns.
  double get _baseAspect => _turns.isOdd ? _imgH / _imgW : _imgW / _imgH;

  double get _rad => _angle * math.pi / 180;

  /// Zoom needed so the rotated photo still covers the whole frame.
  double get _cover {
    final a = _baseAspect;
    final c = math.cos(_rad).abs(), s = math.sin(_rad).abs();
    return math.max(c + s / a, c + s * a);
  }

  void _applyRatio(_Ratio r) {
    setState(() {
      _ratio = r;
      _box = _fitBox(_ratioValue);
    });
  }

  double get _ratioValue => _ratio.value == -1 ? _baseAspect : _ratio.value;

  /// Largest centered box with [ratio] (0 = whole frame).
  Rect _fitBox(double ratio) {
    if (ratio <= 0) return const Rect.fromLTRB(0, 0, 1, 1);
    // In frame fractions: width_frac / height_frac = ratio / baseAspect.
    final rel = ratio / _baseAspect;
    double w = 1, h = 1;
    if (rel > 1) {
      h = 1 / rel;
    } else {
      w = rel;
    }
    return Rect.fromCenter(center: const Offset(0.5, 0.5), width: w * 0.94, height: h * 0.94);
  }

  void _turn(int dir) {
    setState(() {
      _turns = (_turns + dir) % 4;
      if (_turns < 0) _turns += 4;
      _box = _fitBox(_ratio.value == 0 ? 0 : _ratioValue);
    });
  }

  void _reset() {
    setState(() {
      _turns = 0;
      _flipX = _flipY = false;
      _angle = 0;
      _ratio = _ratios.first;
      _box = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  // --------------------------------------------------------- gestures
  void _onScaleStart(ScaleStartDetails d) {
    _angleAtStart = _angle;
    if (d.pointerCount > 1) {
      _drag = _Drag.none;
      return;
    }
    final p = d.localFocalPoint;
    final b = Rect.fromLTRB(_box.left * _frame.width, _box.top * _frame.height, _box.right * _frame.width,
        _box.bottom * _frame.height);
    const hit = 30.0;
    bool near(Offset a) => (a - p).distance < hit;
    if (near(b.topLeft)) {
      _drag = _Drag.tl;
    } else if (near(b.topRight)) {
      _drag = _Drag.tr;
    } else if (near(b.bottomLeft)) {
      _drag = _Drag.bl;
    } else if (near(b.bottomRight)) {
      _drag = _Drag.br;
    } else if (_ratio.value == 0 && (p.dx - b.left).abs() < hit && p.dy > b.top && p.dy < b.bottom) {
      _drag = _Drag.l;
    } else if (_ratio.value == 0 && (p.dx - b.right).abs() < hit && p.dy > b.top && p.dy < b.bottom) {
      _drag = _Drag.r;
    } else if (_ratio.value == 0 && (p.dy - b.top).abs() < hit && p.dx > b.left && p.dx < b.right) {
      _drag = _Drag.t;
    } else if (_ratio.value == 0 && (p.dy - b.bottom).abs() < hit && p.dx > b.left && p.dx < b.right) {
      _drag = _Drag.b;
    } else if (b.contains(p)) {
      _drag = _Drag.move;
    } else {
      _drag = _Drag.none;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) {
      // Two-finger twist: rotate freely, snapping near straight angles.
      var a = _angleAtStart + d.rotation * 180 / math.pi;
      a = ((a + 180) % 360) - 180;
      for (final snap in const [-180.0, -90.0, 0.0, 90.0, 180.0]) {
        if ((a - snap).abs() < 2) a = snap;
      }
      setState(() => _angle = a);
      return;
    }
    if (_drag == _Drag.none || _frame.isEmpty) return;
    final dx = d.focalPointDelta.dx / _frame.width, dy = d.focalPointDelta.dy / _frame.height;
    setState(() => _box = _moveBox(_box, _drag, dx, dy));
  }

  Rect _moveBox(Rect b, _Drag drag, double dx, double dy) {
    const minSize = 0.08;
    if (drag == _Drag.move) {
      final nl = (b.left + dx).clamp(0.0, math.max(0.0, 1 - b.width)).toDouble();
      final nt = (b.top + dy).clamp(0.0, math.max(0.0, 1 - b.height)).toDouble();
      return Rect.fromLTWH(nl, nt, b.width, b.height);
    }
    var l = b.left, t = b.top, r = b.right, bo = b.bottom;
    switch (drag) {
      case _Drag.tl:
        l += dx;
        t += dy;
      case _Drag.tr:
        r += dx;
        t += dy;
      case _Drag.bl:
        l += dx;
        bo += dy;
      case _Drag.br:
        r += dx;
        bo += dy;
      case _Drag.l:
        l += dx;
      case _Drag.r:
        r += dx;
      case _Drag.t:
        t += dy;
      case _Drag.b:
        bo += dy;
      default:
        break;
    }
    // Clamp the dragged edge against the fixed one (clamping against an
    // edge that was itself dragged past it would give lower > upper).
    final movesL = drag == _Drag.tl || drag == _Drag.bl || drag == _Drag.l;
    final movesT = drag == _Drag.tl || drag == _Drag.tr || drag == _Drag.t;
    if (movesL) {
      l = l.clamp(0.0, math.max(0.0, r - minSize));
    } else {
      r = r.clamp(math.min(1.0, l + minSize), 1.0);
    }
    if (movesT) {
      t = t.clamp(0.0, math.max(0.0, bo - minSize));
    } else {
      bo = bo.clamp(math.min(1.0, t + minSize), 1.0);
    }
    if (_ratio.value != 0) {
      // Keep the ratio: size follows the width, anchored at the fixed corner.
      final rel = _ratioValue / _baseAspect; // width_frac / height_frac
      var w = r - l, h = w / rel;
      final anchorTop = drag == _Drag.bl || drag == _Drag.br;
      final anchorLeft = drag == _Drag.tr || drag == _Drag.br;
      final maxH = anchorTop ? 1 - t : bo;
      if (h > maxH) {
        h = maxH;
        w = h * rel;
      }
      final maxW = anchorLeft ? 1 - l : r;
      if (w > maxW) {
        w = maxW;
        h = w / rel;
      }
      if (anchorLeft) {
        r = l + w;
      } else {
        l = r - w;
      }
      if (anchorTop) {
        bo = t + h;
      } else {
        t = bo - h;
      }
    }
    return Rect.fromLTRB(l, t, r, bo);
  }

  // ----------------------------------------------------------- export
  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      final photo = _photo;
      final turns = _turns, fx = _flipX, fy = _flipY, angle = _angle, box = _box, cover = _cover;
      final out = await _bakeAsync(photo, turns, fx, fy, angle, cover, box.left, box.top, box.right, box.bottom);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Could not crop this photo.');
      }
    }
  }

  // --------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: const Color(0xFF14070E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14070E),
        foregroundColor: Colors.white,
        title: Text(context.tr('cropRotate')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _reset,
            child: const Text('Reset', style: TextStyle(color: Colors.white70)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: !_ready || _busy ? null : _done,
              child: _busy
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Done'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(builder: (context, c) {
                        final a = _baseAspect;
                        var fw = c.maxWidth, fh = fw / a;
                        if (fh > c.maxHeight) {
                          fh = c.maxHeight;
                          fw = fh * a;
                        }
                        _frame = Size(fw, fh);
                        return Center(
                          child: SizedBox(
                            width: fw,
                            height: fh,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: _onScaleStart,
                              onScaleUpdate: _onScaleUpdate,
                              onScaleEnd: (_) => setState(() => _drag = _Drag.none),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: ClipRect(
                                      child: Transform.rotate(
                                        angle: _rad,
                                        child: Transform.scale(
                                          scale: _cover,
                                          child: Transform.flip(
                                            flipX: _flipX,
                                            flipY: _flipY,
                                            child: RotatedBox(
                                              quarterTurns: _turns,
                                              child: Image.memory(_photo,
                                                  fit: BoxFit.fill, gaplessPlayback: true),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(painter: _CropPainter(_box, showGrid: _drag != _Drag.none || _angle != 0)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
            ),
            Container(
              color: palette.background,
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.primary,
                      selectedForegroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.crop), label: Text('Crop')),
                      ButtonSegment(value: true, icon: Icon(Icons.rotate_right), label: Text('Rotate')),
                    ],
                    selected: {_rotateTab},
                    onSelectionChanged: (v) => setState(() => _rotateTab = v.first),
                  ),
                  SizedBox(
                    height: 138,
                    child: _rotateTab
                        ? SingleChildScrollView(child: _rotateControls(palette))
                        : _ratioControls(palette),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratioControls(AppPalette palette) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      children: [
        for (final r in _ratios)
          GestureDetector(
            onTap: () => _applyRatio(r),
            child: Container(
              width: 70,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _ratio == r ? AppColors.primary : palette.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(r.icon, color: _ratio == r ? Colors.white : AppColors.primary),
                  const SizedBox(height: 6),
                  Text(r.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _ratio == r ? Colors.white : palette.textPrimary,
                      )),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _rotateControls(AppPalette palette) {
    Widget btn(IconData icon, String label, VoidCallback onTap, {bool on = false}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: on ? AppColors.primary : palette.surface,
                    child: Icon(icon, size: 20, color: on ? Colors.white : AppColors.primary),
                  ),
                  const SizedBox(height: 3),
                  Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              btn(Icons.rotate_left, 'Left', () => _turn(-1)),
              btn(Icons.rotate_right, 'Right', () => _turn(1)),
              btn(Icons.swap_vert, 'Flip up/down', () => setState(() => _flipY = !_flipY), on: _flipY),
              btn(Icons.swap_horiz, 'Flip left/right', () => setState(() => _flipX = !_flipX), on: _flipX),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text('${_angle.toStringAsFixed(_angle.truncateToDouble() == _angle ? 0 : 1)}°',
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Slider(
                  value: _angle.clamp(-45.0, 45.0),
                  min: -45,
                  max: 45,
                  divisions: 180,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _angle = v),
                ),
              ),
              IconButton(
                tooltip: 'Straight',
                onPressed: () => setState(() => _angle = 0),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
        ),
        Text('Tip: twist with two fingers on the photo to rotate freely',
            style: TextStyle(fontSize: 11, color: palette.textMuted)),
      ],
    );
  }
}

/// Dimmed outside, bright border, rule-of-thirds grid and corner handles.
class _CropPainter extends CustomPainter {
  _CropPainter(this.box, {this.showGrid = false});
  final Rect box;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(box.left * size.width, box.top * size.height, box.right * size.width,
        box.bottom * size.height);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white);
    if (showGrid) {
      final g = Paint()
        ..color = Colors.white54
        ..strokeWidth = 0.8;
      for (var i = 1; i < 3; i++) {
        final x = r.left + r.width * i / 3, y = r.top + r.height * i / 3;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), g);
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), g);
      }
    }
    final h = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 18.0;
    for (final (c, sx, sy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(len * sx, 0), h);
      canvas.drawLine(c, c + Offset(0, len * sy), h);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.box != box || old.showGrid != showGrid;
}

// Top-level wrappers: a closure created inside a State method can drag the
// State (widgets, render objects) into the isolate message and fail.
Future<(Uint8List, int, int)?> _uprightAsync(Uint8List bytes) => Isolate.run(() => _upright(bytes));

Future<Uint8List> _bakeAsync(Uint8List bytes, int turns, bool flipX, bool flipY, double angle, double cover,
        double l, double t, double r, double b) =>
    Isolate.run(() => _bake(bytes, turns, flipX, flipY, angle, cover, l, t, r, b));

/// Quarter turns → flips → straighten (with cover zoom) → crop box.
Uint8List _bake(Uint8List bytes, int turns, bool flipX, bool flipY, double angle, double cover, double l,
    double t, double r, double b) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('Could not read this photo.');
  var im = img.bakeOrientation(decoded);
  if (turns != 0) im = img.copyRotate(im, angle: 90 * turns);
  if (flipX) im = img.flipHorizontal(im);
  if (flipY) im = img.flipVertical(im);
  final w = im.width, h = im.height;
  double cx = w / 2, cy = h / 2;
  var fw = w.toDouble(), fh = h.toDouble();
  if (angle != 0) {
    im = img.copyRotate(im, angle: angle, interpolation: img.Interpolation.linear);
    cx = im.width / 2;
    cy = im.height / 2;
    fw = w / cover;
    fh = h / cover;
  }
  final x0 = (cx - fw / 2 + l * fw).round().clamp(0, im.width - 1);
  final y0 = (cy - fh / 2 + t * fh).round().clamp(0, im.height - 1);
  final cw = ((r - l) * fw).round().clamp(1, im.width - x0);
  final ch = ((b - t) * fh).round().clamp(1, im.height - y0);
  final out = img.copyCrop(im, x: x0, y: y0, width: cw, height: ch);
  return img.encodeJpg(out, quality: 95);
}

(Uint8List, int, int)? _upright(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  final orientation = d.exif.imageIfd.orientation ?? 1;
  if (orientation == 1) return (bytes, d.width, d.height);
  final u = img.bakeOrientation(d);
  return (img.encodeJpg(u, quality: 95), u.width, u.height);
}
