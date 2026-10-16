import 'dart:typed_data';

import 'widget.dart';
import 'models.dart';

/// Programmatic controller for the [Interactive3d] widget.
///
/// Attach to a widget via [Interactive3d.controller]. The controller
/// forwards calls to the underlying platform view (iOS) or texture
/// renderer (Android) through [Interactive3dState].
///
/// ```dart
/// final controller = Interactive3dController();
///
/// Interactive3d(
///   controller: controller,
///   modelPath: 'assets/model.glb',
/// );
///
/// // Later:
/// await controller.clearSelections();
/// ```
class Interactive3dController {
  Interactive3dState? _state;

  /// Attaches to the given [Interactive3dState]. Called automatically
  /// by the widget, do not call manually.
  void attach(Interactive3dState state) {
    _state = state;
  }

  /// Detaches if currently attached to [state], or unconditionally if [state]
  /// is null. The identity check guards against an old state's dispose
  /// stomping a new state's attach when the widget rebuilds with a new key.
  void detach([Interactive3dState? state]) {
    if (state == null || identical(_state, state)) {
      _state = null;
    }
  }

  void _ensureAttached() {
    if (_state == null) {
      throw StateError('Interactive3dController is not attached to a widget');
    }
  }

  /// Unselects specific entities by ID, or all if [entityIds] is null.
  Future<void> unselectEntities({List<int>? entityIds}) async {
    _ensureAttached();
    await _state!.unselectEntities(entityIds: entityIds);
  }

  /// Clears all current selections.
  Future<void> clearSelections() async {
    await unselectEntities();
  }

  /// Sets the camera zoom level. Values above 1.0 zoom in, below zoom out.
  Future<void> setCameraZoomLevel(double zoomLevel) async {
    _ensureAttached();
    await _state!.setZoom(zoomLevel);
  }

  /// Toggles visibility for a group of model parts.
  Future<void> updatePartGroupConfig({
    required bool isVisible,
    required ModelPartGroup group,
  }) async {
    _ensureAttached();
    await _state!.updatePartGroupConfig(isVisible: isVisible, group: group);
  }

  /// Clears the persistent selection cache for the current model.
  Future<void> clearCache() async {
    _ensureAttached();
    await _state!.clearCache();
  }

  /// Re-applies cache highlight colors to all cached entities.
  Future<void> refreshCacheHighlights() async {
    _ensureAttached();
    await _state!.refreshCacheHighlights();
  }

  /// Removes specific entities from the persistent cache by name.
  Future<void> removeFromCache(List<String> names) async {
    _ensureAttached();
    await _state!.removeFromCache(names);
  }

  /// Applies a persistent PBR override to a single entity.
  /// Null fields keep their prior value; pass any combination of fields.
  Future<void> setEntityMaterial({
    required String name,
    List<double>? color,
    double? metallic,
    double? roughness,
    List<double>? emissive,
  }) async {
    _ensureAttached();
    await _state!.setEntityMaterials([
      MaterialOverride(
        name: name,
        color: color,
        metallic: metallic,
        roughness: roughness,
        emissive: emissive,
      ),
    ]);
  }

  /// Applies persistent PBR overrides to many entities in one call.
  Future<void> setEntityMaterials(List<MaterialOverride> overrides) async {
    _ensureAttached();
    await _state!.setEntityMaterials(overrides);
  }

  /// Removes the override on [name], restoring the GLB original.
  Future<void> resetEntityMaterial(String name) async {
    _ensureAttached();
    await _state!.resetEntityMaterials([name]);
  }

  /// Removes all active overrides, restoring every overridden entity.
  Future<void> resetAllMaterialOverrides() async {
    _ensureAttached();
    await _state!.resetEntityMaterials(null);
  }

  /// Applies a runtime base-color texture to [name] from PNG/JPEG [bytes].
  /// Merges into the entity's override state; an existing color tints it.
  Future<void> setEntityTexture({
    required String name,
    required Uint8List bytes,
  }) async {
    _ensureAttached();
    await _state!.setEntityTextures([EntityTexture(name: name, bytes: bytes)]);
  }

  /// Applies runtime base-color textures to many entities in one call.
  Future<void> setEntityTextures(List<EntityTexture> textures) async {
    _ensureAttached();
    await _state!.setEntityTextures(textures);
  }

  /// Removes the runtime texture on [name], keeping any other active overrides.
  Future<void> resetEntityTexture(String name) async {
    _ensureAttached();
    await _state!.resetEntityTextures([name]);
  }

  /// Removes all runtime textures, keeping any non-texture overrides.
  Future<void> resetAllEntityTextures() async {
    _ensureAttached();
    await _state!.resetEntityTextures(null);
  }
}
