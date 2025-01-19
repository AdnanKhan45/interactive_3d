import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'interactive_3d_platform_interface.dart';

/// An implementation of [Interactive3dPlatform] that uses method channels.
class MethodChannelInteractive3d extends Interactive3dPlatform {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  MethodChannelInteractive3d(int viewId)
      : _methodChannel = MethodChannel('interactive_3d_$viewId'),
        _eventChannel = EventChannel('interactive_3d_events_$viewId') {
    _eventChannel.receiveBroadcastStream().listen(_onEvent);
  }

  final StreamController<List<EntityData>> _selectionController = StreamController.broadcast();

  @override
  Stream<List<EntityData>> get selectionStream => _selectionController.stream;

  void _onEvent(dynamic event) {
    final Map<dynamic, dynamic> map = event;
    final String eventType = map['event'];
    if (eventType == 'selectionChanged') {
      final List<dynamic> selectedEntities = map['selectedEntities'];
      final List<EntityData> entities = selectedEntities.map((e) {
        return EntityData(id: e['id'], name: e['name']);
      }).toList();
      _selectionController.add(entities);
    }
  }

  @override
  Future<void> loadModel(String modelPath) async {
    ByteData data = await rootBundle.load(modelPath);
    Uint8List modelBytes = data.buffer.asUint8List();
    await _methodChannel.invokeMethod('loadModel', {'modelBytes': modelBytes});
  }

  @override
  Future<void> loadEnvironment(String? iblPath, String? skyboxPath) async {
    Uint8List? iblBytes;
    Uint8List? skyboxBytes;

    if (iblPath != null && skyboxPath != null) {
      try {
        ByteData iblData = await rootBundle.load(iblPath);
        iblBytes = iblData.buffer.asUint8List();
      } catch (e) {
        print('Error loading IBL file: $e');
      }

      try {
        ByteData skyboxData = await rootBundle.load(skyboxPath);
        skyboxBytes = skyboxData.buffer.asUint8List();
      } catch (e) {
        print('Error loading skybox file: $e');
      }
    }

    await _methodChannel.invokeMethod('loadEnvironment', {
      'iblBytes': iblBytes,
      'skyboxBytes': skyboxBytes,
    });
  }
}
