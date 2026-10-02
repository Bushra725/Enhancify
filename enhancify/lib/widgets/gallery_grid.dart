import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../config/app_config.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'permission_rationale.dart';

/// Recent photos or videos from the device, with permission handling and
/// infinite scroll.
class GalleryGrid extends StatefulWidget {
  const GalleryGrid({
    super.key,
    required this.type,
    required this.onTap,
    this.bottomPadding = 0,
  });

  final RequestType type;
  final ValueChanged<AssetEntity> onTap;
  final double bottomPadding;

  @override
  State<GalleryGrid> createState() => _GalleryGridState();
}

class _GalleryGridState extends State<GalleryGrid> with WidgetsBindingObserver {
  static const _pageSize = 24;

  PermissionState? _perm;
  final List<AssetEntity> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  bool _askedOnce = false;
  int _generation = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _checkPermission();
  }

  @override
  void didUpdateWidget(covariant GalleryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _generation++;
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _loadMore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    try {
      final p = await MediaService.galleryPermissionState();
      if (!mounted) return;
      final changed = p != _perm;
      setState(() => _perm = p);
      if (p.hasAccess && (changed || _items.isEmpty)) _reload();
      if (p == PermissionState.notDetermined && !_askedOnce) {
        _askedOnce = true;
        final kind = widget.type == RequestType.video
            ? MediaAccessKind.videos
            : widget.type == RequestType.image
                ? MediaAccessKind.photos
                : MediaAccessKind.photosAndVideos;
        final proceed = await showMediaAccessRationale(context, kind: kind);
        if (!mounted || !proceed) return;
        final r = await MediaService.requestGalleryPermission();
        if (!mounted) return;
        setState(() => _perm = r);
        if (r.hasAccess) _reload();
      }
    } catch (_) {
      if (mounted) setState(() => _perm = PermissionState.denied);
    }
  }

  Future<void> _request() async {
    final kind = widget.type == RequestType.video
        ? MediaAccessKind.videos
        : widget.type == RequestType.image
            ? MediaAccessKind.photos
            : MediaAccessKind.photosAndVideos;
    final proceed = await showMediaAccessRationale(context, kind: kind);
    if (!mounted || !proceed) return;
    final p = await MediaService.requestGalleryPermission();
    if (!mounted) return;
    setState(() => _perm = p);
    if (p.hasAccess) {
      _reload();
    } else if (_askedOnce) {
      await MediaService.openSettings();
    }
    _askedOnce = true;
  }

  Future<void> _reload() {
    _generation++;
    _loading = false;
    _items.clear();
    _page = 0;
    _hasMore = true;
    if (mounted) setState(() {});
    return _loadMore();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    final gen = _generation;
    try {
      final page =
          await MediaService.loadPage(widget.type, page: _page, size: _pageSize)
              .timeout(const Duration(seconds: 8), onTimeout: () => <AssetEntity>[]);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page);
        _page++;
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      if (mounted && gen == _generation) setState(() => _hasMore = false);
    } finally {
      if (gen == _generation) _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = _perm;
    if (perm == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.red));
    }
    if (!perm.hasAccess) return _noAccess();
    if (_items.isEmpty && perm != PermissionState.limited) {
      return Center(
        child: _loading || _hasMore
            ? const CircularProgressIndicator(color: AppColors.red)
            : Text(
                widget.type == RequestType.video
                    ? 'No videos found'
                    : 'No photos found',
                style: TextStyle(color: context.palette.textSecondary),
              ),
      );
    }
    return RefreshIndicator(
      color: AppColors.red,
      onRefresh: _reload,
      child: GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(12, 4, 12, widget.bottomPadding + 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _items.length + (perm == PermissionState.limited ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return InkWell(
              onTap: () async {
                await MediaService.presentLimited();
                await _reload();
              },
              child: Container(
                color: context.palette.surface,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined),
                    SizedBox(height: 6),
                    Text('Manage', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          final a = _items[i];
          return GestureDetector(
            onTap: () => widget.onTap(a),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: context.palette.surface,
                  child: AssetEntityImage(
                    a,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(300),
                    thumbnailFormat: ThumbnailFormat.jpeg,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: ctx.palette.textMuted),
                  ),
                ),
                if (a.type == AssetType.video)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _fmt(a.videoDuration),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _noAccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, color: context.palette.textSecondary),
            const SizedBox(height: 12),
            Text(
              widget.type == RequestType.video
                  ? '${AppConfig.appName} needs video access to enhance clips '
                      'you choose and save improved videos to your gallery.'
                  : '${AppConfig.appName} needs photo access to enhance, edit, '
                      'restore, and collage images you choose, then save '
                      'results to your gallery.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: PillButton(
                  label: 'Give Access', height: 46, onPressed: _request),
            ),
          ],
        ),
      ),
    );
  }
}
