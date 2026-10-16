import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class PreselectPage extends StatefulWidget {
  const PreselectPage({super.key});

  @override
  State<PreselectPage> createState() => _PreselectPageState();
}

class _PreselectPageState extends State<PreselectPage> {
  static const _preselected = ['Teeth_Lower_1', 'Teeth_Lower_2', 'Neck'];

  final _controller = Interactive3dController();
  int _loadKey = 0;
  List<EntityData> _selected = [];
  var _status = const DemoStatus(
    'Model loaded with 3 preselected parts.',
    'Two lower teeth and the neck are already blue.',
  );

  void _reload() {
    setState(() {
      _loadKey++;
      _selected = [];
      _status = const DemoStatus(
        'Reloaded the model.',
        'The same 3 parts are selected again, whatever you changed before.',
      );
    });
  }

  Future<void> _clear() async {
    await _controller.clearSelections();
    setState(() => _status = const DemoStatus(
          'Cleared all selections.',
          'Preselected parts can be cleared like any other selection.',
        ));
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Preselected parts',
      howTo: 'preselectedEntities selects parts by name as soon as the model '
          'loads, for example to restore what the user picked last time.\n\n'
          'They behave like normal selections: tap to deselect, or clear '
          'them from the controller.',
      viewer: Interactive3d(
        key: ValueKey(_loadKey),
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        preselectedEntities: _preselected,
        onSelectionChanged: (entities) => setState(() => _selected = entities),
      ),
      chips: [
        ('Preselected', _preselected.join(', ')),
        ('Selected', '${_selected.length}'),
      ],
      status: _status,
      sections: [
        DemoActionSection('Controller', [
          DemoAction('Clear all', Colors.indigo, _clear),
        ]),
        DemoActionSection('Load', [
          DemoAction('Reload', Colors.blueGrey, _reload),
        ]),
      ],
    );
  }
}
