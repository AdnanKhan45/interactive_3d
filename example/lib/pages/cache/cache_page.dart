import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

class CachePage extends StatefulWidget {
  const CachePage({super.key});

  @override
  State<CachePage> createState() => _CachePageState();
}

class _CachePageState extends State<CachePage> {
  final _controller = Interactive3dController();
  int _loadKey = 0;
  List<String> _cached = [];
  int _selectedCount = 0;
  var _status = const DemoStatus(
    'Ready.',
    'Tap a few parts. Each selected part is also saved, so Cached goes up.',
  );

  void _reopen() {
    setState(() {
      _loadKey++;
      _selectedCount = 0;
      _status = const DemoStatus(
        'Reopened the model.',
        'Saved parts come back in yellow, the cache color.',
      );
    });
  }

  Future<void> _run(Future<void> Function() call, DemoStatus done) async {
    await call();
    setState(() => _status = done);
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Saved selections (cache)',
      howTo: 'With enableCache, every part the user selects is saved on the '
          'device for this model file and shown in cacheColor the next '
          'time the model opens.\n\n'
          'Tapping a cached part takes it out of the cache and selects it '
          'normally. The controller can refresh, remove, or clear cached '
          'parts.',
      viewer: Interactive3d(
        key: ValueKey(_loadKey),
        controller: _controller,
        modelPath: DemoAssets.toothGlb,
        iblPath: DemoAssets.bridgeIbl,
        skyboxPath: DemoAssets.bridgeSkybox,
        iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
        defaultZoom: 2,
        selectionColor: DemoAssets.selectionBlue,
        enableCache: true,
        cacheColor: const [0.8, 0.8, 0.2, 0.6],
        clearSelectionOnHighlight: true,
        onCacheSelectionChanged: (names) => setState(() => _cached = names),
        onSelectionChanged: (entities) =>
            setState(() => _selectedCount = entities.length),
      ),
      chips: [
        ('Cached', '${_cached.length}'),
        ('Selected', '$_selectedCount'),
      ],
      status: _status,
      sections: [
        DemoActionSection('Load', [
          DemoAction('Reopen', Colors.blueGrey, _reopen),
        ]),
        DemoActionSection('Cache', [
          DemoAction(
            'Refresh',
            Colors.amber.shade700,
            () => _run(
              _controller.refreshCacheHighlights,
              const DemoStatus(
                'Refreshed cache highlights.',
                'Every cached part shows yellow. Current selections are '
                    'cleared because clearSelectionOnHighlight is on.',
              ),
            ),
          ),
          DemoAction(
            'Remove 2',
            Colors.orange.shade700,
            () => _run(
              () => _controller.removeFromCache(['Teeth_Lower_1', 'Neck']),
              const DemoStatus(
                'Removed Teeth_Lower_1 and Neck from the cache.',
                'Reopen: those two no longer come back yellow.',
              ),
            ),
          ),
          DemoAction(
            'Clear cache',
            Colors.red.shade400,
            () => _run(
              _controller.clearCache,
              const DemoStatus(
                'Cleared the cache.',
                'Cached shows 0. Reopen: nothing comes back yellow.',
              ),
            ),
          ),
        ]),
        DemoActionSection('Selection', [
          DemoAction(
            'Clear sel.',
            Colors.indigo,
            () => _run(
              _controller.clearSelections,
              const DemoStatus(
                'Cleared selections.',
                'Blue highlights go away. The cache is not touched.',
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
