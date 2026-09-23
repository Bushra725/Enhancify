import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/ai_models.dart';
import '../config/app_config.dart';

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

class _ModelInfo {
  final String? versionId;
  final Map<String, dynamic> inputProps;

  /// Set once we learn the model must be run by version id (community model).
  bool versionOnly = false;
  _ModelInfo(this.versionId, this.inputProps);
}

/// Thin Replicate client.
///
/// Works in two modes with the exact same code path:
///  * proxy  : `BACKEND_URL/replicate/v1/...` (token lives on your server)
///  * direct : `https://api.replicate.com/v1/...` (dev only)
class ReplicateService {
  ReplicateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, _ModelInfo> _modelCache = {};

  static const _timeout = Duration(seconds: 60);
  static const _pollInterval = Duration(milliseconds: 1500);
  static const _maxWait = Duration(minutes: 10);

  bool get _useProxy => AppConfig.backendUrl.isNotEmpty;

  String get _base {
    if (_useProxy) {
      final b = AppConfig.backendUrl.endsWith('/')
          ? AppConfig.backendUrl.substring(0, AppConfig.backendUrl.length - 1)
          : AppConfig.backendUrl;
      return '$b/replicate/v1';
    }
    return 'https://api.replicate.com/v1';
  }

  Map<String, String> get _headers {
    final h = <String, String>{};
    if (_useProxy) {
      if (AppConfig.backendAppKey.isNotEmpty) {
        h['x-app-key'] = AppConfig.backendAppKey;
      }
    } else {
      h['Authorization'] = 'Bearer ${AppConfig.replicateToken}';
    }
    return h;
  }

