import 'package:flutter/material.dart';

import '../services/app_state.dart';

/// One style inside an AI photo pack.
class PresetShot {
  final String title;
  final String prompt;
  final List<Color> colors;
  final IconData icon;

  /// Optional remote preview image. Leave null to show a gradient preview.
  final String? imageUrl;

  const PresetShot(this.title, this.prompt, this.colors, this.icon,
      {this.imageUrl});
}

class PresetPack {
  final String id;
  final String title;
  final String emoji;
  final bool trending;
  final List<PresetShot> shots;

  const PresetPack({
    required this.id,
    required this.title,
    required this.emoji,
    required this.shots,
    this.trending = true,
  });
}

String _subject(Gender g) => switch (g) {
      Gender.female => 'the woman',
      Gender.male => 'the man',
      Gender.other => 'the person',
    };

/// Builds the final instruction sent to the image-edit model.
String buildPresetPrompt(PresetShot shot, Gender gender) =>
    'Create a new professional photo of ${_subject(gender)} from this image: '
    '${shot.prompt}. Keep the exact same face, identity, skin tone and '
    'facial features. Photorealistic, high detail, natural skin texture.';

const _warm = [Color(0xFFE8274B), Color(0xFF6E0F2A)];
const _gold = [Color(0xFFFFB347), Color(0xFFB0123A)];
const _mono = [Color(0xFF8E8E8E), Color(0xFF1E1E1E)];
const _ocean = [Color(0xFFFF7E5F), Color(0xFF2B5876)];
const _pink = [Color(0xFFFF4F9A), Color(0xFF7A1FA2)];
const _blue = [Color(0xFF4A6CF7), Color(0xFF1B1464)];
const _ice = [Color(0xFFB8E1FF), Color(0xFF3B5B7A)];
const _green = [Color(0xFF7FB77E), Color(0xFF28402A)];

const List<PresetPack> presetPacks = [
  PresetPack(id: 'aesthetic', title: 'Aesthetic Photoshoot', emoji: '🎨', shots: [
    PresetShot('Cream Knit', 'soft studio portrait wearing a cream knit sweater, beige backdrop, soft window light', _gold, Icons.wb_sunny_outlined),
    PresetShot('Denim Mood', 'editorial portrait in an oversized denim jacket, white tank top, light grey studio', _blue, Icons.style_outlined),
    PresetShot('Red Turtleneck', 'fashion portrait in a red turtleneck against a deep red backdrop, dramatic light', _warm, Icons.local_fire_department_outlined),
    PresetShot('Faux Fur', 'glamorous portrait wearing a vivid blue faux fur coat, colorful studio', _blue, Icons.auto_awesome),
    PresetShot('Hot Pink Suit', 'high fashion portrait in a hot pink suit on a pink seamless backdrop', _pink, Icons.checkroom_outlined),
    PresetShot('Flower Wall', 'beauty portrait surrounded by large pink peonies, soft pastel light', _pink, Icons.local_florist_outlined),
  ]),
  PresetPack(id: 'spotlight', title: 'Spotlight Portraits', emoji: '📸', shots: [
    PresetShot('Neon Rim', 'moody portrait with pink and teal neon rim lighting, dark background', _pink, Icons.lightbulb_outline),
    PresetShot('Orange Glow', 'portrait lit by a warm orange spotlight with deep shadows', _gold, Icons.highlight_outlined),
    PresetShot('Noir', 'black and white spotlight portrait, high contrast, film noir style', _mono, Icons.contrast),
    PresetShot('Golden Hour', 'portrait in golden hour sunlight with lens flare', _gold, Icons.wb_twilight),
    PresetShot('Red Room', 'portrait in a room lit with deep red light, cinematic', _warm, Icons.movie_outlined),
    PresetShot('Halo', 'portrait with a soft circular spotlight halo behind the head, clean backdrop', _mono, Icons.blur_circular),
  ]),
  PresetPack(id: 'beach', title: 'Beach Sunset', emoji: '🌅', shots: [
    PresetShot('Shoreline', 'walking along the shoreline at sunset, warm pastel sky, linen outfit', _ocean, Icons.beach_access_outlined),
    PresetShot('Palm Silhouette', 'portrait at sunset with palm trees in the background, glowing light', _ocean, Icons.park_outlined),
    PresetShot('Boardwalk', 'relaxed portrait on a wooden boardwalk at dusk, summer outfit', _gold, Icons.deck_outlined),
    PresetShot('Waves', 'portrait standing in shallow waves, sunset reflection on water', _ocean, Icons.waves),
    PresetShot('Cliffside', 'portrait on a cliffside overlooking the ocean at sunset, wind in hair', _ocean, Icons.landscape_outlined),
    PresetShot('Bonfire', 'candid portrait by a beach bonfire at twilight, warm glow', _warm, Icons.local_fire_department_outlined),
  ]),
  PresetPack(id: 'modeling', title: 'Modeling Photoshoot', emoji: '📷', shots: [
    PresetShot('Monochrome', 'black and white fashion model shot, minimalist grey studio', _mono, Icons.camera_alt_outlined),
    PresetShot('Tailored', 'model posing in a tailored black suit, editorial lighting', _mono, Icons.business_center_outlined),
    PresetShot('Runway', 'runway fashion show photo, designer outfit, audience blurred', _warm, Icons.star_outline),
    PresetShot('Magazine', 'magazine cover style portrait, bold studio light, no text', _pink, Icons.menu_book_outlined),
    PresetShot('Streetwear', 'urban streetwear model photo, city street, shallow depth of field', _blue, Icons.location_city_outlined),
    PresetShot('Leather', 'fashion portrait wearing a black leather jacket, moody light', _mono, Icons.nightlife_outlined),
  ]),
  PresetPack(id: 'headshot', title: 'Casual Headshot', emoji: '💼', shots: [
    PresetShot('LinkedIn', 'professional corporate headshot, neutral grey backdrop, soft light, business casual', _blue, Icons.work_outline),
    PresetShot('Office', 'friendly headshot in a modern bright office, blurred background', _blue, Icons.apartment_outlined),
    PresetShot('Outdoor', 'natural outdoor headshot in a park, soft daylight, smart casual', _green, Icons.nature_people_outlined),
    PresetShot('Cafe', 'casual headshot in a cozy cafe, warm tones', _gold, Icons.local_cafe_outlined),
    PresetShot('Studio White', 'clean headshot on a pure white background, even lighting', _mono, Icons.crop_square),
    PresetShot('Creative', 'creative professional headshot against a colorful painted wall', _pink, Icons.palette_outlined),
  ]),
  PresetPack(id: 'winter', title: 'Winter Wonderland', emoji: '❄️', shots: [
    PresetShot('Snowfall', 'portrait in gently falling snow, cozy winter coat and scarf', _ice, Icons.ac_unit),
    PresetShot('Cabin', 'portrait by a wooden cabin window with warm lights, winter evening', _gold, Icons.cabin_outlined),
    PresetShot('Ski Resort', 'portrait at a ski resort with snowy mountains, ski jacket', _ice, Icons.downhill_skiing),
    PresetShot('Holiday Lights', 'portrait with bokeh holiday lights, festive sweater', _warm, Icons.celebration_outlined),
    PresetShot('Frozen Lake', 'portrait standing on a frozen lake, pastel winter sky', _ice, Icons.water_outlined),
    PresetShot('Hot Cocoa', 'candid portrait holding hot cocoa by a fireplace', _warm, Icons.coffee_outlined),
  ]),
];

