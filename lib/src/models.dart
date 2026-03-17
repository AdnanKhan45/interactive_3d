/// Data models used by the interactive_3d plugin.
///
/// These classes define configuration objects and data types shared between
/// the widget, controller, and platform channel layers.
library;

/// Configuration for ordered entity selection within a named group.
///
/// When [selectionSequence] is provided to [Interactive3d], taps are
/// constrained so entities can only be selected in the order defined by
/// [order]. If [bidirectional] is true, selection can proceed in either
/// direction from the current position.
class SequenceConfig {
  final String group;
  final List<String> order;
  final bool bidirectional;
  final String? tiedGroup;

  SequenceConfig({
    required this.group,
    required this.order,
    this.bidirectional = false,
    this.tiedGroup,
  });

  Map<String, dynamic> toJson() => {
    'group': group,
    'order': order,
    'bidirectional': bidirectional,
    if (tiedGroup != null) 'tiedGroup': tiedGroup,
  };
}

/// Per-entity color override for selection and preselection highlights.
///
/// When a [PatchColor] matches a tapped entity by [name], its [color]
/// is used instead of the global [Interactive3d.selectionColor].
class PatchColor {
  /// Node name in the 3D model (e.g. 'Tooth_1', 'Gum_Upper').
  final String name;

  /// RGBA values in the range 0.0–1.0.
  final List<double> color;

  PatchColor({required this.name, required this.color});
}

/// A named group of model parts whose visibility can be toggled together.
class ModelPartGroup {
  /// Display label shown in the UI.
  final String title;

  /// Node names in the 3D model (e.g. 'Tooth_1', 'Gum_1').
  final List<String> names;

  ModelPartGroup({required this.title, required this.names});

  Map<String, dynamic> toMap() => {
    'title': title,
    'names': names,
  };
}

/// Identifies a single entity in the loaded 3D model.
class EntityData {
  /// Filament entity ID (Android) or SceneKit hash (iOS).
  final int id;

  /// Node name as defined in the glTF/GLB file.
  final String name;

  EntityData({required this.id, required this.name});
}