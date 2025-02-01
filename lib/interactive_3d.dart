import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'interactive_3d_method_channel.dart';
import 'interactive_3d_platform_interface.dart';
import 'dart:io';

class Interactive3d extends StatefulWidget {
  final String modelPath;
  final String iblPath;
  final String skyboxPath;
  final List<String> resources;
  final void Function(List<EntityData>)? onSelectionChanged;

  const Interactive3d({
    super.key,
    required this.modelPath,
    required this.iblPath,
    required this.skyboxPath,
    this.onSelectionChanged,
    this.resources = const [],
  });

  @override
  Interactive3dState createState() => Interactive3dState();
}

class Interactive3dState extends State<Interactive3d> {
  Interactive3dPlatform? _platform;
  int _viewId = -1;
  StreamSubscription<List<EntityData>>? _selectionSubscription;

  @override
  Widget build(BuildContext context) {
    if(Platform.isIOS) {
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

  dynamic _creationParams() {
    return {
      'modelPath': widget.modelPath,
      'iblPath': widget.iblPath,
      'skyboxPath': widget.skyboxPath,
      'resources': widget.resources,
    };
  }

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
    await _platform!.loadModel(widget.modelPath, resources);

    // Load environment.
    await _platform!.loadEnvironment(widget.iblPath, widget.skyboxPath);
  }

  Future<Map<String, ByteData>> _loadGltfResources(String modelPath) async {
    // This is an example. Adjust it per your file structure.
    // If your .gltf references textures or .bin, load them here.
    Map<String, ByteData> resources = {};

    // Identify the base directory.
    String baseDir = modelPath.substring(0, modelPath.lastIndexOf('/') + 1);
    // Example resource references.
    // Add real ones or detect them from your .gltf content.
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

  void _onSelectionChanged(List<EntityData> selectedEntities) {
    widget.onSelectionChanged?.call(selectedEntities);
  }
}

class EntityData {
  final int id;
  final String name;

  EntityData({required this.id, required this.name});
}

