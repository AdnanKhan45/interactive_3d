import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:async';

abstract class Interactive3dPlatform extends PlatformInterface {
  /// Constructs a Interactive3dPlatform.
  Interactive3dPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Verify the instance
  static void verify(Interactive3dPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
  }

  // Method to load the model
  Future<void> loadModel(String modelPath);

  // Method to load the environment
  Future<void> loadEnvironment(String iblPath, String skyboxPath);

  // Stream to receive selection changes
  Stream<List<EntityData>> get selectionStream;

}

class EntityData {
  final int id;
  final String name;

  EntityData({required this.id, required this.name});
}
