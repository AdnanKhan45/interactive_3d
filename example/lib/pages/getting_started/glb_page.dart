import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class GlbPage extends StatefulWidget {
  const GlbPage({super.key});

  @override
  State<GlbPage> createState() => _GlbPageState();
}

class _GlbPageState extends State<GlbPage> {
  String _tapped = '-';

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Load a GLB model',
      howTo: 'The smallest setup: one .glb file from the app assets, with '
          'image-based lighting and a skybox on Android and an HDR '
          'background on iOS.\n\n'
          'Drag to rotate, pinch to zoom, tap a part to select it. Tap it '
          'again to deselect.',
      viewer: Interactive3d(
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        onSelectionChanged: (entities) => setState(
          () => _tapped = entities.isEmpty ? '-' : entities.last.name,
        ),
      ),
      chips: [('Last selected', _tapped)],
      status: const DemoStatus(
        'Model loaded from assets.',
        'Tap any part: it turns blue and its name shows in Last selected.',
      ),
    );
  }
}
