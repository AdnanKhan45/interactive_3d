import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class PatchColorsPage extends StatefulWidget {
  const PatchColorsPage({super.key});

  @override
  State<PatchColorsPage> createState() => _PatchColorsPageState();
}

class _PatchColorsPageState extends State<PatchColorsPage> {
  static const _jawOrange = [1.0, 0.5, 0.0, 1.0];
  static const _palatePurple = [0.55, 0.2, 0.85, 1.0];

  final _controller = Interactive3dController();
  String _last = '-';
  var _status = const DemoStatus(
    'Ready.',
    'Tap a jaw or the palate: each gets its own color. Teeth stay blue.',
  );

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Per-part selection colors',
      howTo: 'patchColors gives specific parts their own selection color '
          'instead of the global selectionColor. It only changes how a '
          'selected part looks.\n\n'
          'To restyle parts without selecting them, use the materials API '
          'on the Materials and textures page instead.',
      viewer: Interactive3d(
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        patchColors: [
          for (final name in DemoAssets.jaws)
            PatchColor(name: name, color: _jawOrange),
          for (final name in DemoAssets.palate)
            PatchColor(name: name, color: _palatePurple),
        ],
        onSelectionChanged: (entities) => setState(
          () => _last = entities.isEmpty ? '-' : entities.last.name,
        ),
      ),
      chips: [('Last selected', _last)],
      status: _status,
      sections: [
        DemoActionSection('Controller', [
          DemoAction('Clear all', Colors.indigo, () async {
            await _controller.clearSelections();
            setState(() => _status = const DemoStatus(
                  'Cleared all selections.',
                  'Every part returns to its original look.',
                ));
          }),
        ]),
      ],
    );
  }
}
