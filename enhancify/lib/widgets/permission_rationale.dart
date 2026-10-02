import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// Explains why Enhancify needs media access before the system permission
/// dialog. Required for clear disclosure on Play Store / App Store review.
enum MediaAccessKind { photos, videos, photosAndVideos, camera }

Future<bool> showMediaAccessRationale(
  BuildContext context, {
  required MediaAccessKind kind,
}) async {
  final (title, body) = switch (kind) {
    MediaAccessKind.photos => (
        'Allow photo access',
        '${AppConfig.appName} needs access to your photos so you can choose '
            'images to enhance, edit, restore, collage, and save back to your '
            'gallery. Photos stay on your device unless you use an optional '
            'cloud AI feature.',
      ),
    MediaAccessKind.videos => (
        'Allow video access',
        '${AppConfig.appName} needs access to your videos so you can pick a '
            'clip to enhance and save the improved video to your gallery. '
            'Videos stay on your device unless you use an optional cloud AI '
            'feature.',
      ),
    MediaAccessKind.photosAndVideos => (
        'Allow photos & videos',
        '${AppConfig.appName} needs access to your photos and videos so you '
            'can enhance, edit, restore, collage, and save results to your '
            'gallery. Your media stays on your device unless you use an '
            'optional cloud AI feature.',
      ),
    MediaAccessKind.camera => (
        'Allow camera access',
        '${AppConfig.appName} uses the camera only when you choose to take a '
            'new photo to enhance or edit. We do not record or upload in the '
            'background.',
      ),
  };

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.palette.surface,
      title: Text(title),
      content: Text(body, style: TextStyle(color: ctx.palette.textSecondary, height: 1.35)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return ok == true;
}
