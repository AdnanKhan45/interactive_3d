import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const _levels = [0.75, 1.0, 1.5, 2.0, 3.0];

  final _controller = Interactive3dController();
  double? _level;
  var _status = const DemoStatus(
    'Model loaded at defaultZoom 1.0.',
    'The whole model fits the view.',
  );

  Future<void> _zoomTo(double level) async {
    await _controller.setCameraZoomLevel(level);
    setState(() {
      _level = level;
      _status = DemoStatus(
        'Set zoom level to $level.',
        level > 1.0
            ? 'The model moves closer right away, without touching it.'
            : 'The model moves away or back to its fitted size.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Camera',
      howTo: 'The plugin frames the model automatically when it loads. '
          'defaultZoom sets the starting zoom, and setCameraZoomLevel '
          'changes it from code: above 1.0 zooms in, below zooms out.\n\n'
          'Drag to rotate and pinch to zoom as usual.',
      viewer: Interactive3d(
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 1.0,
        selectionColor: DemoAssets.selectionBlue,
      ),
      chips: [('Zoom level', _level?.toString() ?? '1.0 (default)')],
      status: _status,
      sections: [
        DemoActionSection('setCameraZoomLevel', [
          for (final level in _levels)
            DemoAction(
                '${level}x', Colors.deepPurple.shade400, () => _zoomTo(level)),
        ]),
      ],
    );
  }
}
