/// Asset paths and part names shared by the demo pages.
abstract final class DemoAssets {
  static const toothGlb = 'assets/models/Tooth-3.glb';
  static const toothGltf = 'assets/models/Tooth-2.gltf';
  static const toothGltfResources = [
    'scene.bin',
    'textures/mouth_baseColor.png',
    'textures/mouth_metallicRoughness.png',
    'textures/mouth_normal.png',
    'textures/teeth_baseColor.png',
    'textures/teeth_metallicRoughness.png',
    'textures/teeth_normal.png',
  ];

  static const bridgeIbl = 'assets/models/giuseppe_bridge_4k_ibl.ktx';
  static const bridgeSkybox = 'assets/models/giuseppe_bridge_4k_skybox.ktx';
  static const bridgeHdr = 'assets/models/san_giuseppe_bridge_4k.hdr';
  static const venetianIbl = 'assets/models/venetian_crossroads_2k_ibl.ktx';
  static const venetianSkybox =
      'assets/models/venetian_crossroads_2k_skybox.ktx';

  static const teethTexture = 'assets/models/textures/teeth_baseColor.png';
  static const mouthTexture = 'assets/models/textures/mouth_baseColor.png';

  static const helmetUrl =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb';

  /// Explicit so demos look the same on both platforms (defaults differ).
  static const selectionBlue = [0.0, 0.6, 1.0, 1.0];

  static final lowerTeeth = List.generate(16, (i) => 'Teeth_Lower_${i + 1}');
  static final upperTeeth = List.generate(16, (i) => 'Teeth_Upper_${i + 1}');
  static const jaws = [
    'Lower_Jaw_L',
    'Lower_Jaw_R',
    'Upper_Jaw_L',
    'Upper_Jaw_R',
  ];
  static const tongue = [
    'Tounge_Lower_L',
    'Tounge_Lower_R',
    'Tounge_Upper_L',
    'Tounge_Upper_R',
  ];
  static const palate = [
    'Hard_Plate_L',
    'Hard_Plate_R',
    'Soft_Plate_L',
    'Soft_Plate_R',
  ];
}
