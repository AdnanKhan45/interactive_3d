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
  static const _step = 0.25;

  final _controller = Interactive3dController();
  int _loadKey = 0;
  double? _defaultZoom = 1.0;
  String _lastCall = '-';
  var _status = const DemoStatus(
    'Model loaded at defaultZoom 1.0.',
    'Rotate or pinch, then try the buttons. Reset returns to this view.',
  );

  Future<void> _run(
      String call, Future<void> Function() action, DemoStatus status) async {
    await action();
    if (!mounted) return;
    setState(() {
      _lastCall = call;
      _status = status;
    });
  }

  void _toggleDefaultZoom() {
    setState(() {
      _defaultZoom = _defaultZoom == null ? 1.0 : null;
      _loadKey++;
      _lastCall = '-';
      _status = DemoStatus(
        'Reloaded with defaultZoom ${_defaultZoom ?? 'unset'}.',
        _defaultZoom == null
            ? 'The platform starting view is used. Reset returns to it.'
            : 'The model starts at zoom 1.0. Reset returns to it.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Camera',
      howTo: 'The plugin frames the model when it loads. defaultZoom sets the '
          'starting zoom, and the same value looks the same on Android and '
          'iOS.\n\n'
          'zoomBy adds to the current zoom, even after pinching, and stays '
          'within 0.5 to 3.0, which suits zoom buttons. setCameraZoomLevel '
          'jumps to an exact level. resetCamera undoes rotation and zoom.',
      viewer: Interactive3d(
        key: ValueKey(_loadKey),
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: _defaultZoom,
        selectionColor: DemoAssets.selectionBlue,
      ),
      chips: [
        ('defaultZoom', '${_defaultZoom ?? 'unset'}'),
        ('Last call', _lastCall),
      ],
      status: _status,
      sections: [
        DemoActionSection('zoomBy', [
          DemoAction(
            '-',
            Colors.deepPurple,
            () => _run(
              'zoomBy(-$_step)',
              () => _controller.zoomBy(-_step),
              const DemoStatus('Zoomed out one step.',
                  'The model moves away a little. It stops at 0.5.'),
            ),
          ),
          DemoAction(
            '+',
            Colors.deepPurple,
            () => _run(
              'zoomBy($_step)',
              () => _controller.zoomBy(_step),
              const DemoStatus('Zoomed in one step.',
                  'The model moves closer a little, even after a pinch. It stops at 3.0.'),
            ),
          ),
        ]),
        DemoActionSection('resetCamera', [
          DemoAction(
            'Reset',
            Colors.teal,
            () => _run(
              'resetCamera()',
              _controller.resetCamera,
              const DemoStatus('Reset the camera.',
                  'Rotation and zoom are undone; the starting view is back.'),
            ),
          ),
        ]),
        DemoActionSection('setCameraZoomLevel', [
          for (final level in _levels)
            DemoAction(
              '${level}x',
              Colors.deepPurple.shade300,
              () => _run(
                'setCameraZoomLevel($level)',
                () => _controller.setCameraZoomLevel(level),
                DemoStatus('Set zoom level to $level.',
                    'The model jumps to that zoom, keeping its rotation.'),
              ),
            ),
        ]),
        DemoActionSection('Load', [
          DemoAction(
            _defaultZoom == null ? 'Set 1.0' : 'Unset',
            Colors.blueGrey,
            _toggleDefaultZoom,
          ),
        ]),
      ],
    );
  }
}
