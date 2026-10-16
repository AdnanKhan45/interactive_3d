import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class SequencePage extends StatefulWidget {
  const SequencePage({super.key});

  @override
  State<SequencePage> createState() => _SequencePageState();
}

class _SequencePageState extends State<SequencePage> {
  final _controller = Interactive3dController();
  List<EntityData> _selected = [];
  var _status = const DemoStatus(
    'Ready.',
    'Tap any lower tooth to start. Next taps must be a neighbour of an '
        'already selected tooth.',
  );

  Future<void> _clear() async {
    await _controller.clearSelections();
    setState(() => _status = const DemoStatus(
          'Cleared all selections.',
          'The order resets: the next tooth you tap can be any tooth.',
        ));
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Selection order',
      howTo: 'selectionSequence limits which part can be tapped next. Here '
          'each jaw is a group ordered tooth 1 to 16:\n\n'
          '- The first tooth in a group can be any tooth.\n'
          '- After that, only a neighbour of a selected tooth is accepted '
          '(either side, because bidirectional is true).\n'
          '- Out-of-order taps are ignored and nothing changes.\n'
          '- Deselecting is always allowed. Parts outside the groups are '
          'never restricted.',
      viewer: Interactive3d(
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        selectionSequence: [
          SequenceConfig(
            group: 'Teeth_Lower',
            order: DemoAssets.lowerTeeth,
            bidirectional: true,
          ),
          SequenceConfig(
            group: 'Teeth_Upper',
            order: DemoAssets.upperTeeth,
            bidirectional: true,
          ),
        ],
        onSelectionChanged: (entities) => setState(() {
          _selected = entities;
          if (entities.isNotEmpty) {
            _status = const DemoStatus(
              'Selection changed.',
              'Try a tooth two places away: it should be ignored.',
            );
          }
        }),
      ),
      chips: [
        ('Selected', '${_selected.length}'),
        ('Last', _selected.isEmpty ? '-' : _selected.last.name),
      ],
      status: _status,
      sections: [
        DemoActionSection('Controller', [
          DemoAction('Clear all', Colors.indigo, _clear),
        ]),
      ],
    );
  }
}
