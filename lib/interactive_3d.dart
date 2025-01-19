import 'dart:async';

import 'package:flutter/material.dart';

import 'interactive_3d_method_channel.dart';
import 'interactive_3d_platform_interface.dart';

class Interactive3d extends StatefulWidget {
  final String modelPath;
  final String iblPath;
  final String skyboxPath;
  final void Function(List<EntityData>)? onSelectionChanged;

  const Interactive3d({super.key,
    required this.modelPath,
    required this.iblPath,
    required this.skyboxPath,
    this.onSelectionChanged,
  });

  @override
  Interactive3dState createState() => Interactive3dState();
}

class Interactive3dState extends State<Interactive3d> { // Added WidgetsBindingObserver
  Interactive3dPlatform? _platform;
  int _viewId = -1;
  StreamSubscription<List<EntityData>>? _selectionSubscription;


  @override
  Widget build(BuildContext context) {
    return AndroidView(
      key: const ValueKey('interactive_3d'), // Add this line
      viewType: 'interactive_3d',
      onPlatformViewCreated: _onPlatformViewCreated,

    );
  }

  void _onPlatformViewCreated(int id) async {
    _viewId = id;
    _platform = MethodChannelInteractive3d(_viewId);
    Interactive3dPlatform.verify(_platform!);

    // Listen to selection changes
    _selectionSubscription =
        _platform!.selectionStream.listen(_onSelectionChanged);

    // Load the model
    await _platform!.loadModel(widget.modelPath);

    // Load the environment
    await _platform!.loadEnvironment(widget.iblPath, widget.skyboxPath);
  }

  void _onSelectionChanged(List<EntityData> selectedEntities) {
    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(selectedEntities);
    }
  }
}