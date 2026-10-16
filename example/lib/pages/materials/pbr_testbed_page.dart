import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:interactive_3d/interactive_3d.dart';

import '../../shared/demo_assets.dart';
import '../../shared/demo_scaffold.dart';

/// End-to-end testbed for runtime PBR overrides.
/// Stays on the clean path: no cache, no patchColors, no preselectedEntities.
/// The plugin renders. Your app owns the state and persistence.
class PbrOverrideTestbed extends StatefulWidget {
  const PbrOverrideTestbed({super.key});

  @override
  State<PbrOverrideTestbed> createState() => _PbrOverrideTestbedState();
}

class _PbrOverrideTestbedState extends State<PbrOverrideTestbed> {
  final _controller = Interactive3dController();

  // Tracked app-side so we can demo persistence via initialMaterialOverrides
  // and initialEntityTextures.
  final Map<String, MaterialOverride> _overrides = {};
  final Map<String, Uint8List> _textures = {};
  String? _selectedName;

  // Mode flag drives widget rebuilds via _modelKey.
  bool _useInitialOverrides = false;
  int _modelKey = 0;

  var _status = const DemoStatus(
    'Tap a tooth to begin.',
    'A tooth name should appear in "Selected" once you tap one.',
  );

  // -- Selection ----------------------------------------------------------

  void _onSelectionChanged(List<EntityData> entities) {
    setState(() {
      _selectedName = entities.isEmpty ? null : entities.first.name;
    });
  }

  // -- Override actions ---------------------------------------------------

