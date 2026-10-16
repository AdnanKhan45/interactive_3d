import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class GltfPage extends StatefulWidget {
  const GltfPage({super.key});

  @override
  State<GltfPage> createState() => _GltfPageState();
}

class _GltfPageState extends State<GltfPage> {
  String _tapped = '-';

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Load a glTF with files',
      howTo: 'A .gltf model whose geometry (.bin) and textures (.png) are '
          'separate files. List them in resources, relative to the .gltf '
          'file, and make sure they are in your pubspec assets.',
      viewer: Interactive3d(
        modelPath: DemoAssets.toothGltf,
        resources: DemoAssets.toothGltfResources,
        iblPath: DemoAssets.venetianIbl,
        skyboxPath: DemoAssets.venetianSkybox,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        onSelectionChanged: (entities) => setState(
          () => _tapped = entities.isEmpty ? '-' : entities.last.name,
        ),
      ),
      chips: [
        ('Files', '${DemoAssets.toothGltfResources.length + 1}'),
        ('Last selected', _tapped),
      ],
      status: const DemoStatus(
        'Model loaded with its .bin and texture files.',
        'Teeth and mouth show their textures. A missing file shows as a '
            'blank or untextured model.',
      ),
    );
  }
}
