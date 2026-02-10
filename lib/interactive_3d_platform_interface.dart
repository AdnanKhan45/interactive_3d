import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'interactive_3d.dart';
import 'dart:async';
import 'dart:typed_data';

/// Platform interface for the Interactive3d plugin.
///
/// This interface defines the contract for texture-based 3D rendering
/// using Flutter's SurfaceProducer API.
abstract class Interactive3dPlatform extends PlatformInterface {
  Interactive3dPlatform() : super(token: _token);

  static final Object _token = Object();

  static void verify(Interactive3dPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
  }

  /// Creates a new texture for 3D rendering.
  /// Returns a map containing 'textureId'.
  Future<Map<String, dynamic>> createTexture({
    required int width,
    required int height,
  });

  /// Disposes a texture and releases all associated resources.
  Future<void> disposeTexture(int textureId);

  /// Loads a 3D model into the specified texture.
  Future<void> loadModel({
    required int textureId,
    String? modelPath,
    String? modelUrl,
    required Map<String, ByteData> resources,
    List<String>? preselectedEntities,
    List<double>? selectionColor,
    List<PatchColor>? patchColors,
    bool enableCache = false,
    List<double>? cacheColor,
    bool clearSelectionsOnHighlight = false,
    List<SequenceConfig>? selectionSequence,
  });

  /// Loads environment lighting into the specified texture.
  Future<void> loadEnvironment({
    required int textureId,
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  });

  /// Loads HDR/EXR background for iOS.
  Future<void> loadHdrBackground({
    required int textureId,
    String? backgroundPath,
    String? backgroundUrl,
  });

  /// Sets the camera zoom level.
  Future<void> setCameraZoomLevel(int textureId, double zoom);

  /// Updates visibility for a model part group.
  Future<void> updatePartGroupConfig({
    required int textureId,
    required bool isVisible,
    required ModelPartGroup group,
  });

  /// Unselects entities in the 3D model.
  Future<void> unselectEntities({required int textureId, List<int>? entityIds});

  /// Clears the selection cache.
  Future<void> clearCache(int textureId);

  /// Refreshes cache highlights.
  Future<void> refreshCacheHighlights(int textureId);

  /// Removes specific entities from cache.
  Future<void> removeFromCache(int textureId, List<String> names);

  /// Sends a touch event to the native side.
  Future<void> onTouchEvent({
    required int textureId,
    required String action,
    double? x,
    double? y,
    double? deltaX,
    double? deltaY,
    double? scale,
  });

  /// Stream to receive selection changes for a specific texture.
  Stream<List<EntityData>> selectionStream(int textureId);

  /// Stream to receive cached selection changes for a specific texture.
  Stream<List<String>> cacheSelectionStream(int textureId);
}