/// AI Filters.
class AiFilter {
  final String id;
  final String name;
  final String prompt;
  final List<Color> colors;
  final IconData icon;
  final String demoLook;
  final bool pro;

  const AiFilter(this.id, this.name, this.prompt, this.colors, this.icon,
      {this.demoLook = 'warm', this.pro = false});
}

const List<AiFilter> aiFilters = [
  AiFilter('anime', 'Anime', 'Turn this photo into a high quality anime illustration, keep the composition and the person\'s features', _pink, Icons.auto_awesome, demoLook: 'vivid'),
  AiFilter('3d', '3D Cartoon', 'Turn this photo into a cute 3D animated movie character render, soft lighting, keep likeness', _blue, Icons.view_in_ar_outlined, demoLook: 'vivid'),
  AiFilter('oil', 'Oil Painting', 'Turn this photo into a classical oil painting with visible brush strokes', _gold, Icons.brush_outlined, demoLook: 'warm'),
  AiFilter('watercolor', 'Watercolor', 'Turn this photo into a delicate watercolor painting on textured paper', _ocean, Icons.water_drop_outlined, demoLook: 'cool'),
  AiFilter('sketch', 'Pencil Sketch', 'Turn this photo into a detailed graphite pencil sketch', _mono, Icons.edit_outlined, demoLook: 'mono'),
  AiFilter('comic', 'Comic Book', 'Turn this photo into a bold comic book illustration with ink outlines and halftone shading', _warm, Icons.menu_book_outlined, demoLook: 'vivid'),
  AiFilter('cyberpunk', 'Cyberpunk', 'Restyle this photo as a cyberpunk scene with neon lights and futuristic city vibes', _pink, Icons.bolt_outlined, demoLook: 'cool', pro: true),
  AiFilter('vintage', 'Vintage Film', 'Make this photo look like a 1970s vintage film photograph with grain and faded colors', _gold, Icons.camera_roll_outlined, demoLook: 'warm'),
  AiFilter('clay', 'Clay Figure', 'Turn this photo into a claymation figure scene, handcrafted plasticine look', _gold, Icons.emoji_people_outlined, demoLook: 'warm', pro: true),
  AiFilter('pixel', 'Pixel Art', 'Turn this photo into detailed 16-bit pixel art', _green, Icons.grid_on, demoLook: 'vivid', pro: true),
  AiFilter('royal', 'Royal Portrait', 'Turn this photo into a Renaissance royal portrait painting with regal clothing', _warm, Icons.workspace_premium_outlined, demoLook: 'warm', pro: true),
  AiFilter('bw', 'Studio B&W', 'Turn this photo into an elegant black and white studio portrait', _mono, Icons.contrast, demoLook: 'mono'),
];

/// Extra one-tap tools (All Tools sheet).
const colorizePrompt =
    'Colorize this black and white photo with natural, realistic colors. '
    'Restore it, remove scratches and keep all details and faces identical.';
