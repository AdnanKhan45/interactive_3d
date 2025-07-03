import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'interactive_3d.dart';
import 'dart:async';
import 'dart:typed_data';

abstract class Interactive3dPlatform extends PlatformInterface {
  Interactive3dPlatform() : super(token: _token);

  static final Object _token = Object();

  static void verify(Interactive3dPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
  }

  /// Method to load the model from assets or network.
  /// [resources] is empty for .glb models and populated for .gltf models.
  Future<void> loadModel({
    String? modelPath,
    String? modelUrl,
    required Map<String, ByteData> resources,
    List<String>? preselectedEntities,
    List<double>? selectionColor,
    List<PatchColor>? patchColors, // Add patchColors
    bool enableCache = false,
    List<double>? cacheColor,
    bool clearSelectionsOnHighlight = false,
  });

  /// Method to load the environment from assets or network URLs.
  Future<void> loadEnvironment({
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  });

  /// Method to set the camera position.
  Future<void> setCameraZoomLevel(double zoom);

  /// Method to set the camera position.
  Future<void> updatePartGroupConfig({required bool isVisible, required ModelPartGroup group});

  /// Method to unselect entities in the 3D model.
  Future<void> unselectEntities({List<int>? entityIds});

  /// Method to clear all selected entities in the 3D model.
  Future<void> clearCache();

  /// Method to refresh the cache highlights for a specific view.
  Future<void> refreshCacheHighlights();

  /// Method to clear specific cached entities
  Future<void> removeFromCache(List<String> names);

  // Load HDR or EXR background for iOS
  Future<void> loadHdrBackground({
    String? backgroundPath,
    String? backgroundUrl,
  });

  /// Stream to receive selection changes.
  Stream<List<EntityData>> get selectionStream;

  /// Stream to receive cached selection changes.
  Stream<List<String>> get cacheSelectionStream;

}