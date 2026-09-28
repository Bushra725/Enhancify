import 'package:flutter/material.dart';

/// A ready-made scene bundled with the app (assets/backgrounds).
class BgScene {
  const BgScene(this.id, this.label, this.category);
  final String id;
  final String label;
  final String category;
  String get asset => 'assets/backgrounds/$id.jpg';

  /// All bundled scenes are 1080 × 1920.
  double get aspect => 9 / 16;
}

/// Original illustrated scenes (drawn by tool/art/backgrounds.py).
const bgScenes = <BgScene>[
  BgScene('white_blossom_wall', 'Blossom wall', 'Floral walls'),
  BgScene('pink_blossom_brick', 'Pink blossom brick', 'Floral walls'),
  BgScene('bougainvillea_street', 'Bougainvillea gate', 'Floral walls'),
  BgScene('rose_wall_bench', 'Rose wall & bench', 'Garden'),
  BgScene('orange_arch', 'Orange vine arch', 'Garden'),
  BgScene('warm_interior', 'Warm lounge', 'Cozy interiors'),
  BgScene('rattan_sunroom', 'Rattan sunroom', 'Cozy interiors'),
  BgScene('leaf_shadow_cream', 'Leaf shadows', 'Sunlight'),
  BgScene('skyline_pool', 'Skyline pool', 'City'),
  BgScene('city_plaza', 'City plaza', 'City'),
  BgScene('sail_tower_path', 'Sail tower walk', 'City'),
  BgScene('birthday_roses', 'Birthday roses', 'Birthday'),
  BgScene('birthday_torn_paper', 'Birthday note', 'Birthday'),
];

List<String> get bgSceneCategories {
  final out = <String>[];
  for (final s in bgScenes) {
    if (!out.contains(s.category)) out.add(s.category);
  }
  return out;
}

/// Soft gradients (top → bottom).
const bgGradients = <(String, List<Color>)>[
  ('Blush', [Color(0xFFFFE3EF), Color(0xFFFFB6D3)]),
  ('Peach', [Color(0xFFFFE8D6), Color(0xFFFFB38A)]),
  ('Lavender', [Color(0xFFEDE4FF), Color(0xFFB892FF)]),
  ('Mint', [Color(0xFFE3FFF6), Color(0xFF7ED9C0)]),
  ('Sky', [Color(0xFFDDF0FF), Color(0xFF6FA3D8)]),
  ('Sunset', [Color(0xFFFFD27A), Color(0xFFEA026A)]),
  ('Sand', [Color(0xFFF7F1E3), Color(0xFFD9C3A0)]),
  ('Cloud', [Color(0xFFFFFFFF), Color(0xFFE6E6EA)]),
  ('Berry', [Color(0xFFEA026A), Color(0xFF5C0A33)]),
  ('Night', [Color(0xFF2A2F45), Color(0xFF0E1020)]),
];

/// AI background themes (free Cloudflare generator). Prompts ask for an
/// empty scene so the person can be placed in it.
class AiBgTheme {
  const AiBgTheme(this.label, this.icon, this.prompt);
  final String label;
  final IconData icon;
  final String prompt;
}

const _suffix = ' Empty scene with open space in the lower middle for a person to stand. '
    'No people, no animals, no text, no watermark. Photorealistic, soft natural light, '
    'sharp detail, vertical phone wallpaper composition.';

const aiBgThemes = <AiBgTheme>[
  AiBgTheme('White bougainvillea', Icons.local_florist,
      'A white painted garden wall with lush white bougainvillea cascading over the top, green leaves, '
      'a few white petals fallen on a wet street after rain.$_suffix'),
  AiBgTheme('Climbing roses', Icons.spa,
      'A white wall covered with climbing red roses and green vines, dappled sunlight and leaf shadows on the wall, '
      'a curved white stone bench and round boxwood shrubs.$_suffix'),
  AiBgTheme('Orange tree arch', Icons.circle,
      'A white Mediterranean wall with an arched niche framed by a vine of small oranges, soft leaf shadows, '
      'pale stone floor tiles, fallen oranges.$_suffix'),
  AiBgTheme('Warm plant lounge', Icons.light,
      'A warm beige plaster room with glowing brass wall lights and pendant bulbs, trailing ivy from the ceiling, '
      'potted green plants, golden sunlight patches on the floor.$_suffix'),
  AiBgTheme('Rattan sunroom', Icons.chair,
      'A sunlit room with a wooden lattice screen, bamboo palms, a round rattan chair and woven vases, '
      'long stripes of sunlight across a light wood floor.$_suffix'),
  AiBgTheme('Pink blossom brick', Icons.filter_vintage,
      'A white painted brick wall with pale pink blossom vines hanging from the top, soft overcast light.$_suffix'),
  AiBgTheme('Leaf shadows', Icons.wb_sunny,
      'A plain warm cream wall with soft shadows of leaves and window blinds, a few green leafy branches in the corners, '
      'golden hour light.$_suffix'),
  AiBgTheme('Skyline pool', Icons.pool,
      'A rooftop infinity pool with clear turquoise water in the foreground and a futuristic city skyline with a very tall '
      'needle-like skyscraper under a hazy blue sky.$_suffix'),
  AiBgTheme('Downtown plaza', Icons.location_city,
      'A wide modern city plaza with pale stone tiles, a very tall silver skyscraper, palm trees and a fountain, '
      'bright blue sky with light clouds.$_suffix'),
  AiBgTheme('Sail hotel walk', Icons.sailing,
      'A curving paved garden walkway lined with palms and green hedges leading toward a white sail-shaped luxury '
      'hotel tower, deep blue sky.$_suffix'),
  AiBgTheme('Birthday roses', Icons.cake,
      'A flat lay birthday backdrop: a soft cream surface with vivid magenta roses and scattered petals along the left '
      'edge, lots of clean empty space.$_suffix'),
  AiBgTheme('Birthday paper', Icons.celebration,
      'A soft pink torn handmade paper note on white, decorated with delicate pink lilies in two corners, '
      'lots of clean empty space.$_suffix'),
  AiBgTheme('Beach sunset', Icons.beach_access,
      'A calm tropical beach at sunset with gentle waves, warm pink and orange sky, palm silhouettes.$_suffix'),
  AiBgTheme('Cherry blossoms', Icons.park,
      'A quiet park path under blooming pink cherry blossom trees, petals in the air, soft spring light.$_suffix'),
  AiBgTheme('Paris street', Icons.storefront,
      'A charming European street with cream stone buildings, iron balconies with flowers and a small café, '
      'morning light.$_suffix'),
  AiBgTheme('Studio', Icons.photo_camera_back,
      'A professional photo studio backdrop with a smooth seamless blush pink paper and soft even lighting.$_suffix'),
];
