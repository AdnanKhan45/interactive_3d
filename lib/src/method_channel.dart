import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'platform_interface.dart';

/// Android method channel implementation using Flutter's Texture API.
///
/// Communicates with the Kotlin plugin over a single [MethodChannel]
/// (`interactive_3d_plugin`) and per-texture [EventChannel]s for
/// selection and cache change events.
class MethodChannelInteractive3d extends Interactive3dPlatform {
  static const _pluginChannel = MethodChannel('interactive_3d_plugin');

  final Map<int, EventChannel> _eventChannels = {};
  final Map<int, StreamController<List<EntityData>>> _selectionControllers = {};
  final Map<int, StreamController<List<String>>> _cacheSelectionControllers = {};

  @override
  Future<Map<String, dynamic>> createTexture({
    required int width,
    required int height,
  }) async {
    final result = await _pluginChannel.invokeMethod<Map<dynamic, dynamic>>(
      'createTexture',
      {'width': width, 'height': height},
    );
    if (result == null) throw Exception('Failed to create texture');

    final textureId = result['textureId'] as int;
    _setupEventChannel(textureId);
    return {'textureId': textureId};
  }

  @override
  Future<void> disposeTexture(int textureId) async {
    _selectionControllers[textureId]?.close();
    _cacheSelectionControllers[textureId]?.close();
    _selectionControllers.remove(textureId);
    _cacheSelectionControllers.remove(textureId);
    _eventChannels.remove(textureId);

    await _pluginChannel.invokeMethod('disposeTexture', {
      'textureId': textureId,
    });
  }

  void _setupEventChannel(int textureId) {
    final eventChannel = EventChannel('interactive_3d_events_$textureId');
    _eventChannels[textureId] = eventChannel;
    _selectionControllers[textureId] = StreamController.broadcast();
    _cacheSelectionControllers[textureId] = StreamController.broadcast();

    eventChannel.receiveBroadcastStream().listen((event) {
      _onEvent(textureId, event);
    });
  }

  void _onEvent(int textureId, dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    final String eventType = map['event'];

    if (eventType == 'selectionChanged') {
      final List<dynamic> selected = map['selectedEntities'];
      final entities = selected
          .map((e) => EntityData(id: e['id'] as int, name: e['name'] as String))
          .toList();
      _selectionControllers[textureId]?.add(entities);
    } else if (eventType == 'cacheSelectionChanged') {
      final List<dynamic> cached = map['cachedEntities'];
      final names = cached.map<String>((e) => e['name'] as String).toList();
      _cacheSelectionControllers[textureId]?.add(names);
    }
  }

  @override
  Stream<List<EntityData>> selectionStream(int textureId) =>
      _selectionControllers[textureId]?.stream ?? const Stream.empty();

  @override
  Stream<List<String>> cacheSelectionStream(int textureId) =>
      _cacheSelectionControllers[textureId]?.stream ?? const Stream.empty();

