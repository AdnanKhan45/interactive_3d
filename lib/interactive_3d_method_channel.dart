import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'interactive_3d_platform_interface.dart';
import 'interactive_3d.dart';

class MethodChannelInteractive3d extends Interactive3dPlatform {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  MethodChannelInteractive3d(int viewId)
      : _methodChannel = MethodChannel('interactive_3d_$viewId'),
        _eventChannel = EventChannel('interactive_3d_events_$viewId') {
    _eventChannel.receiveBroadcastStream().listen(_onEvent);
  }

  final StreamController<List<EntityData>> _selectionController =
  StreamController.broadcast();

  @override
  Stream<List<EntityData>> get selectionStream => _selectionController.stream;

  void _onEvent(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    final String eventType = map['event'];
    if (eventType == 'selectionChanged') {
      final List<dynamic> selectedEntities = map['selectedEntities'];
      final entities = selectedEntities.map((e) {
        return EntityData(id: e['id'], name: e['name']);
      }).toList();
      _selectionController.add(entities);
    }
  }

  @override
  Future<void> loadModel({
    String? modelPath,
    String? modelUrl,
    required Map<String, ByteData> resources,
    List<String>? preselectedEntities,
    List<double>? selectionColor,
    List<PatchColor>? patchColors, // Add patchColors
  }) async {
    Uint8List modelBytes;
    String modelName;

    if (modelPath != null) {
      ByteData modelData = await rootBundle.load(modelPath);
      modelBytes = modelData.buffer.asUint8List();
      modelName = modelPath.split('/').last;
    } else if (modelUrl != null) {
      final response = await http.get(Uri.parse(modelUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to load model: $modelUrl, status: ${response.statusCode}');
      }
      modelBytes = response.bodyBytes;
      modelName = modelUrl.split('/').last;
    } else {
      throw ArgumentError('Must provide either modelPath or modelUrl');
    }

    final resourceMap = resources.map(
          (key, value) => MapEntry(key, value.buffer.asUint8List()),
    );

    // Convert patchColors to a serializable format
    final patchColorsMap = patchColors?.map((patch) => {
      'name': patch.name,
      'color': patch.color,
    }).toList();

    final args = {
      'modelBytes': modelBytes,
      'name': modelName,
      'resources': resourceMap,
      'preselectedEntities': preselectedEntities,
      'selectionColor': selectionColor,
      'patchColors': patchColorsMap, // Pass patchColors
    };

    await _methodChannel.invokeMethod('loadModel', args);
  }

  @override
  Future<void> loadEnvironment({
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  }) async {
    Uint8List? iblBytes;
    Uint8List? skyboxBytes;

    try {
      if (iblPath != null) {
        ByteData iblData = await rootBundle.load(iblPath);
        iblBytes = iblData.buffer.asUint8List();
      } else if (iblUrl != null) {
        final response = await http.get(Uri.parse(iblUrl));
        if (response.statusCode == 200) {
          iblBytes = response.bodyBytes;
        } else {
          debugPrint('Failed to load IBL from $iblUrl: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Error loading IBL: $e');
    }

    try {
      if (skyboxPath != null) {
        ByteData skyboxData = await rootBundle.load(skyboxPath);
        skyboxBytes = skyboxData.buffer.asUint8List();
      } else if (skyboxUrl != null) {
        final response = await http.get(Uri.parse(skyboxUrl));
        if (response.statusCode == 200) {
          skyboxBytes = response.bodyBytes;
        } else {
          debugPrint('Failed to load skybox from $skyboxUrl: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Error loading skybox: $e');
    }

    if (iblBytes == null || skyboxBytes == null) {
      throw Exception('Failed to load environment: iblBytes or skyboxBytes is null');
    }

    await _methodChannel.invokeMethod('loadEnvironment', {
      'iblBytes': iblBytes,
      'skyboxBytes': skyboxBytes,
    });
  }

  @override
  Future<void> unselectEntities({List<int>? entityIds}) async {
    await _methodChannel.invokeMethod('unselectEntities', {
      'entityIds': entityIds?.map((id) => id.toInt()).toList(),
    });
  }

  @override
  Future<void> setCameraZoomLevel(double zoom) async {
    await _methodChannel.invokeMethod('setZoomLevel', {'zoom': zoom});
  }
}