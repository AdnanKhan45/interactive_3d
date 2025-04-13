import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'interactive_3d_method_channel.dart';
import 'interactive_3d_platform_interface.dart';
import 'dart:io';

class Interactive3d extends StatefulWidget {
  /// Path to the 3D model file (e.g., `.glb` or `.gltf`) to be loaded.
  final String modelPath;

  /// Path to the Image-Based Lighting (IBL) file used for rendering the 3D model.
  final String iblPath;

  /// Path to the skybox texture file used for the 3D environment.
  final String skyboxPath;

  /// A list of additional resource file paths required for `.gltf` models (e.g., textures, binary files).
  /// Defaults to an empty list.
  final List<String> resources;

  /// Callback function triggered when the selection of entities in the 3D model changes.
  /// It provides a list of selected entities.
  final void Function(List<EntityData>)? onSelectionChanged;

  /// A list of entity names to be preselected when the model is loaded.
  final List<String>? preselectedEntities;

  /// A list of RGBA values (0.0 to 1.0) representing the color used to highlight selected entities.
  final List<double>? selectionColor;

  /// The initial zoom level of the camera when the 3D model is loaded.
  final double? defaultZoom;

  /// Constructor for the `Interactive3d` widget.
  const Interactive3d({
    super.key,
    required this.modelPath,
    required this.iblPath,
    required this.skyboxPath,
    this.onSelectionChanged,
    this.resources = const [],
    this.preselectedEntities,
    this.selectionColor,
    this.defaultZoom,
  });

  @override
  Interactive3dState createState() => Interactive3dState();
}

/// State class for the `Interactive3d` widget.
class Interactive3dState extends State<Interactive3d> {
  /// Platform-specific implementation for interacting with the 3D viewer.
  Interactive3dPlatform? _platform;

  /// ID of the platform view.
  int _viewId = -1;

  /// Subscription to the selection stream for listening to selection changes.
  StreamSubscription<List<EntityData>>? _selectionSubscription;

  @override
  Widget build(BuildContext context) {
    // Render the platform-specific view (iOS or Android).
    if (Platform.isIOS) {
      return UiKitView(
        viewType: 'interactive_3d',
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: _creationParams(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      return AndroidView(
        key: const ValueKey('interactive_3d'),
        viewType: 'interactive_3d',
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
  }

  /// Creates the parameters to be passed to the platform view.
  dynamic _creationParams() {
    return {
      'modelPath': widget.modelPath,
      'iblPath': widget.iblPath,
      'skyboxPath': widget.skyboxPath,
      'resources': widget.resources,
    };
  }

  /// Called when the platform view is created.
  /// Initializes the platform interface and loads the model and environment.
  Future<void> _onPlatformViewCreated(int id) async {
    _viewId = id;
    _platform = MethodChannelInteractive3d(_viewId);
    Interactive3dPlatform.verify(_platform!);

    // Listen for selection changes.
    _selectionSubscription = _platform!.selectionStream.listen(_onSelectionChanged);

    // Create resources if needed (for .gltf only).
    Map<String, ByteData> resources = {};
    if (widget.modelPath.endsWith('.gltf')) {
      resources = await _loadGltfResources(widget.modelPath);
    }

    // Load the model.
    await _platform!.loadModel(
      widget.modelPath,
      resources,
      preselectedEntities: widget.preselectedEntities,
      selectionColor: widget.selectionColor,
    );

    // Load environment.
    await _platform!.loadEnvironment(widget.iblPath, widget.skyboxPath);

    // Set the default zoom level if provided.
    if (widget.defaultZoom != null) {
      await _platform!.setCameraZoomLevel(widget.defaultZoom!);
    }
  }

  /// Loads additional resources required for `.gltf` models.
  /// Returns a map of resource file names to their byte data.
  Future<Map<String, ByteData>> _loadGltfResources(String modelPath) async {
    Map<String, ByteData> resources = {};

    // Identify the base directory.
    String baseDir = modelPath.substring(0, modelPath.lastIndexOf('/') + 1);
    List<String> candidates = widget.resources;

    for (final file in candidates) {
      final path = '$baseDir$file';
      try {
        ByteData data = await rootBundle.load(path);
        resources[file] = data;
      } catch (e) {
        debugPrint('Optional resource not found: $path');
      }
    }

    return resources;
  }

  /// Handles selection changes and triggers the callback.
  void _onSelectionChanged(List<EntityData> selectedEntities) {
    widget.onSelectionChanged?.call(selectedEntities);
  }
}

/// Represents an entity in the 3D model.
class EntityData {
  /// A unique identifier for the entity in the 3D model.
  final int id;

  /// The name of the entity in the 3D model.
  final String name;

  /// Constructor for the `EntityData` class.
  EntityData({required this.id, required this.name});
}