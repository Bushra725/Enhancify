import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'replicate_service.dart';

/// Edits the photo the person selected with the Gemini image API.
///
/// The source image is sent with the prompt, so oil paint, sketch, and
/// enhance results are made from that photo.
class GeminiService {
  GeminiService(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _model = 'gemini-2.5-flash-image';

  Future<List<int>> edit({
    required File image,
    required String prompt,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt},
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Encode(await image.readAsBytes()),
                    },
                  },
                ],
              },
            ],
            'generationConfig': {
              'responseModalities': ['TEXT', 'IMAGE'],
            },
          }),
        )
        .timeout(const Duration(minutes: 3));

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (body['error'] is Map ? body['error']['message'] : null)
              ?.toString() ??
          'Gemini request failed (${response.statusCode}).';
      throw AiException(message);
    }

    final candidates = body['candidates'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is! Map) continue;
        final content = candidate['content'];
        if (content is! Map) continue;
        final parts = content['parts'];
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map) continue;
          final inline = part['inlineData'] ?? part['inline_data'];
          if (inline is Map) {
            final data = inline['data'] as String?;
            if (data != null && data.isNotEmpty) return base64Decode(data);
          }
        }
      }
    }
    throw AiException('Gemini did not return an image of this photo.');
  }
}