  Future<void> _applyOverride({
    required String label,
    required String expectation,
    List<double>? color,
    double? metallic,
    double? roughness,
    List<double>? emissive,
  }) async {
    final name = _selectedName;
    if (name == null) {
      _setStatus(
          action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    final update = MaterialOverride(
      name: name,
      color: color,
      metallic: metallic,
      roughness: roughness,
      emissive: emissive,
    );
    _overrides[name] = _merge(_overrides[name], update);
    await _controller.setEntityMaterial(
      name: name,
      color: color,
      metallic: metallic,
      roughness: roughness,
      emissive: emissive,
    );
    _setStatus(action: 'Applied $label to $name.', expectation: expectation);
  }

  Future<void> _resetSelected() async {
    final name = _selectedName;
    if (name == null) {
      _setStatus(
          action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    _overrides.remove(name);
    _textures.remove(name);
    await _controller.resetEntityMaterial(name);
    _setStatus(
      action: 'Reset override on $name.',
      expectation:
          'Tooth should return to GLB original (no tint). Selection visual is unchanged.',
    );
  }

  Future<void> _resetAll() async {
    _overrides.clear();
    _textures.clear();
    await _controller.resetAllMaterialOverrides();
    await _controller.resetAllEntityTextures();
    _setStatus(
      action: 'Reset every active override.',
      expectation:
          'All overridden teeth should snap back to GLB original. Selection visual is unchanged.',
    );
  }

  Future<void> _clearSelection() async {
    await _controller.clearSelections();
    _setStatus(
      action: 'Cleared selection.',
      expectation:
          'Selection ring removed. Overridden teeth should still show their override.',
    );
  }

  // -- Texture actions ----------------------------------------------------

  Future<void> _applyTexture({
    required String assetPath,
    required String label,
    required String expectation,
  }) async {
    final name = _selectedName;
    if (name == null) {
      _setStatus(
          action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    _setStatus(
      action: 'Uploading $label to $name...',
      expectation: 'Decoding and binding on the native side.',
    );
    final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
    await _controller.setEntityTexture(name: name, bytes: bytes);
    _textures[name] = bytes;
    _setStatus(
      action: 'Applied $label to $name.',
      expectation:
          'Tooth surface shows the image; any active color tints it. Tap to add selection (texture hides), deselect to restore.',
    );
  }

  Future<void> _resetTexture() async {
    final name = _selectedName;
    if (name == null) {
      _setStatus(
          action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    await _controller.resetEntityTexture(name);
    _textures.remove(name);
    _setStatus(
      action: 'Reset texture on $name.',
      expectation:
          'Texture removed, GLB base color returns. Any color/PBR override stays.',
    );
  }

  // -- Stress test --------------------------------------------------------

  Future<void> _stress() async {
    final name = _selectedName ?? 'Teeth_Lower_1';
    _setStatus(
      action: 'Running 50x apply/reset cycle on $name...',
      expectation: 'Hold tight, this takes a couple seconds.',
    );
    for (int i = 0; i < 50; i++) {
      await _controller.setEntityMaterial(
        name: name,
        color: const [1.0, 0.0, 0.0, 1.0],
      );
      await _controller.resetEntityMaterial(name);
    }
    _setStatus(
      action: 'Completed 50x apply/reset on $name.',
      expectation:
          'Tooth shows GLB original. On Android, check logs for MaterialInstance leak warnings.',
    );
  }

  // -- Reload (forces a fresh model load with new params) -----------------

  void _reload({
    bool withInitialOverrides = false,
    required String label,
    required String expectation,
  }) {
    setState(() {
      _useInitialOverrides = withInitialOverrides;
      _modelKey++;
      _selectedName = null;
      if (!withInitialOverrides) {
        _overrides.clear();
        _textures.clear();
      }
      _status = DemoStatus(label, expectation);
    });
  }

  // -- Helpers ------------------------------------------------------------

  void _setStatus({required String action, required String expectation}) {
    setState(() => _status = DemoStatus(action, expectation));
  }

  void _showPersistenceGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Persisting overrides app-side'),
        content: const SingleChildScrollView(
          child: Text(
            'The plugin does not persist overrides. Your app owns the state '
            'and survives across restarts.\n\n'
            '1. Store overrides in your own layer (SharedPreferences, Hive, '
            'SQLite, or a remote DB). A simple Map<String, MaterialOverride> '
            'or a list of MaterialOverride works.\n\n'
            '2. On any runtime change, mirror it to storage:\n'
            '   controller.setEntityMaterial(name: ..., color: ...);\n'
            '   await repo.save(currentOverrides);\n\n'
            '3. On widget construction, read from storage and pass via\n'
            '   initialMaterialOverrides:\n'
            '   final saved = await repo.load();\n'
            '   Interactive3d(\n'
            '     initialMaterialOverrides: saved,\n'
            '     ...\n'
            '   );\n\n'
            'Keep enableCache false. Do not use patchColors or '
            'preselectedEntities for styling, those are legacy paths kept '
            'for backward compatibility.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  MaterialOverride _merge(MaterialOverride? existing, MaterialOverride update) {
    return MaterialOverride(
      name: update.name,
      color: update.color ?? existing?.color,
      metallic: update.metallic ?? existing?.metallic,
      roughness: update.roughness ?? existing?.roughness,
      emissive: update.emissive ?? existing?.emissive,
    );
  }

  String get _mode => _useInitialOverrides ? 'initialOverrides' : 'clean';

  // -- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Materials and textures',
      howTo: 'Runtime PBR overrides and base color textures on the clean '
          'path: no cache, no patchColors, no preselectedEntities.\n\n'
          'Tap a tooth, then use the actions. Color tints the GLB texture '
          'instead of replacing it, partial updates keep earlier values, and '
          'selection wins visually while active. Reload with +Initial to '
          'test restoring overrides on load.',
      appBarActions: [
        IconButton(
          tooltip: 'How to persist overrides',
          icon: const Icon(Icons.save_outlined),
          onPressed: () => _showPersistenceGuide(context),
        ),
      ],
      viewer: _buildModel(),
      chips: [
        ('Selected', _selectedName ?? '-'),
        ('Overrides', '${_overrides.length}'),
        ('Mode', _mode),
      ],
      status: _status,
      sections: _sections(),
    );
  }

  Widget _buildModel() {
    return Interactive3d(
      key: ValueKey(_modelKey),
      controller: _controller,
      modelPath: DemoAssets.toothGlb,
      iblPath: DemoAssets.bridgeIbl,
      skyboxPath: DemoAssets.bridgeSkybox,
      iOSBackgroundEnvPath: DemoAssets.bridgeHdr,
      defaultZoom: 2,
      selectionColor: DemoAssets.selectionBlue,
      onSelectionChanged: _onSelectionChanged,
      initialMaterialOverrides:
          _useInitialOverrides ? _overrides.values.toList() : null,
      initialEntityTextures: _useInitialOverrides
          ? _textures.entries
              .map((e) => EntityTexture(name: e.key, bytes: e.value))
              .toList()
          : null,
    );
  }

  // -- Action sections ----------------------------------------------------

  List<DemoActionSection> _sections() => [
        DemoActionSection('Full PBR', [
          DemoAction(
              'Cavity',
              Colors.red.shade700,
              () => _applyOverride(
                    label: 'Cavity (red matte)',
                    color: const [0.85, 0.15, 0.15, 1.0],
                    metallic: 0.0,
                    roughness: 0.9,
                    expectation:
                        'Red-tinted tooth, enamel texture still visible. Tap to add blue selection on top, tap again to deselect, override returns.',
                  )),
          DemoAction(
              'Filling',
              Colors.amber.shade700,
              () => _applyOverride(
                    label: 'Filling (gold metal)',
                    color: const [0.85, 0.7, 0.2, 1.0],
                    metallic: 0.9,
                    roughness: 0.2,
                    expectation:
                        'Tooth looks shiny gold. Light should reflect off it.',
                  )),
          DemoAction(
              'Crown',
              Colors.grey.shade400,
              () => _applyOverride(
                    label: 'Crown (white satin)',
                    color: const [1.0, 1.0, 1.0, 1.0],
                    metallic: 0.1,
                    roughness: 0.4,
                    expectation: 'Tooth becomes slightly brighter white.',
                  )),
          DemoAction(
              'Inflamed',
              Colors.pink.shade300,
              () => _applyOverride(
                    label: 'Inflamed (pink)',
                    color: const [1.0, 0.5, 0.6, 1.0],
                    metallic: 0.0,
                    roughness: 0.7,
                    expectation: 'Pink tint, texture preserved.',
                  )),
        ]),
        DemoActionSection('Partial', [
          DemoAction(
              'Color blue',
              Colors.blue,
              () => _applyOverride(
                    label: 'Color only blue',
                    color: const [0.2, 0.4, 1.0, 1.0],
                    expectation:
                        'Only color changes. Metallic/roughness from any previous override are preserved (test sticky updates).',
                  )),
          DemoAction(
              'Metallic 1.0',
              Colors.grey.shade700,
              () => _applyOverride(
                    label: 'Metallic only 1.0',
                    metallic: 1.0,
                    expectation:
                        'Tooth becomes fully metallic. Color from any previous override is preserved.',
                  )),
          DemoAction(
              'Roughness 0.1',
              Colors.lightBlue.shade100,
              () => _applyOverride(
                    label: 'Roughness only 0.1',
                    roughness: 0.1,
                    expectation: 'Surface becomes very shiny / smooth.',
                  )),
          DemoAction(
              'Emissive',
              Colors.orange.shade200,
              () => _applyOverride(
                    label: 'Emissive only',
                    emissive: const [0.6, 0.3, 0.0],
                    expectation:
                        'Tooth glows orange even in shadowed areas. Note: emissive replaces any GLB emission map.',
                  )),
        ]),
        DemoActionSection('Texture', [
          DemoAction(
              'Teeth tex',
              Colors.brown.shade400,
              () => _applyTexture(
                    assetPath: DemoAssets.teethTexture,
                    label: 'teeth base color',
                    expectation: 'Tooth shows the teeth base-color image.',
                  )),
          DemoAction(
              'Mouth tex',
              Colors.purple.shade300,
              () => _applyTexture(
                    assetPath: DemoAssets.mouthTexture,
                    label: 'mouth base color',
                    expectation: 'Swaps to a different image at runtime.',
                  )),
          DemoAction('Reset tex', Colors.brown.shade200, _resetTexture),
        ]),
        DemoActionSection('Reset', [
          DemoAction('Reset selected', Colors.grey.shade600, _resetSelected),
          DemoAction('Reset all', Colors.grey.shade800, _resetAll),
          DemoAction('Clear sel.', Colors.indigo.shade300, _clearSelection),
        ]),
        DemoActionSection('Reload', [
          DemoAction(
              'Clean',
              Colors.teal.shade400,
              () => _reload(
                    label: 'Reloaded clean. All overrides cleared.',
                    expectation:
                        'Fresh model. No overrides, no cache, no sequence. Use this between tests.',
                  )),
          DemoAction('+Initial', Colors.teal.shade600, () {
            if (_overrides.isEmpty && _textures.isEmpty) {
              _setStatus(
                action: 'No overrides to seed.',
                expectation:
                    'Apply at least one override first, then press +Initial to test persistence on reload.',
              );
              return;
            }
            _reload(
              withInitialOverrides: true,
              label: 'Reloaded with ${_overrides.length} initial overrides.',
              expectation:
                  'Previously overridden teeth should appear pre-painted. Tap and deselect to confirm override is the deselect target.',
            );
          }),
        ]),
        DemoActionSection('Stress', [
          DemoAction('Run 50x', Colors.deepOrange.shade400, _stress),
        ]),
      ];
}
