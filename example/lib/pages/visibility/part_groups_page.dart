import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class PartGroupsPage extends StatefulWidget {
  const PartGroupsPage({super.key});

  @override
  State<PartGroupsPage> createState() => _PartGroupsPageState();
}

class _PartGroupsPageState extends State<PartGroupsPage> {
  final _controller = Interactive3dController();
  final _groups = [
    ModelPartGroup(title: 'Upper teeth', names: DemoAssets.upperTeeth),
    ModelPartGroup(title: 'Lower teeth', names: DemoAssets.lowerTeeth),
    ModelPartGroup(title: 'Jaws', names: DemoAssets.jaws),
    ModelPartGroup(title: 'Tongue', names: DemoAssets.tongue),
    ModelPartGroup(title: 'Palate', names: DemoAssets.palate),
  ];
  final Set<String> _hidden = {};
  var _status = const DemoStatus(
    'Ready.',
    'Tap a group to hide it, tap again to show it.',
  );

  Future<void> _toggle(ModelPartGroup group) async {
    final show = _hidden.contains(group.title);
    await _controller.updatePartGroupConfig(isVisible: show, group: group);
    setState(() {
      show ? _hidden.remove(group.title) : _hidden.add(group.title);
      _status = DemoStatus(
        '${show ? 'Showed' : 'Hid'} ${group.title} '
        '(${group.names.length} parts).',
        show
            ? 'The group is visible again.'
            : 'The whole group disappears; everything else stays.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Show and hide part groups',
      howTo: 'A ModelPartGroup is a named list of part names. '
          'updatePartGroupConfig shows or hides the whole group in one '
          'call, for layered views such as hiding the jaw to see the '
          'teeth roots.',
      viewer: Interactive3d(
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
      ),
      chips: [('Hidden', _hidden.isEmpty ? 'none' : _hidden.join(', '))],
      status: _status,
      sections: [
        DemoActionSection('Groups', [
          for (final group in _groups)
            DemoAction(
              group.title,
              _hidden.contains(group.title)
                  ? Colors.grey.shade500
                  : Colors.green.shade600,
              () => _toggle(group),
            ),
        ]),
      ],
    );
  }
}
