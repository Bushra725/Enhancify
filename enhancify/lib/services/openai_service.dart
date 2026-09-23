import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'replicate_service.dart';

/// Edits a photo with the OpenAI Image API.
///
/// Each feature sends a different prompt, so Enhance, Natural, Ultra HD,
/// filters, colorize, and AI Photos do not return the same picture.
class OpenAiService {
  OpenAiService(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _flare = 'gpt-image-2.5-flare';
  static const _sunburst = 'gpt-image-2.5-sunburst';

  Future<List<int>> edit({
    required File image,
    required String prompt,
    bool highDetail = false,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.openai.com/v1/images/edits'),
    )
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = highDetail ? _sunburst : _flare
      ..fields['prompt'] = prompt
      ..fields['size'] = 'auto'
      ..fields['quality'] = highDetail ? 'high' : 'medium'
      ..fields['output_format'] = 'jpeg'
      ..files.add(await http.MultipartFile.fromPath(
        'image',
        image.path,
        filename: 'photo.jpg',
      ));

    final streamed = await _client.send(req).timeout(const Duration(minutes: 3));
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (body['error'] is Map ? body['error']['message'] : null)
              ?.toString() ??
          'OpenAI request failed (${response.statusCode}).';
      throw AiException(message);
    }
    final data = body['data'];
    if (data is List && data.isNotEmpty && data.first is Map) {
      final b64 = (data.first as Map)['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) return base64Decode(b64);
    }
    throw AiException('OpenAI did not return an image.');
  }
}
