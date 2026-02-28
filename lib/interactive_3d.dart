import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'interactive_3d_controller.dart';
import 'interactive_3d_method_channel.dart';
import 'interactive_3d_platform_interface.dart';

/// Configuration for the sequence selection of entities in the 3D model.
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

/// Represents a patch color for a specific entity in the 3D model.
class PatchColor {
  /// The name of the entity to apply the color to.
  final String name;

  /// The RGBA color values (0.0 to 1.0) for selection and preselection.
  final List<double> color;

  PatchColor({required this.name, required this.color});
}

/// Represents a group of model parts whose visibility can be toggled together.
class ModelPartGroup {
  /// The display title for the group, shown in the UI.
  final String title;

  /// The list of node names (e.g., 'Tooth_1', 'Gum_1') in the 3D model.
  final List<String> names;

  ModelPartGroup({required this.title, required this.names});

  /// Converts the group to a map for method channel communication.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'names': names,
    };
  }
}

/// A widget for rendering and interacting with 3D models.
///
/// On Android: Uses Flutter's Texture widget with SurfaceProducer API
/// for high-performance rendering.
/// On iOS: Uses UiKitView PlatformView with SCNView for native rendering.
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

  /// If non-null, uses a solid color background instead of the IBL skybox.
  /// Format: [r, g, b, a] with values 0.0–1.0.
  /// Default when enabled without a color: dim white [0.92, 0.92, 0.92, 1.0]
  final List<double>? solidBackgroundColor;

  /// A list of PatchColor objects specifying entity-specific selection and preselection colors.
  final List<PatchColor>? patchColors;

  /// Controller for programmatically interacting with the 3D view.
  final Interactive3dController? controller;

  /// Enables persistent caching of selected entities on the native side.
  final bool enableCache;

  /// The color used to display cached entities (RGBA 0.0–1.0).
  final List<double>? cacheColor;

  /// Callback for when the cached selection changes (persistent cache).
  final void Function(List<String>)? onCacheSelectionChanged;

  /// Whether to clear the selection when highlighting cached entities.
  final bool clearSelectionOnHighlight;

  /// A list of sequence configurations for selecting entities in a specific order.
  final List<SequenceConfig>? selectionSequence;

  /// Background color shown while loading.
  final Color backgroundColor;

  /// Widget to show while loading.
  final Widget? loadingWidget;

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

/// State class for the `Interactive3d` widget.
class Interactive3dState extends State<Interactive3d> {
  // ── Android (Texture API) ──
  Interactive3dPlatform? _platform;
  int? _textureId;
  bool _isInitializing = false;

  // ── iOS (PlatformView) ──
  int? _iosViewId;
  MethodChannel? _iosMethodChannel;
  StreamSubscription? _iosEventSubscription;

  // ── Shared ──
  bool _isLoaded = false;
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

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // iOS: PlatformView (SCNView via UiKitView)
    if (Platform.isIOS) {
      return _buildIOSPlatformView();
    }

    // Android: Texture API (SurfaceProducer + Filament)
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

  // ═══════════════════════════════════════════════════════════════════════════
  // iOS — PlatformView
  // ═══════════════════════════════════════════════════════════════════════════

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
    _iosViewId = viewId;
    _iosMethodChannel = MethodChannel('interactive_3d_$viewId');
    final eventChannel = EventChannel('interactive_3d_events_$viewId');

    // Listen for native events
    _iosEventSubscription = eventChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<dynamic, dynamic>;
      final String eventType = map['event'];

