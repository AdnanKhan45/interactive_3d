import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'interactive_3d_controller.dart';
import 'interactive_3d_method_channel.dart';
import 'interactive_3d_platform_interface.dart';

/// Represents a patch color for a specific entity in the 3D model.
class PatchColor {
  /// The name of the entity to apply the color to.
  final String name;

  /// The RGBA color values (0.0 to 1.0) for selection and preselection.
  final List<double> color;

  PatchColor({required this.name, required this.color});
}

/// A widget for rendering and interacting with 3D models using a native platform view.
class Interactive3d extends StatefulWidget {
  /// Path to the 3D model file (e.g., `.glb` or `.gltf`) to be loaded from assets.
  final String? modelPath;

  /// URL to the 3D model file (e.g., `.glb` or `.gltf`) to be loaded from the network.
  final String? modelUrl;

  /// Path to the Image-Based Lighting (IBL) file used for rendering the 3D model from assets.
  final String? iblPath;

  /// URL to the Image-Based Lighting (IBL) file used for rendering the 3D model from the network.
  final String? iblUrl;

  /// Path to the skybox texture file used for the 3D environment from assets.
  final String? skyboxPath;

  /// URL to the skybox texture file used for the 3D environment from the network.
  final String? skyboxUrl;

  /// Path to the skybox texture file of type .hdr/.exr used for the 3D environment from assets.
  final String? iOSBackgroundEnvPath;

  /// URL to the skybox texture file of type .hdr/.exr used for the 3D environment from the network.
  final String? iOSBackgroundEnvUrl;


  /// A list of additional resource file paths required for `.gltf` models (e.g., textures, binary files).
  /// Defaults to an empty list.
  final List<String> resources;

  /// Callback function triggered when the selection of entities in the 3D model changes.
  /// It provides a list of selected entities.
  final void Function(List<EntityData>)? onSelectionChanged;

  /// A list of entity names to be preselected when the model is loaded.
  final List<String>? preselectedEntities;

  /// A list of RGBA values (0.0 to 1.0) representing the default color used to highlight selected entities.
  final List<double>? selectionColor;

  /// The initial zoom level of the camera when the 3D model is loaded.
  final double? defaultZoom;

  /// A list of PatchColor objects specifying entity-specific selection and preselection colors.
  final List<PatchColor>? patchColors;

  /// Controller for programmatically interacting with the 3D view.
  final Interactive3dController? controller;

  /// Constructor for the `Interactive3d` widget.
  const Interactive3d({
    super.key,
    this.modelPath,
    this.modelUrl,
    this.iblPath,
    this.iblUrl,
    this.skyboxPath,
    this.skyboxUrl,
    this.iOSBackgroundEnvPath,
    this.iOSBackgroundEnvUrl,
    this.onSelectionChanged,
    this.resources = const [],
    this.preselectedEntities,
    this.selectionColor,
    this.defaultZoom,
    this.patchColors,
    this.controller,
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
  void initState() {
    widget.controller?.attach(this);
    super.initState();
  }

  @override
  void didUpdateWidget(Interactive3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reattach the controller if it changes
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(this);
    }
  }

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
      'modelUrl': widget.modelUrl,
      'iblPath': widget.iblPath,
      'iblUrl': widget.iblUrl,
      'skyboxPath': widget.skyboxPath,
      'skyboxUrl': widget.skyboxUrl,
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
    if ((widget.modelPath ?? widget.modelUrl ?? '').endsWith('.gltf')) {
      resources = await _loadGltfResources();
    }

    // Load the model.
    await _platform!.loadModel(
      modelPath: widget.modelPath,
      modelUrl: widget.modelUrl,
      resources: resources,
      preselectedEntities: widget.preselectedEntities,
      selectionColor: widget.selectionColor,
      patchColors: widget.patchColors, // Pass patchColors
    );

    // Load environment.
    if(Platform.isAndroid) {
      await _platform!.loadEnvironment(
        iblPath: widget.iblPath,
        iblUrl: widget.iblUrl,
        skyboxPath: widget.skyboxPath,
        skyboxUrl: widget.skyboxUrl,
      );
    } else {
      await _platform!.loadHdrBackground(
        backgroundPath: widget.iOSBackgroundEnvPath,
        backgroundUrl: widget.iOSBackgroundEnvUrl,
      );
    }

    if(widget.defaultZoom != null) {
      await setZoom(widget.defaultZoom);
    }
  }

  // Set the default zoom level if provided.
  Future<void> setZoom(double? level) async {
    await _platform!.setCameraZoomLevel(level ?? widget.defaultZoom!);
  }

  /// Loads additional resources required for `.gltf` models.
  /// Returns a map of resource file names to their byte data.
  Future<Map<String, ByteData>> _loadGltfResources() async {
    Map<String, ByteData> resources = {};

    // Identify the base directory for assets or assume same directory for URLs.
    String baseDir = '';
    if (widget.modelPath != null) {
      baseDir = widget.modelPath!.substring(0, widget.modelPath!.lastIndexOf('/') + 1);
    } else if (widget.modelUrl != null) {
      baseDir = widget.modelUrl!.substring(0, widget.modelUrl!.lastIndexOf('/') + 1);
    }

    List<String> candidates = widget.resources;

    for (final file in candidates) {
      try {
        if (widget.modelPath != null) {
          final path = '$baseDir$file';
          ByteData data = await rootBundle.load(path);
          resources[file] = data;
        } else if (widget.modelUrl != null) {
          // For network resources, assume URLs are provided in resources list
          final uri = Uri.parse('$baseDir$file');
          ByteData data = await _loadNetworkResource(uri.toString());
          resources[file] = data;
        }
      } catch (e) {
        debugPrint('Optional resource not found: $file, error: $e');
      }
    }

    return resources;
  }

  /// Loads a resource from a network URL.
  Future<ByteData> _loadNetworkResource(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return ByteData.view(response.bodyBytes.buffer);
    } else {
      throw Exception('Failed to load resource: $url, status: ${response.statusCode}');
    }
  }

  Future<void> unselectEntities({List<int>? entityIds}) async {
    if (_platform == null) {
      throw StateError('Platform view not initialized');
    }
    await _platform!.unselectEntities(entityIds: entityIds);
  }

  /// Handles selection changes and triggers the callback.
  void _onSelectionChanged(List<EntityData> selectedEntities) {
    widget.onSelectionChanged?.call(selectedEntities);
  }

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    widget.controller?.detach();
    super.dispose();
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