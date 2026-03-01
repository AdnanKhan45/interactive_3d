import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'controller.dart';
import 'method_channel.dart';
import 'models.dart';
import 'platform_interface.dart';

/// A widget for rendering and interacting with 3D models.
///
/// On Android, renders via Flutter's Texture widget backed by a Filament
/// SurfaceProducer. On iOS, renders via a native SCNView embedded through
/// UiKitView.
///
/// ```dart
/// Interactive3d(
///   modelPath: 'assets/models/tooth.glb',
///   iblPath: 'assets/models/env_ibl.ktx',
///   skyboxPath: 'assets/models/env_skybox.ktx',
///   selectionColor: [0.0, 0.4, 1.0, 1.0],
///   onSelectionChanged: (entities) => print(entities),
/// )
/// ```
class Interactive3d extends StatefulWidget {
  /// Path to the 3D model (.glb/.gltf) in the asset bundle.
  final String? modelPath;

  /// URL to download the 3D model (.glb/.gltf) from the network.
  final String? modelUrl;

  /// Asset path for the IBL lighting file (.ktx).
  final String? iblPath;

  /// URL for the IBL lighting file (.ktx).
  final String? iblUrl;

  /// Asset path for the skybox texture (.ktx).
  final String? skyboxPath;

  /// URL for the skybox texture (.ktx).
  final String? skyboxUrl;

  /// Asset path for the iOS HDR/EXR background environment.
  final String? iOSBackgroundEnvPath;

  /// URL for the iOS HDR/EXR background environment.
  final String? iOSBackgroundEnvUrl;

  /// Additional resource paths for multi-file .gltf models (textures, .bin).
  final List<String> resources;

  /// Called when the set of selected entities changes.
  final void Function(List<EntityData>)? onSelectionChanged;

  /// Entity names to highlight when the model first loads.
  final List<String>? preselectedEntities;

  /// Default highlight color for selected entities. RGBA 0.0–1.0.
  final List<double>? selectionColor;

  /// Initial camera zoom level.
  final double? defaultZoom;

  /// Solid background color (RGBA 0.0–1.0). When set, replaces the skybox.
  final List<double>? solidBackgroundColor;

  /// Per-entity color overrides for selection highlights.
  final List<PatchColor>? patchColors;

  /// Controller for programmatic interaction with the 3D view.
  final Interactive3dController? controller;

  /// Enables persistent selection caching across sessions.
  final bool enableCache;

  /// Color used for cached entity highlights. RGBA 0.0–1.0.
  final List<double>? cacheColor;

  /// Called when the cached selection set changes.
  final void Function(List<String>)? onCacheSelectionChanged;

  /// When true, clears active selections when cache highlights are applied.
  final bool clearSelectionOnHighlight;

  /// Ordered selection rules that constrain which entities can be tapped next.
  final List<SequenceConfig>? selectionSequence;

  /// Background color shown while the model is loading.
  final Color backgroundColor;

  /// Widget displayed while the model is loading.
  final Widget? loadingWidget;

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
    this.solidBackgroundColor,
    this.patchColors,
    this.controller,
    this.enableCache = false,
    this.cacheColor,
    this.onCacheSelectionChanged,
    this.clearSelectionOnHighlight = false,
    this.selectionSequence,
    this.backgroundColor = Colors.black,
    this.loadingWidget,
  });

  @override
  Interactive3dState createState() => Interactive3dState();
}

/// State for [Interactive3d].
///
/// Public methods ([setZoom], [clearCache], etc.) are called by
/// [Interactive3dController] and route to the correct platform.
class Interactive3dState extends State<Interactive3d> {
  // Android (Texture API)
  Interactive3dPlatform? _platform;
  int? _textureId;
  bool _isInitializing = false;

  // iOS (PlatformView)
  MethodChannel? _iosMethodChannel;
  StreamSubscription? _iosEventSubscription;

