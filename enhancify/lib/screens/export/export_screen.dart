import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/media_service.dart';
import '../../services/share_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../tools/gif_maker_screen.dart';
import '../tools/music_screen.dart';

enum ExportKind { image, gif, video }

/// The "all done" screen after editing: preview, save, share and post
/// straight to Instagram, Facebook, WhatsApp, TikTok or Snapchat.
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.file,
    this.kind = ExportKind.image,
    this.title = 'Ready to share',
    this.showSave = true,
  });

  final File file;
  final ExportKind kind;
  final String title;

  /// False when the previous screen already has its own Save button.
  final bool showSave;

  static Future<void> open(BuildContext context, File file,
      {ExportKind kind = ExportKind.image, bool showSave = true, String title = 'Ready to share'}) {
    return Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ExportScreen(file: file, kind: kind, showSave: showSave, title: title)));
  }

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  VideoPlayerController? _video;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == ExportKind.video) {
      final c = VideoPlayerController.file(widget.file);
      _video = c;
      c.initialize().then((_) {
        if (!mounted) return;
        c
          ..setLooping(true)
          ..play();
        setState(() {});
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final err = await MediaService.saveToGallery(widget.file, video: widget.kind == ExportKind.video);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = err == null;
    });
    showSnack(context, err ?? 'Saved to your gallery ✨');
  }

  Future<void> _post(SocialTarget t) async {
    final outcome = await ShareService.postTo(t, widget.file);
    if (!mounted) return;
    if (outcome == ShareOutcome.notInstalled) {
      showSnack(context, '${t.label} isn\'t installed. Opening other options…');
      await ShareService.shareAnywhere(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => widget.showSave
                ? Navigator.of(context).popUntil((r) => r.isFirst)
                : Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Center(child: _preview()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (widget.showSave) ...[
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: Icon(_saved ? Icons.check_circle : Icons.download_rounded),
                      label: Text(_saved ? 'Saved' : 'Save'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.4),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      onPressed: () => ShareService.shareAnywhere(widget.file),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Post to',
                    style: TextStyle(fontWeight: FontWeight.w700, color: palette.textSecondary)),
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final t in SocialTarget.all) _social(t),
                  _circle('More', Icons.more_horiz, palette.surfaceHigh, palette.textPrimary,
                      () => ShareService.shareAnywhere(widget.file)),
                ],
              ),
            ),
            if (widget.kind == ExportKind.image)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _extra(Icons.music_note, 'Add music', () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MusicScreen(image: widget.file)));
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _extra(Icons.gif_box, 'Make GIF', () async {
                        final bytes = await widget.file.readAsBytes();
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => GifMakerScreen(photos: [bytes])));
                      }),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final radius = BorderRadius.circular(14);
    if (widget.kind == ExportKind.video) {
      final c = _video;
      if (c == null || !c.value.isInitialized) {
        return const CircularProgressIndicator(color: AppColors.primary);
      }
      return GestureDetector(
        onTap: () {
          if (c.value.isPlaying) {
            c.pause();
          } else {
            c.play();
          }
        },
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
        ),
      );
    }
    // Image.file animates GIFs on its own.
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(widget.file, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }

  Widget _social(SocialTarget t) =>
      _circle(t.label, _iconFor(t), Color(t.color), Colors.white, () => _post(t));

  IconData _iconFor(SocialTarget t) {
    switch (t.id) {
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'facebook':
        return Icons.facebook;
      case 'whatsapp':
        return Icons.chat;
      case 'tiktok':
        return Icons.tiktok;
      case 'snapchat':
        return Icons.snapchat;
      default:
        return Icons.share;
    }
  }

  Widget _circle(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 24, backgroundColor: bg, child: Icon(icon, color: fg)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _extra(IconData icon, String label, VoidCallback onTap) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Share to" row (WhatsApp, Instagram, Facebook, TikTok, More) for
/// result screens that already have their own Save button.
class SocialShareBar extends StatelessWidget {
  const SocialShareBar({super.key, required this.file});

  final File file;

  static const _targets = [
    (SocialTarget.whatsapp, Icons.chat),
    (SocialTarget.instagram, Icons.camera_alt_outlined),
    (SocialTarget.facebook, Icons.facebook),
    (SocialTarget.tiktok, Icons.tiktok),
  ];

  Future<void> _post(BuildContext context, SocialTarget t) async {
    final outcome = await ShareService.postTo(t, file);
    if (!context.mounted) return;
    if (outcome == ShareOutcome.notInstalled) {
      showSnack(context, '${t.label} isn\'t installed. Opening other options…');
      await ShareService.shareAnywhere(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget circle(String tip, IconData icon, Color bg, Color fg, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: CircleAvatar(radius: 20, backgroundColor: bg, child: Icon(icon, color: fg, size: 20)),
          ),
        );
    return Row(
      children: [
        Text('Share to', style: TextStyle(fontWeight: FontWeight.w700, color: palette.textSecondary)),
        const Spacer(),
        for (final (t, icon) in _targets) ...[
          circle(t.label, icon, Color(t.color), Colors.white, () => _post(context, t)),
          const SizedBox(width: 8),
        ],
        circle('More', Icons.ios_share, palette.surfaceHigh, palette.textPrimary,
            () => ShareService.shareAnywhere(file)),
      ],
    );
  }
}
