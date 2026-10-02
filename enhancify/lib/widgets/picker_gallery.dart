import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Home-screen media grid backed by the **system photo picker** only.
/// Does not request READ_MEDIA_IMAGES / READ_MEDIA_VIDEO (Play policy).
class PickerGallery extends StatefulWidget {
  const PickerGallery({
    super.key,
    required this.onOpen,
    this.bottomPadding = 0,
  });

  final Future<void> Function(File file) onOpen;
  final double bottomPadding;

  @override
  State<PickerGallery> createState() => PickerGalleryState();
}

class PickerGalleryState extends State<PickerGallery> {
  final List<File> _files = [];
  bool _busy = false;

  Future<void> pickMore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await MediaService.pickImages(limit: 24);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        for (final f in picked) {
          if (!_files.any((e) => e.path == f.path)) _files.add(f);
        }
      });
      // Open the first newly picked photo so the flow feels immediate.
      await widget.onOpen(picked.first);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> pickOne() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final f = await MediaService.pickImage();
      if (!mounted || f == null) return;
      setState(() {
        if (!_files.any((e) => e.path == f.path)) _files.insert(0, f);
      });
      await widget.onOpen(f);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 24, 32, widget.bottomPadding + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 48, color: context.palette.textSecondary),
              const SizedBox(height: 14),
              Text(
                '${AppConfig.appName} uses your phone’s photo picker — '
                'no broad gallery access needed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: PillButton(
                  label: _busy ? 'Opening…' : 'Choose photos',
                  height: 48,
                  onPressed: _busy ? null : pickMore,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding: EdgeInsets.fromLTRB(12, 4, 12, widget.bottomPadding + 64),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: _files.length,
          itemBuilder: (context, i) {
            final file = _files[i];
            return GestureDetector(
              onTap: () => widget.onOpen(file),
              child: ColoredBox(
                color: context.palette.surface,
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: widget.bottomPadding + 12,
          child: FloatingActionButton.extended(
            onPressed: _busy ? null : pickMore,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}
