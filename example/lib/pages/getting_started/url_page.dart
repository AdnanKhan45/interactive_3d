import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class UrlPage extends StatefulWidget {
  const UrlPage({super.key});

  @override
  State<UrlPage> createState() => _UrlPageState();
}

class _UrlPageState extends State<UrlPage> {
  static const _brokenUrl =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/missing.glb';

  int _loadKey = 0;
  String _url = DemoAssets.helmetUrl;
  String _tapped = '-';
  var _status = const DemoStatus(
    'Downloading the model.',
    'The loading overlay stays up until the helmet is on screen.',
  );

  void _load(String url, DemoStatus status) {
    setState(() {
      _url = url;
      _loadKey++;
      _tapped = '-';
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Load from a URL',
      howTo: 'Downloads a .glb over the network with modelUrl. Lighting still '
          'comes from local assets. Needs an internet connection.\n\n'
          'loadingWidget covers the view until the model is drawn. '
          'errorBuilder replaces it when loading fails, and onModelLoaded / '
          'onModelLoadError report the outcome. Retry by rebuilding the '
          'widget with a new key.',
      viewer: Interactive3d(
        key: ValueKey(_loadKey),
        modelUrl: _url,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        loadingWidget: const _Overlay(
          icon: CircularProgressIndicator(color: Colors.white),
          message: 'Downloading model...',
        ),
        errorBuilder: (context, error) => _Overlay(
          icon: const Icon(Icons.cloud_off, color: Colors.white, size: 40),
          message: 'Could not load the model.',
          action: OutlinedButton(
            onPressed: () => _load(
              DemoAssets.helmetUrl,
              const DemoStatus('Retrying.', 'The helmet loads normally.'),
            ),
            child: const Text('Retry'),
          ),
        ),
        onModelLoaded: () => setState(() => _status = const DemoStatus(
              'onModelLoaded fired.',
              'The helmet is on screen and the overlay is gone.',
            )),
        onModelLoadError: (error, _) => setState(() => _status = DemoStatus(
              'onModelLoadError fired.',
              'The error view shows instead of a blank area. Error: $error',
            )),
        onSelectionChanged: (entities) => setState(
          () => _tapped = entities.isEmpty ? '-' : entities.last.name,
        ),
      ),
      chips: [
        ('Source', _url.split('/').last),
        ('Last selected', _tapped),
      ],
      status: _status,
      sections: [
        DemoActionSection('Load', [
          DemoAction(
            'Reload',
            Colors.blueGrey,
            () => _load(
              DemoAssets.helmetUrl,
              const DemoStatus(
                'Downloading the model again.',
                'The loading overlay shows until the helmet is drawn.',
              ),
            ),
          ),
          DemoAction(
            'Broken URL',
            Colors.red.shade400,
            () => _load(
              _brokenUrl,
              const DemoStatus(
                'Loading a URL that does not exist.',
                'The loading overlay is replaced by the error view.',
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

class _Overlay extends StatelessWidget {
  final Widget icon;
  final String message;
  final Widget? action;

  const _Overlay({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white)),
            if (action != null) ...[
              const SizedBox(height: 12),
              Theme(
                data: ThemeData.dark(),
                child: action!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
