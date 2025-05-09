
import 'interactive_3d.dart';

/// A controller for interacting with the [Interactive3d] widget.
class Interactive3dController {
  Interactive3dState? _state;

  /// Attaches the controller to the given [Interactive3dState].
  void attach(Interactive3dState state) {
    _state = state;
  }

  /// Detaches the controller from the state.
  void detach() {
    _state = null;
  }

  /// Unselects specific entities or all entities in the 3D model.
  Future<void> unselectEntities({List<int>? entityIds}) async {
    if (_state == null) {
      throw StateError('Interactive3dController is not attached to a widget');
    }
    await _state!.unselectEntities(entityIds: entityIds);
  }

  /// Clears all selected entities in the 3D model.
  Future<void> clearSelections() async {
    await unselectEntities();
  }
}