import 'dart:math';

import 'package:http/http.dart' as http;

import 'replicate_service.dart';

/// Built-in image generation. No key is required from the person using the app.
///
/// Each prompt returns its own picture, so AI Photos and filters do not
/// all come back the same.
class PollinationsService {
  PollinationsService({http.Client? client, Random? random})
      : _client = client ?? http.Client(),
        _random = random ?? Random();

  final http.Client _client;
  final Random _random;

  Future<List<int>> generate(String prompt, {int width = 1024, int height = 1024}) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _once(prompt, width: width, height: height);
      } catch (e) {
        lastError = e;
        if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 16));
      }
    }
    if (lastError is AiException) throw lastError;
    throw AiException('The AI could not create this photo. Try again.');
  }

  Future<List<int>> _once(String prompt, {required int width, required int height}) async {
    final seed = _random.nextInt(1 << 30);
    final w = width.clamp(256, 1024);
    final h = height.clamp(256, 1024);
    final uri = Uri.parse(
      'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}'
      '?model=flux&width=$w&height=$h&nologo=true&seed=$seed',
    );
    final response = await _client.get(uri, headers: const {
      'Accept': 'image/jpeg,image/png,image/webp',
    }).timeout(const Duration(minutes: 2));
    final bytes = response.bodyBytes;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        _isImage(bytes)) {
      return bytes;
    }
    throw AiException('The AI could not create this photo. Try again.');
  }

  bool _isImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return true;
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      return true;
    }
    return false;
  }
}
