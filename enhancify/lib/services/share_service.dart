import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import 'media_service.dart';

/// A social app we can post to directly.
class SocialTarget {
  const SocialTarget(this.id, this.label, this.androidPackage, this.color);
  final String id;
  final String label;
  final String androidPackage;
  final int color;

  static const instagram = SocialTarget('instagram', 'Instagram', 'com.instagram.android', 0xFFE1306C);
  static const facebook = SocialTarget('facebook', 'Facebook', 'com.facebook.katana', 0xFF1877F2);
  static const whatsapp = SocialTarget('whatsapp', 'WhatsApp', 'com.whatsapp', 0xFF25D366);
  static const tiktok = SocialTarget('tiktok', 'TikTok', 'com.zhiliaoapp.musically', 0xFF111111);
  static const snapchat = SocialTarget('snapchat', 'Snapchat', 'com.snapchat.android', 0xFFFFC700);

  static const all = [instagram, facebook, whatsapp, tiktok, snapchat];
}

enum ShareOutcome { opened, notInstalled, sheet }

/// Posts a finished file straight into a social app (Android), or opens the
/// system share sheet (iOS, or when the app isn't installed).
class ShareService {
  ShareService._();

  static const _channel = MethodChannel('enhancify/share');

  static String mimeFor(File file) {
    final p = file.path.toLowerCase();
    if (p.endsWith('.mp4') || p.endsWith('.mov')) return 'video/mp4';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  static bool get _android => !kIsWeb && Platform.isAndroid;

  static Future<ShareOutcome> postTo(SocialTarget target, File file) async {
    if (_android) {
      try {
        final ok = await _channel.invokeMethod<bool>('shareToApp', {
          'path': file.path,
          'mime': mimeFor(file),
          'package': target.androidPackage,
        });
        if (ok == true) return ShareOutcome.opened;
        // TikTok has two package names (global / Asia).
        if (target.id == 'tiktok') {
          final alt = await _channel.invokeMethod<bool>('shareToApp', {
            'path': file.path,
            'mime': mimeFor(file),
            'package': 'com.ss.android.ugc.trill',
          });
          if (alt == true) return ShareOutcome.opened;
        }
        return ShareOutcome.notInstalled;
      } on MissingPluginException {
        // fall back to the share sheet
      } on PlatformException {
        // fall back to the share sheet
      }
    }
    // iOS: the share sheet lists Instagram, Facebook, WhatsApp etc.
    await MediaService.shareFiles([file], text: 'Made with ${AppConfig.appName} 💖');
    return ShareOutcome.sheet;
  }

  static Future<void> shareAnywhere(File file) async {
    if (_android) {
      try {
        final ok = await _channel.invokeMethod<bool>('shareToApp', {
          'path': file.path,
          'mime': mimeFor(file),
          'text': 'Made with ${AppConfig.appName} 💖',
        });
        if (ok == true) return;
      } catch (_) {}
    }
    await MediaService.shareFiles([file], text: 'Made with ${AppConfig.appName} 💖');
  }
}
