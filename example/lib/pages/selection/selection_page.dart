import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class SelectionPage extends StatefulWidget {
  const SelectionPage({super.key});

  @override
  State<SelectionPage> createState() => _SelectionPageState();
}

class _SelectionPageState extends State<SelectionPage> {
  final _controller = Interactive3dController();
  List<EntityData> _selected = [];
  var _status = const DemoStatus(
    'Ready.',
    'Tap several parts. Each turns blue and is added to the selection.',
  );

  Future<void> _unselectLast() async {
    if (_selected.isEmpty) {
      setState(() =>
          _status = const DemoStatus('Nothing selected.', 'Tap a part first.'));
      return;
    }
    final last = _selected.last;
    await _controller.unselectEntities(entityIds: [last.id]);
    setState(() => _status = DemoStatus(
          'Unselected ${last.name} by id.',
          'Only that part returns to its original look.',
        ));
  }

  Future<void> _clearAll() async {
    await _controller.clearSelections();
    setState(() => _status = const DemoStatus(
          'Cleared all selections.',
          'Every part returns to its original look and Selected shows 0.',
        ));
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Tap to select',
      howTo: 'Tapping a named part selects it; tapping it again deselects '
          'it. onSelectionChanged reports the full selection (id and name) '
          'after every change.\n\n'
          'The controller can unselect specific parts by id or clear '
          'everything.',
      viewer: Interactive3d(
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        onSelectionChanged: (entities) => setState(() => _selected = entities),
      ),
      chips: [
        ('Selected', '${_selected.length}'),
        ('Last', _selected.isEmpty ? '-' : _selected.last.name),
      ],
      status: _status,
      sections: [
        DemoActionSection('Controller', [
          DemoAction('Unselect last', Colors.indigo.shade300, _unselectLast),
          DemoAction('Clear all', Colors.indigo, _clearAll),
        ]),
      ],
    );
  }
}