      if (eventType == 'selectionChanged') {
        final List<dynamic> selectedEntities = map['selectedEntities'];
        final entities = selectedEntities.map((e) {
          return EntityData(id: e['id'] as int, name: e['name'] as String);
        }).toList();
        widget.onSelectionChanged?.call(entities);
      } else if (eventType == 'cacheSelectionChanged') {
        final List<dynamic> cachedEntities = map['cachedEntities'];
        final entityNames = cachedEntities.map<String>((e) => e['name'] as String).toList();
        widget.onCacheSelectionChanged?.call(entityNames);
      }
    });

    // Load model and environment via the view's method channel
    _loadIOSModelAndEnvironment();
  }

  Future<void> _loadIOSModelAndEnvironment() async {
    final channel = _iosMethodChannel;
    if (channel == null) return;

    try {
      // Load model bytes
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
        'patchColors': widget.patchColors?.map((p) => {
          'name': p.name,
          'color': p.color,
        }).toList(),
        'enableCache': widget.enableCache,
        'cacheColor': widget.cacheColor,
        'clearSelectionsOnHighlight': widget.clearSelectionOnHighlight,
        'selectionSequence': widget.selectionSequence?.map((c) => c.toJson()).toList(),
        'backgroundColor': widget.solidBackgroundColor,
      });

      // Load HDR background for iOS
      if (widget.iOSBackgroundEnvPath != null || widget.iOSBackgroundEnvUrl != null) {
        Uint8List? bgBytes;
        if (widget.iOSBackgroundEnvPath != null) {
          final data = await rootBundle.load(widget.iOSBackgroundEnvPath!);
          bgBytes = data.buffer.asUint8List();
        } else if (widget.iOSBackgroundEnvUrl != null) {
          final response = await http.get(Uri.parse(widget.iOSBackgroundEnvUrl!));
          if (response.statusCode == 200) {
            bgBytes = response.bodyBytes;
          }
        }
        if (bgBytes != null) {
          await channel.invokeMethod('loadHdrBackground', {
            'backgroundBytes': bgBytes,
          });
        }
      }

      // Set default zoom
      if (widget.defaultZoom != null) {
        await channel.invokeMethod('setZoomLevel', {
          'zoom': widget.defaultZoom,
        });
      }

      _isLoaded = true;
    } catch (e) {
      debugPrint('Error loading iOS model: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Android — Texture API
  // ═══════════════════════════════════════════════════════════════════════════

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

      final textureId = result['textureId'] as int?;
      if (textureId == null) {
        throw Exception('Failed to create texture');
      }

      _textureId = textureId;
      _currentSize = size;

      if (mounted) setState(() {});

      _selectionSubscription = _platform!.selectionStream(_textureId!).listen(_onSelectionChanged);

      if (widget.onCacheSelectionChanged != null) {
        _cacheSelectionSubscription = _platform!.cacheSelectionStream(_textureId!).listen(widget.onCacheSelectionChanged!);
      }

      await _loadAndroidModelAndEnvironment();

      _isLoaded = true;
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
    // Future enhancement: update texture size on native side
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Gesture Handling (Android Texture only — iOS handles natively via SCNView)
  // ═══════════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API — routes to correct platform
  // ═══════════════════════════════════════════════════════════════════════════

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

  Future<void> updatePartGroupConfig({required bool isVisible, required ModelPartGroup group}) async {
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

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

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
          final path = '$baseDir$file';
          ByteData data = await rootBundle.load(path);
          resources[file] = data;
        } else if (widget.modelUrl != null) {
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

  Future<ByteData> _loadNetworkResource(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return ByteData.view(response.bodyBytes.buffer);
    } else {
      throw Exception('Failed to load resource: $url, status: ${response.statusCode}');
    }
  }

  void _onSelectionChanged(List<EntityData> selectedEntities) {
    widget.onSelectionChanged?.call(selectedEntities);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Dispose
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    _cacheSelectionSubscription?.cancel();
    _iosEventSubscription?.cancel();
    widget.controller?.detach();

    if (Platform.isIOS) {
      // Explicitly trigger native cleanup (breaks retain cycles)
      _iosMethodChannel?.invokeMethod('dispose');
      _iosMethodChannel = null;
    } else {
      // Dispose the Android texture
      if (_platform != null && _textureId != null) {
        _platform!.disposeTexture(_textureId!);
      }
    }

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