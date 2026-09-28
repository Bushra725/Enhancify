import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/passport_maker.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../export/export_screen.dart';

/// Passport / visa / ID photos at official sizes, with background swap,
/// auto face framing and a 6×4 in print sheet.
class PassportScreen extends StatefulWidget {
  const PassportScreen({super.key, required this.photo});

  final Uint8List photo;

  @override
  State<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends State<PassportScreen> {
  PassportSource? _src;
  String? _error;
  PassportSpec _spec = PassportSpec.all.first;
  int _bg = 0xFFFFFF;
  bool _keepBg = false;
  double _zoom = 1;
  double _dx = 0;
  double _dy = 0;
  bool _busy = false;
  bool _guides = true;

  static const _backgrounds = [
    (0xFFFFFF, 'White'),
    (0xF2F2F2, 'Off-white'),
    (0xDCEBFA, 'Light blue'),
    (0xE3E3E3, 'Light grey'),
    (0x4A90D9, 'Blue'),
    (0xD32F2F, 'Red'),
  ];

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      final src = await PassportMaker.analyze(widget.photo);
      if (!mounted) return;
      setState(() {
        _src = src;
        _keepBg = !src.hasPerson;
      });
      if (!src.faceFound) {
        showSnack(context, 'No face found. Use the sliders to line up the head with the guides.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read this photo.');
    }
  }

  Future<void> _export({required bool sheet}) async {
    final src = _src;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      var jpg = await PassportMaker.render(src, _spec,
          bg: _bg, keepBackground: _keepBg, zoom: _zoom, dx: _dx, dy: _dy);
      if (sheet) jpg = await PassportMaker.printSheet(jpg, _spec);
      final file = File('${Directory.systemTemp.path}/passport_${_spec.id}_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpg, flush: true);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExportScreen(
          file: file,
          title: sheet ? 'Print sheet (6×4 in)' : 'Passport photo',
        ),
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not make the photo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = _src;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('passport'))),
      body: SafeArea(
        child: src == null
            ? Center(
                child: _error != null
                    ? Text(_error!)
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 12),
                          Text('Finding your face…'),
                        ],
                      ),
              )
            : Column(
                children: [
                  Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(16), child: _preview(src)))),
                  if (_busy) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
                  Expanded(child: _controls(src)),
                ],
              ),
      ),
    );
  }

  Widget _preview(PassportSource src) {
    final bgColor = Color(0xFF000000 | _bg);
    return AspectRatio(
      aspectRatio: _spec.aspect,
      child: LayoutBuilder(builder: (context, box) {
        final k = box.maxWidth / _spec.pxW;
        final l = PassportMaker.layout(src, _spec, zoom: _zoom, dx: _dx, dy: _dy);
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: l.left * k,
                  top: l.top * k,
                  width: src.width * l.scale * k,
                  height: src.height * l.scale * k,
                  child: Image.memory(
                    _keepBg || !src.hasPerson ? src.photo : src.cutout,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
                if (_guides) Positioned.fill(child: CustomPaint(painter: _GuidePainter(_spec))),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _controls(PassportSource src) {
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in PassportSpec.all)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text(s.sizeText, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                    selected: _spec == s,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(color: _spec == s ? Colors.white : palette.textPrimary),
                    onSelected: (_) => setState(() => _spec = s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Background', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (c, name) in _backgrounds)
                      Tooltip(
                        message: name,
                        child: GestureDetector(
                          onTap: src.hasPerson
                              ? () => setState(() {
                                    _bg = c;
                                    _keepBg = false;
                                  })
                              : null,
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Color(0xFF000000 | c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: !_keepBg && _bg == c ? AppColors.primary : palette.border,
                                width: !_keepBg && _bg == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (!src.hasPerson)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Background swap needs a clear photo of one person.',
                style: TextStyle(fontSize: 12, color: palette.textMuted)),
          )
        else
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('keepOriginalBg')),
            value: _keepBg,
            onChanged: (v) => setState(() => _keepBg = v),
          ),
        _slider(Icons.zoom_in, 'Size', _zoom, 0.6, 1.6, (v) => _zoom = v),
        _slider(Icons.swap_vert, 'Up / down', _dy, -0.3, 0.3, (v) => _dy = v),
        _slider(Icons.swap_horiz, 'Left / right', _dx, -0.3, 0.3, (v) => _dx = v),
        Row(
          children: [
            Checkbox(
              value: _guides,
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _guides = v ?? true),
            ),
            const Expanded(child: Text('Show head guides', style: TextStyle(fontSize: 13))),
            TextButton(
              onPressed: () => setState(() {
                _zoom = 1;
                _dx = 0;
                _dy = 0;
              }),
              child: const Text('Auto fit'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : () => _export(sheet: false),
                child: const Text('Save photo'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : () => _export(sheet: true),
                child: const Text('Print sheet 6×4'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${_spec.pxW} × ${_spec.pxH} px at 300 dpi. Always check your country\'s latest photo rules.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: palette.textMuted),
        ),
      ],
    );
  }

  Widget _slider(IconData icon, String label, double value, double min, double max, ValueChanged<double> set) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        SizedBox(width: 84, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => set(v)),
          ),
        ),
      ],
    );
  }
}

/// Dashed lines for the top of the head and the chin, plus a face oval.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.spec);
  final PassportSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xAAEA026A)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final top = spec.topRatio * size.height;
    final chin = (spec.topRatio + spec.headRatio) * size.height;
    void dashed(double y) {
      for (var x = 0.0; x < size.width; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), p);
      }
    }

    dashed(top);
    dashed(chin);
    final headH = chin - top;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, (top + chin) / 2), width: headH * 0.72, height: headH),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => old.spec != spec;
}
