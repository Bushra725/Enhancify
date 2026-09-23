import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows the "Uploading image..." modal while [task] runs, then closes it.
/// Returns the task result or rethrows its error.
Future<T> runWithProgress<T>(
  BuildContext context, {
  File? preview,
  bool isVideo = false,
  String initialStatus = 'Uploading image...',
  required Future<T> Function(void Function(String) setStatus) task,
}) async {
  final status = ValueNotifier<String>(initialStatus);
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProcessingView(
        status: status,
        preview: isVideo ? null : preview,
        isVideo: isVideo,
      ),
    ),
  );
  unawaited(navigator.push(route));
  // Let the route mount before a fast task finishes, so we never pop the
  // screen underneath the dialog.
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) {
    if (route.isActive) navigator.removeRoute(route);
    status.dispose();
    throw StateError('Enhancement was cancelled.');
  }
  try {
    return await task((s) => status.value = s);
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    Future<void>.delayed(const Duration(milliseconds: 400), status.dispose);
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({
    required this.status,
    required this.preview,
    required this.isVideo,
  });

  final ValueNotifier<String> status;
  final File? preview;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.82,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (preview != null)
                      Image.file(preview!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: AppColors.maroonDeep))
                    else
                      Container(
                        decoration: const BoxDecoration(
                          gradient: AppColors.giftGradient,
                        ),
                        child: Icon(
                          isVideo ? Icons.movie_outlined : Icons.image_outlined,
                          color: Colors.white24,
                          size: 90,
                        ),
                      ),
                    Container(color: Colors.black.withValues(alpha: 0.55)),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 46,
                            height: 46,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              color: AppColors.red,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ValueListenableBuilder<String>(
                              valueListenable: status,
                              builder: (_, s, __) => Text(
                                s,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Text(
                  'The enhancement may take a few seconds. '
                  "Please don't quit the app.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black87, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
