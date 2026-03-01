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
  /// by the widget — do not call manually.
  void attach(Interactive3dState state) {
    _state = state;
  }

  /// Detaches from the state. Called automatically on dispose.
  void detach() {
    _state = null;
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
}