  // ------------------------------------------------------------ helpers
  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      body = {'detail': r.body};
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = body['detail'] ?? body['error'] ?? 'HTTP ${r.statusCode}';
      throw AiException(_friendly(r.statusCode, detail.toString()));
    }
    return body;
  }

  String _friendly(int code, String detail) {
    if (code == 401 || code == 403) {
      return 'AI service authorization failed. Check your API token / server.';
    }
    if (code == 402) return 'AI service billing limit reached.';
    if (code == 429) return 'Too many requests. Please try again in a moment.';
    return detail;
  }

  Future<_ModelInfo> _modelInfo(AiModel m) async {
    final cached = _modelCache[m.slug];
    if (cached != null) return cached;
    final r = await _client
        .get(Uri.parse('$_base/models/${m.slug}'), headers: _headers)
        .timeout(_timeout);
    final j = _decode(r);
    final lv = j['latest_version'] as Map<String, dynamic>?;
    Map<String, dynamic> props = {};
    try {
      final schemas = (lv?['openapi_schema'] as Map?)?['components']?['schemas']
          as Map?;
      final input = schemas?['Input'] as Map?;
      props = Map<String, dynamic>.from(input?['properties'] as Map? ?? {});
    } catch (_) {}
    final info = _ModelInfo(lv?['id'] as String?, props);
    _modelCache[m.slug] = info;
    return info;
  }

  /// Keeps only inputs the model accepts and coerces simple types.
  Map<String, dynamic> _mapInput(
    AiModel m,
    _ModelInfo info,
    String? mediaUrl,
    Map<String, dynamic> input,
  ) {
    final props = info.inputProps;
    final out = <String, dynamic>{};
    if (mediaUrl != null) {
      var key = m.mediaKey;
      if (props.isNotEmpty && !props.containsKey(key)) {
        key = props.entries
            .firstWhere(
              (e) => e.value is Map && (e.value as Map)['format'] == 'uri',
              orElse: () => MapEntry(m.mediaKey, const {}),
            )
            .key;
      }
      out[key] = mediaUrl;
    }
    final merged = {...m.defaults, ...input};
    merged.forEach((k, v) {
      if (props.isEmpty) {
        out[k] = v;
        return;
      }
      final spec = props[k];
      if (spec is! Map) return; // unknown input: drop
      final allowed = spec['enum'];
      var value = v;
      if (spec['type'] == 'integer' && value is double) value = value.round();
      if (spec['type'] == 'number' && value is int) value = value.toDouble();
      if (allowed is List && !allowed.contains(value)) return;
      out[k] = value;
    });
    return out;
  }

  // ------------------------------------------------------------ public
  Future<String> uploadFile(File file) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/files'))
      ..headers.addAll(_headers)
      ..files.add(await http.MultipartFile.fromPath(
        'content',
        file.path,
        filename: p.basename(file.path).replaceAll(' ', '_'),
      ));
    final streamed = await _client.send(req).timeout(const Duration(minutes: 3));
    final r = await http.Response.fromStream(streamed);
    final j = _decode(r);
    final url = (j['urls'] as Map?)?['get'] as String?;
    if (url == null) throw AiException('Upload failed.');
    return url;
  }

  /// Runs a model and returns the list of output URLs.
  Future<List<String>> run(
    AiModel model, {
    String? mediaUrl,
    Map<String, dynamic> input = const {},
    void Function(String status)? onStatus,
  }) async {
    final info = await _modelInfo(model);
    final mapped = _mapInput(model, info, mediaUrl, input);

    Future<Map<String, dynamic>> byVersion() async {
      final r2 = await _client
          .post(
            Uri.parse('$_base/predictions'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'version': info.versionId, 'input': mapped}),
          )
          .timeout(_timeout);
      return _decode(r2);
    }

    Map<String, dynamic> prediction;
    if (info.versionOnly && info.versionId != null) {
      prediction = await byVersion();
    } else {
      // Official models run on the model endpoint; community models need a
      // version id. Try the model endpoint first and fall back.
      final r1 = await _client
          .post(
            Uri.parse('$_base/models/${model.slug}/predictions'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'input': mapped}),
          )
          .timeout(_timeout);
      if (r1.statusCode >= 200 && r1.statusCode < 300) {
        prediction = _decode(r1);
      } else if (info.versionId != null &&
          r1.statusCode != 401 &&
          r1.statusCode != 402 &&
          r1.statusCode != 429) {
        prediction = await byVersion();
        info.versionOnly = true;
      } else {
        prediction = _decode(r1); // throws with a readable message
      }
    }

    final id = prediction['id'] as String?;
    if (id == null) throw AiException('The AI service did not start the job.');
    final started = DateTime.now();
    var pollErrors = 0;
    while (true) {
      final status = prediction['status'] as String? ?? 'starting';
      onStatus?.call(status);
      if (status == 'succeeded') return _outputs(prediction['output']);
      if (status == 'failed' || status == 'canceled') {
        final err = prediction['error']?.toString() ?? 'Processing failed.';
        throw AiException(err.contains('NSFW') || err.contains('flagged')
            ? 'This photo could not be processed. Try another one.'
            : err);
      }
      if (DateTime.now().difference(started) > _maxWait) {
        throw AiException('Processing is taking too long. Please try again.');
      }
      await Future<void>.delayed(_pollInterval);
      try {
        final r = await _client
            .get(Uri.parse('$_base/predictions/$id'), headers: _headers)
            .timeout(_timeout);
        prediction = _decode(r);
        pollErrors = 0;
      } catch (e) {
        // Tolerate brief network hiccups while polling.
        if (++pollErrors >= 5) rethrow;
      }
    }
  }

  List<String> _outputs(dynamic output) {
    final urls = <String>[];
    void walk(dynamic value) {
      if (value is String) {
        if (value.startsWith('http://') || value.startsWith('https://')) {
          urls.add(value);
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          walk(item);
        }
        return;
      }
      if (value is Map) {
        final direct = value['url'] ?? value['uri'];
        if (direct is String) {
          walk(direct);
          return;
        }
        for (final item in value.values) {
          walk(item);
        }
      }
    }

    walk(output);
    if (urls.isEmpty) throw AiException('The AI service returned no result.');
    return urls;
  }

  /// Downloads a result URL to a local file.
  Future<File> download(String url, File target) async {
    final r = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 3));
    if (r.statusCode != 200) {
      throw AiException('Could not download the result (${r.statusCode}).');
    }
    await target.writeAsBytes(r.bodyBytes, flush: true);
    return target;
  }
}
