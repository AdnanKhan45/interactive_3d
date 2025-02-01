// main.dart
import 'package:flutter/material.dart';
import 'package:interactive_3d_example/glb_loader_example.dart';


void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home:
        // GltfLoaderExample()
      GlbLoaderExample()
    );
  }
}