import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/l10n.dart';
import '../../services/music_video.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../export/export_screen.dart';

/// Add a song to a photo → MP4 ready for Reels, Stories, TikTok, Status.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key, required this.image});

  final File image;

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  String? _audioPath;
  String _audioName = '';
  double _songLength = 0;
  double _start = 0;
  double _length = 15;
  bool _zoom = true;
  bool _fade = true;
  bool _busy = false;
  VideoPlayerController? _player;
  Timer? _stopTimer;

  static const _lengths = [10.0, 15.0, 30.0, 60.0];

  @override
  void dispose() {
    _stopTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  double get _maxLength => _songLength <= 0 ? 60 : math.min(60, _songLength);
  double get _effectiveLength => math.min(_length, math.max(1, _songLength - _start));

  Future<void> _pick() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.audio);
      final path = res?.files.single.path;
      if (path == null || !mounted) return;
      setState(() => _busy = true);
      final d = await MusicVideo.durationOf(path);
      // The preview stop timer holds the old player; cancel before disposing it.
      _stopTimer?.cancel();
      await _player?.dispose();
      _player = null;
      final c = VideoPlayerController.file(File(path));
      try {
        await c.initialize();
        _player = c;
      } catch (_) {
        await c.dispose();
      }
      final ms = _player?.value.duration.inMilliseconds ?? 0;
      final length = d ?? ms / 1000;
      if (!mounted) {
        await _player?.dispose();
        return;
      }
      if (length <= 0.5) {
        showSnack(context, 'That file has no playable audio.');
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _audioPath = path;
        _audioName = res!.files.single.name;
        _songLength = length;
        _start = 0;
        _length = _lengths.firstWhere((l) => l >= math.min(15, length), orElse: () => 15);
        if (_length > length) _length = math.max(1.0, length.floorToDouble());
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Could not open that song.');
      }
    }
  }

  Future<void> _preview() async {
    final p = _player;
    if (p == null) return;
    _stopTimer?.cancel();
    if (p.value.isPlaying) {
      await p.pause();
      if (mounted) setState(() {});
      return;
    }
    await p.seekTo(Duration(milliseconds: (_start * 1000).round()));
    await p.play();
    if (!mounted) return;
    _stopTimer = Timer(Duration(milliseconds: (_effectiveLength * 1000).round()), () {
      p.pause();
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  Future<void> _create() async {
    final audio = _audioPath;
    if (audio == null) return;
    _stopTimer?.cancel();
    await _player?.pause();
    setState(() => _busy = true);
    try {
      final video = await MusicVideo.render(
        imagePath: widget.image.path,
        audioPath: audio,
        start: _start,
        seconds: _effectiveLength,
        zoom: _zoom,
        fade: _fade,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExportScreen(file: video, kind: ExportKind.video, title: 'Your video'),
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not make the video. Try another song.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(double s) {
    final m = s ~/ 60, sec = (s % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasSong = _audioPath != null;
    final maxStart = math.max(0.0, _songLength - _effectiveLength);
    final playing = _player?.value.isPlaying ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('addMusic'))),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(widget.image, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Icon(hasSong ? Icons.music_note : Icons.library_music, color: Colors.white),
                  ),
                  title: Text(hasSong ? _audioName : 'Choose a song',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(hasSong ? 'Length ${_fmt(_songLength)}' : 'MP3, M4A, WAV or AAC from your phone'),
                  trailing: hasSong
                      ? IconButton(
                          icon: Icon(playing ? Icons.pause_circle : Icons.play_circle,
                              color: AppColors.primary, size: 32),
                          onPressed: _player == null ? null : _preview,
                        )
                      : null,
                  onTap: _busy ? null : _pick,
                ),
              ),
            ),
            if (hasSong) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Text('Length', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final l in _lengths)
                            if (l <= _maxLength + 0.01)
                              ChoiceChip(
                                label: Text('${l.round()}s'),
                                selected: _length == l,
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(color: _length == l ? Colors.white : null),
                                showCheckmark: false,
                                onSelected: (_) => setState(() {
                                  _length = l;
                                  _start = math.min(_start, math.max(0, _songLength - l));
                                }),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Text('Start ${_fmt(_start)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(
                      child: Slider(
                        value: _start.clamp(0, maxStart),
                        max: maxStart <= 0 ? 1 : maxStart,
                        activeColor: AppColors.primary,
                        onChanged: maxStart <= 0 ? null : (v) => setState(() => _start = v),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        value: _zoom,
                        activeColor: AppColors.primary,
                        title: Text(context.tr('slowZoom')),
                        onChanged: (v) => setState(() => _zoom = v ?? true),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        value: _fade,
                        activeColor: AppColors.primary,
                        title: Text(context.tr('fadeInOut')),
                        onChanged: (v) => setState(() => _fade = v ?? true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                onPressed: _busy ? null : (hasSong ? _create : _pick),
                icon: Icon(hasSong ? Icons.movie_creation_outlined : Icons.library_music),
                label: Text(_busy
                    ? 'Working…'
                    : hasSong
                        ? 'Create video (${_effectiveLength.round()}s)'
                        : 'Choose a song'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
