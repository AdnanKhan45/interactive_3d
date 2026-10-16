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
  int _loadKey = 0;
  String _tapped = '-';

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Load from a URL',
      howTo: 'Downloads a .glb over the network with modelUrl. Lighting still '
          'comes from local assets. Needs an internet connection.\n\n'
          'Use Reload to download it again.',
      viewer: Interactive3d(
        key: ValueKey(_loadKey),
        modelUrl: DemoAssets.helmetUrl,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        loadingWidget: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Downloading model...'),
            ],
          ),
        ),
        onSelectionChanged: (entities) => setState(
          () => _tapped = entities.isEmpty ? '-' : entities.last.name,
        ),
      ),
      chips: [('Source', 'DamagedHelmet.glb'), ('Last selected', _tapped)],
      status: const DemoStatus(
        'Downloading the model.',
        'The helmet appears once the 4 MB file has downloaded.',
      ),
      sections: [
        DemoActionSection('Load', [
          DemoAction(
            'Reload',
            Colors.blueGrey,
            () => setState(() {
              _loadKey++;
              _tapped = '-';
            }),
          ),
        ]),
      ],
    );
  }
}