  @override
  Future<void> loadModel({
    required int textureId,
    String? modelPath,
    String? modelUrl,
    required Map<String, ByteData> resources,
    List<String>? preselectedEntities,
    List<double>? selectionColor,
    List<PatchColor>? patchColors,
    bool enableCache = false,
    List<double>? cacheColor,
    bool clearSelectionsOnHighlight = false,
    List<SequenceConfig>? selectionSequence,
    List<double>? backgroundColor,
  }) async {
    Uint8List modelBytes;
    String modelName;

    if (modelPath != null) {
      final data = await rootBundle.load(modelPath);
      modelBytes = data.buffer.asUint8List();
      modelName = modelPath.split('/').last;
    } else if (modelUrl != null) {
      final response = await http.get(Uri.parse(modelUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to load model: $modelUrl (${response.statusCode})');
      }
      modelBytes = response.bodyBytes;
      modelName = modelUrl.split('/').last;
    } else {
      throw ArgumentError('Must provide either modelPath or modelUrl');
    }

    final resourceMap = resources.map(
          (key, value) => MapEntry(key, value.buffer.asUint8List()),
    );

    await _pluginChannel.invokeMethod('loadModel', {
      'textureId': textureId,
      'modelBytes': modelBytes,
      'name': modelName,
      'resources': resourceMap,
      'preselectedEntities': preselectedEntities,
      'selectionColor': selectionColor,
      'patchColors': patchColors
          ?.map((p) => {'name': p.name, 'color': p.color})
          .toList(),
      'enableCache': enableCache,
      'cacheColor': cacheColor,
      'clearSelectionsOnHighlight': clearSelectionsOnHighlight,
      'selectionSequence': selectionSequence?.map((c) => c.toJson()).toList(),
      'backgroundColor': backgroundColor,
    });
  }

  @override
  Future<void> loadEnvironment({
    required int textureId,
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  }) async {
    Uint8List? iblBytes;
    Uint8List? skyboxBytes;

    try {
      if (iblPath != null) {
        iblBytes = (await rootBundle.load(iblPath)).buffer.asUint8List();
      } else if (iblUrl != null) {
        final response = await http.get(Uri.parse(iblUrl));
        if (response.statusCode == 200) iblBytes = response.bodyBytes;
      }
    } catch (e) {
      debugPrint('Error loading IBL: $e');
    }

    try {
      if (skyboxPath != null) {
        skyboxBytes = (await rootBundle.load(skyboxPath)).buffer.asUint8List();
      } else if (skyboxUrl != null) {
        final response = await http.get(Uri.parse(skyboxUrl));
        if (response.statusCode == 200) skyboxBytes = response.bodyBytes;
      }
    } catch (e) {
      debugPrint('Error loading skybox: $e');
    }

    if (iblBytes == null || skyboxBytes == null) {
      debugPrint('Warning: Environment not fully loaded');
      return;
    }

    await _pluginChannel.invokeMethod('loadEnvironment', {
      'textureId': textureId,
      'iblBytes': iblBytes,
      'skyboxBytes': skyboxBytes,
    });
  }

  @override
  Future<void> loadHdrBackground({
    required int textureId,
    String? backgroundPath,
    String? backgroundUrl,
  }) async {
    Uint8List? backgroundBytes;

    if (backgroundPath != null) {
      backgroundBytes = (await rootBundle.load(backgroundPath)).buffer.asUint8List();
    } else if (backgroundUrl != null) {
      final response = await http.get(Uri.parse(backgroundUrl));
      if (response.statusCode == 200) {
        backgroundBytes = response.bodyBytes;
      } else {
        throw Exception('Failed to load HDR/EXR from $backgroundUrl');
      }
    } else {
      throw ArgumentError('Must provide backgroundPath or backgroundUrl');
    }

    await _pluginChannel.invokeMethod('loadHdrBackground', {
      'textureId': textureId,
      'backgroundBytes': backgroundBytes,
    });
  }

  @override
  Future<void> unselectEntities({
    required int textureId,
    List<int>? entityIds,
  }) async {
    await _pluginChannel.invokeMethod('unselectEntities', {
      'textureId': textureId,
      'entityIds': entityIds?.map((id) => id.toInt()).toList(),
    });
  }

  @override
  Future<void> updatePartGroupConfig({
    required int textureId,
    required bool isVisible,
    required ModelPartGroup group,
  }) async {
    await _pluginChannel.invokeMethod('setPartGroupVisibility', {
      'textureId': textureId,
      'group': group.toMap(),
      'visibility': {group.title: isVisible},
    });
  }

  @override
  Future<void> setCameraZoomLevel(int textureId, double zoom) async {
    await _pluginChannel.invokeMethod('setZoomLevel', {
      'textureId': textureId,
      'zoom': zoom,
    });
  }

  @override
  Future<void> clearCache(int textureId) async {
    await _pluginChannel.invokeMethod('clearCache', {
      'textureId': textureId,
    });
  }

  @override
  Future<void> refreshCacheHighlights(int textureId) async {
    await _pluginChannel.invokeMethod('refreshCacheHighlights', {
      'textureId': textureId,
    });
  }

  @override
  Future<void> removeFromCache(int textureId, List<String> names) async {
    await _pluginChannel.invokeMethod('removeFromCache', {
      'textureId': textureId,
      'names': names,
    });
  }

  @override
  Future<void> onTouchEvent({
    required int textureId,
    required String action,
    double? x,
    double? y,
    double? deltaX,
    double? deltaY,
    double? scale,
  }) async {
    await _pluginChannel.invokeMethod('onTouchEvent', {
      'textureId': textureId,
      'action': action,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (deltaX != null) 'deltaX': deltaX,
      if (deltaY != null) 'deltaY': deltaY,
      if (scale != null) 'scale': scale,
    });
  }
}