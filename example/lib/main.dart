// main.dart
import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';
import 'package:interactive_3d/interactive_3d_platform_interface.dart';
import 'package:interactive_3d_example/gltf_loader_example.dart';
import 'package:interactive_3d_example/glb_loader_example.dart';


void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home:
        // GltfLoaderExample()
      GlbLoaderExample()
    );
  }
}