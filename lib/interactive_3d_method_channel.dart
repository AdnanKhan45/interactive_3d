import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:interactive_3d/interactive_3d_platform_interface.dart';
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
  Future<void> loadModel(
      String modelPath,
      Map<String, ByteData> resources, {
        List<String>? preselectedEntities,
        List<double>? selectionColor,
      }) async {
    // Convert the main model to bytes.
    ByteData modelData = await rootBundle.load(modelPath);
    Uint8List modelBytes = modelData.buffer.asUint8List();

    final resourceMap = resources.map(
          (key, value) => MapEntry(key, value.buffer.asUint8List()),
    );

    final args = {
      'modelBytes': modelBytes,
      'name': modelPath.split('/').last,
      'resources': resourceMap,
      'preselectedEntities': preselectedEntities,
      'selectionColor': selectionColor,
    };

    await _methodChannel.invokeMethod('loadModel', args);
  }

  @override
  Future<void> loadEnvironment(String iblPath, String skyboxPath) async {
    Uint8List? iblBytes;
    Uint8List? skyboxBytes;

    try {
      ByteData iblData = await rootBundle.load(iblPath);
      iblBytes = iblData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error loading IBL file: $e');
    }

    try {
      ByteData skyboxData = await rootBundle.load(skyboxPath);
      skyboxBytes = skyboxData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error loading skybox file: $e');
    }

    await _methodChannel.invokeMethod('loadEnvironment', {
      'iblBytes': iblBytes,
      'skyboxBytes': skyboxBytes,
    });
  }
}
