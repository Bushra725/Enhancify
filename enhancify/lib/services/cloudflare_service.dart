import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'replicate_service.dart' show AiException;

/// A photo prepared for the free provider: small PNG + original aspect ratio.
class CfInput {
  final Uint8List png;
  final double aspect; // width / height
  const CfInput(this.png, this.aspect);
}

/// FREE AI provider: your Cloudflare Worker (see /cloudflare) running
/// FLUX.2 [klein] on Workers AI's free daily allocation.
class CloudflareService {
  CloudflareService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Workers AI requires input images smaller than 512x512.
  static const int maxInputSide = 496;

  /// Output long side (1024 keeps the cost ≈110 neurons per image).
  static const int _outputLongSide = 1024;

  String get _endpoint {
    final b = AppConfig.cfWorkerUrl.endsWith('/')
        ? AppConfig.cfWorkerUrl.substring(0, AppConfig.cfWorkerUrl.length - 1)
        : AppConfig.cfWorkerUrl;
    return '$b/v1/edit';
  }

  /// Downscales an encoded image to a PNG with long side <= [maxInputSide].
  /// Reads the size from the header first, so huge photos are never fully
  /// decoded. Throws [AiException] if the format can't be decoded.
  static Future<CfInput> shrink(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) throw AiException('Could not read this image.');
      final longSide = w > h ? w : h;
      var tw = w;
      var th = h;
      if (longSide > maxInputSide) {
        tw = (w * maxInputSide / longSide).floor();
        th = (h * maxInputSide / longSide).floor();
        if (tw < 1) tw = 1;
        if (th < 1) th = 1;
      }
      codec = await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw AiException('Could not read this image.');
      return CfInput(data.buffer.asUint8List(), w / h);
    } on AiException {
      rethrow;
    } catch (_) {
      throw AiException('Could not read this image.');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static int _mult16(double v) {
    final n = (v / 16).round() * 16;
    return n < 256 ? 256 : (n > _outputLongSide ? _outputLongSide : n);
  }

  /// Edits / restores / restyles with a text instruction. [inputs] are 1-4
  /// reference photos; the first one sets the output aspect ratio.
  /// Retries once if the Worker says "too many requests".
  Future<Uint8List> edit(List<CfInput> inputs, String prompt) async {
    if (inputs.isEmpty) throw AiException('No image.');
    for (var attempt = 0;; attempt++) {
      final r = await _send(_buildRequest(inputs, prompt));
      if (r.statusCode == 429 && attempt == 0) {
        await Future<void>.delayed(const Duration(seconds: 15));
        continue;
      }
      return _parse(r);
    }
  }

  /// Text-to-image (no input photo), e.g. AI backgrounds. [aspect] is
  /// width / height of the result.
  Future<Uint8List> generate(String prompt, {double aspect = 9 / 16}) async {
    for (var attempt = 0;; attempt++) {
      final r = await _send(_buildRequest(const [], prompt, aspect: aspect));
      if (r.statusCode == 429 && attempt == 0) {
        await Future<void>.delayed(const Duration(seconds: 15));
        continue;
      }
      return _parse(r);
    }
  }

  http.MultipartRequest _buildRequest(List<CfInput> inputs, String prompt, {double? aspect}) {
    final req = http.MultipartRequest('POST', Uri.parse(_endpoint));
    if (AppConfig.cfAppKey.isNotEmpty) {
      req.headers['x-app-key'] = AppConfig.cfAppKey;
    }
    for (var i = 0; i < inputs.length && i < 4; i++) {
      req.files.add(http.MultipartFile.fromBytes('image', inputs[i].png,
          filename: 'input_$i.png'));
    }
    final a = aspect ?? (inputs.isEmpty ? 1.0 : inputs.first.aspect);
    final width = a >= 1 ? _outputLongSide : _mult16(_outputLongSide * a);
    final height = a >= 1 ? _mult16(_outputLongSide / a) : _outputLongSide;
    req.fields['prompt'] = prompt;
    req.fields['width'] = '$width';
    req.fields['height'] = '$height';
    return req;
  }

  Uint8List _parse(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      body = {};
    }
    if (r.statusCode != 200) {
      if (r.statusCode == 401) {
        throw AiException('AI server rejected the app key. Check CF_APP_KEY.');
      }
      throw AiException(
          body['detail']?.toString() ?? 'AI error (${r.statusCode}).');
    }
    final b64 = body['image'];
    if (b64 is! String || b64.isEmpty) {
      throw AiException('The AI returned no image.');
    }
    try {
      var raw = b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64;
      raw = raw.replaceAll(RegExp(r'\s'), '');
      return base64Decode(base64.normalize(raw));
    } on FormatException {
      throw AiException('The AI returned an invalid image.');
    }
  }

  Future<http.Response> _send(http.MultipartRequest req) async {
    try {
      final streamed = await _client.send(req);
      return await http.Response.fromStream(streamed)
          .timeout(const Duration(minutes: 2));
    } on SocketException {
      throw AiException('No internet connection.');
    } on TimeoutException {
      throw AiException('The AI server did not respond. Please try again.');
    } on http.ClientException {
      throw AiException('Could not reach the AI server.');
    }
  }
}
