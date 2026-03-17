import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';

/// Platform interface for the interactive_3d plugin.
///
/// Defines the contract that platform-specific implementations must fulfil.
/// Currently only [MethodChannelInteractive3d] (Android Texture API) implements
/// this interface. iOS uses a PlatformView with its own method channel.
abstract class Interactive3dPlatform extends PlatformInterface {
  Interactive3dPlatform() : super(token: _token);

  static final Object _token = Object();

  static void verify(Interactive3dPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
  }

  /// Creates a GPU-backed texture and returns `{'textureId': int}`.
  Future<Map<String, dynamic>> createTexture({
    required int width,
    required int height,
  });

  /// Releases the texture and all associated native resources.
  Future<void> disposeTexture(int textureId);

  /// Loads a 3D model into the renderer bound to [textureId].
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
    List<double>? backgroundColor,
  });

  /// Loads IBL and skybox environment lighting.
  Future<void> loadEnvironment({
    required int textureId,
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  });

  /// Loads an HDR/EXR background (iOS only).
  Future<void> loadHdrBackground({
    required int textureId,
    String? backgroundPath,
    String? backgroundUrl,
  });

  /// Sets the camera zoom level.
  Future<void> setCameraZoomLevel(int textureId, double zoom);

  /// Toggles visibility for a group of model parts.
  Future<void> updatePartGroupConfig({
    required int textureId,
    required bool isVisible,
    required ModelPartGroup group,
  });

  /// Unselects entities by ID, or all if [entityIds] is null.
  Future<void> unselectEntities({
    required int textureId,
    List<int>? entityIds,
  });

  /// Clears the persistent selection cache.
  Future<void> clearCache(int textureId);

  /// Re-applies cache highlight colors.
  Future<void> refreshCacheHighlights(int textureId);

  /// Removes specific entities from the cache by name.
  Future<void> removeFromCache(int textureId, List<String> names);

  /// Forwards a touch event to the native renderer.
  Future<void> onTouchEvent({
    required int textureId,
    required String action,
    double? x,
    double? y,
    double? deltaX,
    double? deltaY,
    double? scale,
  });

  /// Stream of selection changes for a given texture.
  Stream<List<EntityData>> selectionStream(int textureId);

  /// Stream of cache selection changes for a given texture.
  Stream<List<String>> cacheSelectionStream(int textureId);
}