  // Shared
  StreamSubscription<List<EntityData>>? _selectionSubscription;
  StreamSubscription<List<String>>? _cacheSelectionSubscription;
  Size? _currentSize;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
  }

  @override
  void didUpdateWidget(Interactive3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      widget.controller?.attach(this);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) return _buildIOSPlatformView();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        if (_textureId == null && !_isInitializing && size.width > 0 && size.height > 0) {
          _initializeTexture(size);
        }

        if (_currentSize != size && _textureId != null) {
          _currentSize = size;
          _updateTextureSize(size);
        }

        return Container(
          color: widget.backgroundColor,
          child: _textureId != null
              ? _buildTextureWidget()
              : (widget.loadingWidget ?? const Center(child: CircularProgressIndicator())),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // iOS — PlatformView
  // ---------------------------------------------------------------------------

  Widget _buildIOSPlatformView() {
    return UiKitView(
      viewType: 'interactive_3d',
      creationParams: {
        'modelPath': widget.modelPath,
        'modelUrl': widget.modelUrl,
        'solidBackgroundColor': widget.solidBackgroundColor,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onIOSPlatformViewCreated,
    );
  }

  void _onIOSPlatformViewCreated(int viewId) {
    _iosMethodChannel = MethodChannel('interactive_3d_$viewId');
    final eventChannel = EventChannel('interactive_3d_events_$viewId');

    _iosEventSubscription = eventChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<dynamic, dynamic>;
      final String eventType = map['event'];

      if (eventType == 'selectionChanged') {
        final List<dynamic> selected = map['selectedEntities'];
        final entities = selected
            .map((e) => EntityData(id: e['id'] as int, name: e['name'] as String))
            .toList();
        widget.onSelectionChanged?.call(entities);
      } else if (eventType == 'cacheSelectionChanged') {
        final List<dynamic> cached = map['cachedEntities'];
        final names = cached.map<String>((e) => e['name'] as String).toList();
        widget.onCacheSelectionChanged?.call(names);
      }
    });

    _loadIOSModelAndEnvironment();
  }

  Future<void> _loadIOSModelAndEnvironment() async {
    final channel = _iosMethodChannel;
    if (channel == null) return;

    try {
      Uint8List modelBytes;
      String modelName;

      if (widget.modelPath != null) {
        final data = await rootBundle.load(widget.modelPath!);
        modelBytes = data.buffer.asUint8List();
        modelName = widget.modelPath!.split('/').last;
      } else if (widget.modelUrl != null) {
        final response = await http.get(Uri.parse(widget.modelUrl!));
        if (response.statusCode != 200) {
          throw Exception('Failed to load model: ${widget.modelUrl}');
        }
        modelBytes = response.bodyBytes;
        modelName = widget.modelUrl!.split('/').last;
      } else {
        return;
      }

      await channel.invokeMethod('loadModel', {
        'modelBytes': modelBytes,
        'name': modelName,
        'preselectedEntities': widget.preselectedEntities,
        'selectionColor': widget.selectionColor,
        'patchColors': widget.patchColors
            ?.map((p) => {'name': p.name, 'color': p.color})
            .toList(),
        'enableCache': widget.enableCache,
        'cacheColor': widget.cacheColor,
        'clearSelectionsOnHighlight': widget.clearSelectionOnHighlight,
        'selectionSequence': widget.selectionSequence?.map((c) => c.toJson()).toList(),
        'backgroundColor': widget.solidBackgroundColor,
      });

      // iOS HDR/EXR background
      if (widget.iOSBackgroundEnvPath != null || widget.iOSBackgroundEnvUrl != null) {
        Uint8List? bgBytes;
        if (widget.iOSBackgroundEnvPath != null) {
          bgBytes = (await rootBundle.load(widget.iOSBackgroundEnvPath!)).buffer.asUint8List();
        } else if (widget.iOSBackgroundEnvUrl != null) {
          final response = await http.get(Uri.parse(widget.iOSBackgroundEnvUrl!));
          if (response.statusCode == 200) bgBytes = response.bodyBytes;
        }
        if (bgBytes != null) {
          await channel.invokeMethod('loadHdrBackground', {'backgroundBytes': bgBytes});
        }
      }

      if (widget.defaultZoom != null) {
        await channel.invokeMethod('setZoomLevel', {'zoom': widget.defaultZoom});
      }
    } catch (e) {
      debugPrint('Error loading iOS model: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Android — Texture API
  // ---------------------------------------------------------------------------

  Widget _buildTextureWidget() {
    return GestureDetector(
      onTapUp: _handleTapUp,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: Texture(textureId: _textureId!),
    );
  }

  Future<void> _initializeTexture(Size size) async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      _platform = MethodChannelInteractive3d();

      final result = await _platform!.createTexture(
        width: size.width.toInt(),
        height: size.height.toInt(),
      );

      _textureId = result['textureId'] as int?;
      if (_textureId == null) throw Exception('Failed to create texture');

      _currentSize = size;
      if (mounted) setState(() {});

      _selectionSubscription =
          _platform!.selectionStream(_textureId!).listen(_onSelectionChanged);

      if (widget.onCacheSelectionChanged != null) {
        _cacheSelectionSubscription = _platform!
            .cacheSelectionStream(_textureId!)
            .listen(widget.onCacheSelectionChanged!);
      }

      await _loadAndroidModelAndEnvironment();
    } catch (e) {
      debugPrint('Error initializing texture: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadAndroidModelAndEnvironment() async {
    if (_platform == null || _textureId == null) return;

    Map<String, ByteData> resources = {};
    if ((widget.modelPath ?? widget.modelUrl ?? '').endsWith('.gltf')) {
      resources = await _loadGltfResources();
    }

    await _platform!.loadModel(
      textureId: _textureId!,
      modelPath: widget.modelPath,
      modelUrl: widget.modelUrl,
      resources: resources,
      preselectedEntities: widget.preselectedEntities,
      selectionColor: widget.selectionColor,
      patchColors: widget.patchColors,
      enableCache: widget.enableCache,
      cacheColor: widget.cacheColor,
      clearSelectionsOnHighlight: widget.clearSelectionOnHighlight,
      selectionSequence: widget.selectionSequence,
      backgroundColor: widget.solidBackgroundColor,
    );

    await _platform!.loadEnvironment(
      textureId: _textureId!,
      iblPath: widget.iblPath,
      iblUrl: widget.iblUrl,
      skyboxPath: widget.skyboxPath,
      skyboxUrl: widget.skyboxUrl,
    );

    if (widget.defaultZoom != null) {
      await setZoom(widget.defaultZoom);
    }
  }

  Future<void> _updateTextureSize(Size size) async {
    // Future: update texture size on native side
  }

  // ---------------------------------------------------------------------------
  // Gesture Handling (Android only — iOS handles natively)
  // ---------------------------------------------------------------------------

  void _handleTapUp(TapUpDetails details) {
    if (_platform == null || _textureId == null) return;
    _platform!.onTouchEvent(
      textureId: _textureId!,
      action: 'tap',
      x: details.localPosition.dx,
      y: details.localPosition.dy,
    );
  }

  Offset? _lastFocalPoint;

  void _handleScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_platform == null || _textureId == null) return;

    if (details.scale != 1.0) {
      _platform!.onTouchEvent(
        textureId: _textureId!,
        action: 'scale',
        scale: details.scale,
      );
    }

    if (_lastFocalPoint != null) {
      final delta = details.localFocalPoint - _lastFocalPoint!;
      if (delta.distance > 0.5) {
        _platform!.onTouchEvent(
          textureId: _textureId!,
          action: 'pan',
          deltaX: delta.dx,
          deltaY: delta.dy,
        );
      }
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  // ---------------------------------------------------------------------------
  // Public API — routes to correct platform
  // ---------------------------------------------------------------------------

  Future<void> setZoom(double? level) async {
    if (level == null) return;
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('setZoomLevel', {'zoom': level});
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.setCameraZoomLevel(_textureId!, level);
    }
  }

  Future<void> clearCache() async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('clearCache');
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.clearCache(_textureId!);
    }
  }

  Future<void> refreshCacheHighlights() async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('refreshCacheHighlights');
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.refreshCacheHighlights(_textureId!);
    }
  }

  Future<void> removeFromCache(List<String> names) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('removeFromCache', names);
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.removeFromCache(_textureId!, names);
    }
  }

  Future<void> updatePartGroupConfig({
    required bool isVisible,
    required ModelPartGroup group,
  }) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('setPartGroupVisibility', {
        'group': group.toMap(),
        'visibility': {group.title: isVisible},
      });
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.updatePartGroupConfig(
        textureId: _textureId!,
        isVisible: isVisible,
        group: group,
      );
    }
  }

  Future<void> unselectEntities({List<int>? entityIds}) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('unselectEntities', entityIds);
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.unselectEntities(textureId: _textureId!, entityIds: entityIds);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, ByteData>> _loadGltfResources() async {
    Map<String, ByteData> resources = {};

    String baseDir = '';
    if (widget.modelPath != null) {
      baseDir = widget.modelPath!.substring(0, widget.modelPath!.lastIndexOf('/') + 1);
    } else if (widget.modelUrl != null) {
      baseDir = widget.modelUrl!.substring(0, widget.modelUrl!.lastIndexOf('/') + 1);
    }

    for (final file in widget.resources) {
      try {
        if (widget.modelPath != null) {
          resources[file] = await rootBundle.load('$baseDir$file');
        } else if (widget.modelUrl != null) {
          final uri = Uri.parse('$baseDir$file');
          resources[file] = await _loadNetworkResource(uri.toString());
        }
      } catch (e) {
        debugPrint('Optional resource not found: $file ($e)');
      }
    }

    return resources;
  }

  Future<ByteData> _loadNetworkResource(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return ByteData.view(response.bodyBytes.buffer);
    }
    throw Exception('Failed to load resource: $url (${response.statusCode})');
  }

  void _onSelectionChanged(List<EntityData> selectedEntities) {
    widget.onSelectionChanged?.call(selectedEntities);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    _cacheSelectionSubscription?.cancel();
    _iosEventSubscription?.cancel();
    widget.controller?.detach();

    if (Platform.isIOS) {
      _iosMethodChannel?.invokeMethod('dispose');
      _iosMethodChannel = null;
    } else {
      if (_platform != null && _textureId != null) {
        _platform!.disposeTexture(_textureId!);
      }
    }

    super.dispose();
  }
}