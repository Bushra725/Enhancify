/// Replicate models used by the app.
///
/// The service looks up each model's latest version and input schema at
/// runtime, so you can swap a model here without touching any other code.
/// `mediaKey` is the input that receives the uploaded photo / video. If the
/// model uses a different name, the service automatically falls back to the
/// first URI-typed input in the model's schema.
class AiModel {
  final String owner;
  final String name;
  final String mediaKey;
  final Map<String, dynamic> defaults;

  const AiModel({
    required this.owner,
    required this.name,
    required this.mediaKey,
    this.defaults = const {},
  });

  String get slug => '$owner/$name';
}

class AiModels {
  AiModels._();

  /// Face restoration + background enhancement + upscale.
  static const faceEnhance = AiModel(
    owner: 'sczhou',
    name: 'codeformer',
    mediaKey: 'image',
    defaults: {
      'codeformer_fidelity': 0.7,
      'background_enhance': true,
      'face_upsample': true,
      'upscale': 2,
    },
  );

  /// General upscaler (Ultra / 4x).
  static const upscale = AiModel(
    owner: 'nightmareai',
    name: 'real-esrgan',
    mediaKey: 'image',
    defaults: {'scale': 4, 'face_enhance': true},
  );

  /// Stable Diffusion avatars from one face photo (InstantID).
  static const avatar = AiModel(
    owner: 'fofr',
    name: 'face-to-many',
    mediaKey: 'image',
    defaults: {
      'style': '3D',
      'denoising_strength': 0.5,
      'instant_id_strength': 0.8,
      'prompt_strength': 4.5,
    },
  );

  /// Instruction-based image editing: AI Filters, AI Photos, Colorize.
  static const imageEdit = AiModel(
    owner: 'black-forest-labs',
    name: 'flux-kontext-pro',
    mediaKey: 'input_image',
    defaults: {
      'aspect_ratio': 'match_input_image',
      'output_format': 'jpg',
      'safety_tolerance': 2,
    },
  );

  /// Video upscaler (Pro).
  static const videoEnhance = AiModel(
    owner: 'lucataco',
    name: 'real-esrgan-video',
    mediaKey: 'video_path',
    defaults: {},
  );

  static const all = [faceEnhance, upscale, imageEdit, avatar, videoEnhance];
}
