import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/gif_maker.dart';
import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../export/export_screen.dart';

/// Makes a looping GIF with a live preview.
class GifMakerScreen extends StatefulWidget {
  const GifMakerScreen({super.key, required this.photos});

  final List<Uint8List> photos;

  @override
  State<GifMakerScreen> createState() => _GifMakerScreenState();
}

class _GifMakerScreenState extends State<GifMakerScreen> {
  late final List<Uint8List> _photos = List.of(widget.photos);
  GifStyle _style = GifStyle.pulse;
  double _speed = 1; // 0 slow, 1 normal, 2 fast
  int _size = 480;
  Uint8List? _gif;
  bool _busy = false;
  int _job = 0;
  Timer? _debounce;

  static const _sizes = [(360, 'Small'), (480, 'Medium'), (640, 'Large')];

  int get _frameMs => const [140, 90, 50][_speed.round()];

  @override
  void initState() {
    super.initState();
    if (_photos.length > 1) _style = GifStyle.slideshow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _build();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _build);
  }

  Future<void> _build() async {
    final job = ++_job;
    setState(() => _busy = true);
    try {
      final gif = await GifMaker.make(_photos, style: _style, frameMs: _frameMs, size: _size);
      if (!mounted || job != _job) return;
      setState(() => _gif = gif);
    } catch (e) {
      if (mounted && job == _job) showSnack(context, 'Could not make the GIF from this photo.');
    } finally {
      if (mounted && job == _job) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() async {
    final files = await MediaService.pickImages(limit: 8);
    if (files.isEmpty) return;
    final bytes = <Uint8List>[];
    for (final f in files) {
      bytes.add(await f.readAsBytes());
    }
    if (!mounted) return;
    setState(() {
      _photos.addAll(bytes);
      if (_photos.length > 10) _photos.removeRange(10, _photos.length);
      _style = GifStyle.slideshow;
    });
    _build();
  }

  Future<void> _next() async {
    final gif = _gif;
    if (gif == null) return;
    final file = File('${Directory.systemTemp.path}/enhancify_${DateTime.now().millisecondsSinceEpoch}.gif');
    await file.writeAsBytes(gif, flush: true);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportScreen(file: file, kind: ExportKind.gif, title: 'Your GIF'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gif = _gif;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('makeGif')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: gif == null || _busy ? null : _next,
              child: const Text('Next'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: gif == null
                      ? const CircularProgressIndicator(color: AppColors.primary)
                      : Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              // A new key restarts the animation when the GIF changes.
                              child: Image.memory(gif, key: ValueKey(gif.hashCode), gaplessPlayback: true),
                            ),
                            Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${(gif.length / 1024).round()} KB',
                                  style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final s in GifStyle.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: _style == s,
                        showCheckmark: false,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: _style == s ? Colors.white : palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setState(() => _style = s);
                          _schedule();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.speed, size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(const ['Slow', 'Normal', 'Fast'][_speed.round()],
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Slider(
                      value: _speed,
                      max: 2,
                      divisions: 2,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _speed = v),
                      onChangeEnd: (_) => _schedule(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (px, label) in _sizes)
                    ChoiceChip(
                        label: Text(label),
                        selected: _size == px,
                        showCheckmark: false,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _size == px ? Colors.white : palette.textPrimary),
                        onSelected: (_) {
                          setState(() => _size = px);
                          _schedule();
                        },
                      ),
                  TextButton.icon(
                    onPressed: _busy ? null : _addPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_photos.length > 1 ? '${_photos.length} photos' : 'Add photos'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
