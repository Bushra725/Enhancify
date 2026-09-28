import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';

/// Gallery access, saving and sharing.
class MediaService {
  MediaService._();

  static final ImagePicker _picker = ImagePicker();

  // ------------------------------------------------------------- gallery
  static Future<PermissionState> requestGalleryPermission() {
    return PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
  }

  static Future<PermissionState> galleryPermissionState() {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    ).timeout(const Duration(seconds: 6), onTimeout: () => PermissionState.denied);
  }

  static Future<void> openSettings() => PhotoManager.openSetting();

  static Future<void> presentLimited() async {
    try {
      await PhotoManager.presentLimited();
    } catch (_) {}
  }

  /// Loads a page of the "Recent" album for the given type.
  static Future<List<AssetEntity>> loadPage(
    RequestType type, {
    required int page,
    int size = 60,
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      type: type,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate)],
      ),
    );
    if (paths.isEmpty) return [];
    return paths.first.getAssetListPaged(page: page, size: size);
  }

  // -------------------------------------------------------------- picker
  static Future<File?> pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    return x == null ? null : File(x.path);
  }

  static Future<List<File>> pickImages({int limit = 8}) async {
    final xs = await _picker.pickMultiImage(limit: limit < 2 ? 2 : limit);
    return xs.take(limit).map((x) => File(x.path)).toList();
  }

  static Future<File?> pickVideo() async {
    final x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: AppConfig.maxVideoSeconds),
    );
    return x == null ? null : File(x.path);
  }

  // ---------------------------------------------------------- save/share
  /// Saves to the device gallery. Returns an error message or null.
  static Future<String?> saveToGallery(File file, {bool video = false}) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        final ok = await Gal.requestAccess(toAlbum: true);
        if (!ok) return 'Permission denied. Allow photo access in Settings.';
      }
      if (video) {
        await Gal.putVideo(file.path, album: AppConfig.appName);
      } else {
        await Gal.putImage(file.path, album: AppConfig.appName);
      }
      return null;
    } on GalException catch (e) {
      return 'Could not save (${e.type.name}).';
    } catch (e) {
      return 'Could not save: $e';
    }
  }

  /// iPad needs an anchor rect for the share popover.
  static Rect get _origin {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    final v = views.first;
    final size = v.physicalSize / v.devicePixelRatio;
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  static Future<void> shareFiles(List<File> files, {String? text}) async {
    if (files.isEmpty) return;
    await Share.shareXFiles(
      files.map((f) => XFile(f.path)).toList(),
      text: text ?? 'Made with ${AppConfig.appName}',
      sharePositionOrigin: _origin,
    );
  }

  static Future<void> shareApp() async {
    await Share.share(
      'I enhance my photos with ${AppConfig.appName}! ${AppConfig.storeUrl}',
      sharePositionOrigin: _origin,
    );
  }
}
