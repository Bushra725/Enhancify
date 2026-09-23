import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/media_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class VideoResultScreen extends StatefulWidget {
  const VideoResultScreen({
    super.key,
    required this.original,
    required this.result,
  });

  final File original;
  final File result;

  @override
  State<VideoResultScreen> createState() => _VideoResultScreenState();
}

class _VideoResultScreenState extends State<VideoResultScreen> {
  VideoPlayerController? _controller;
  bool _showOriginal = false;
  bool _saving = false;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final old = _controller;
    final c = VideoPlayerController.file(
        _showOriginal ? widget.original : widget.result);
    if (old != null || _error != null) {
      setState(() {
        _controller = null;
        _error = null;
      });
    }
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted || id != _loadId) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      await c.dispose();
      if (mounted && id == _loadId) {
        setState(() => _error = 'Could not play this video.');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final err = await MediaService.saveToGallery(widget.result, video: true);
    if (!mounted) return;
    setState(() => _saving = false);
    showSnack(context, err ?? 'Video saved to your gallery ✨');
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced Video'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => MediaService.shareFiles([widget.result]),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Text(_error!,
                      style: TextStyle(color: context.palette.textSecondary))
                  : c == null
                      ? const CircularProgressIndicator(color: AppColors.red)
                      : GestureDetector(
                          onTap: () {
                            if (c.value.isPlaying) {
                              c.pause();
                            } else {
                              c.play();
                            }
                            setState(() {});
                          },
                          child: AspectRatio(
                            aspectRatio: c.value.aspectRatio <= 0
                                ? 16 / 9
                                : c.value.aspectRatio,
                            child: VideoPlayer(c),
                          ),
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Enhanced')),
                ButtonSegment(value: true, label: Text('Original')),
              ],
              selected: {_showOriginal},
              onSelectionChanged: (s) {
                setState(() => _showOriginal = s.first);
                _load();
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PillButton(
                label: 'Save video',
                kind: ButtonStyleKind.brand,
                loading: _saving,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
