import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:interactive_3d/interactive_3d.dart';

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

  // Tracked app-side so we can demo persistence via initialMaterialOverrides.
  final Map<String, MaterialOverride> _overrides = {};
  String? _selectedName;

  // Mode flag drives widget rebuilds via _modelKey.
  bool _useInitialOverrides = false;
  int _modelKey = 0;

  String _lastAction = 'Tap a tooth to begin.';
  String _expectation =
      'A tooth name should appear in "Selected" once you tap one.';

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
      _setStatus(action: 'No tooth selected.', expectation: 'Tap a tooth first.');
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
      _setStatus(action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    _overrides.remove(name);
    await _controller.resetEntityMaterial(name);
    _setStatus(
      action: 'Reset override on $name.',
      expectation:
          'Tooth should return to GLB original (no tint). Selection visual is unchanged.',
    );
  }

  Future<void> _resetAll() async {
    _overrides.clear();
    await _controller.resetAllMaterialOverrides();
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
      _setStatus(action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    _setStatus(
      action: 'Uploading $label to $name...',
      expectation: 'Decoding and binding on the native side.',
    );
    final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
    await _controller.setEntityTexture(name: name, bytes: bytes);
    _setStatus(
      action: 'Applied $label to $name.',
      expectation:
          'Tooth surface shows the image; any active color tints it. Tap to add selection (texture hides), deselect to restore.',
    );
  }

  Future<void> _resetTexture() async {
    final name = _selectedName;
    if (name == null) {
      _setStatus(action: 'No tooth selected.', expectation: 'Tap a tooth first.');
      return;
    }
    await _controller.resetEntityTexture(name);
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
      if (!withInitialOverrides) _overrides.clear();
      _lastAction = label;
      _expectation = expectation;
    });
  }

  // -- Helpers ------------------------------------------------------------

  void _setStatus({required String action, required String expectation}) {
    setState(() {
      _lastAction = action;
      _expectation = expectation;
    });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('PBR Override Testbed'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'How to persist overrides',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showPersistenceGuide(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildModel()),
          _StatusPanel(
            selectedName: _selectedName,
            overrideCount: _overrides.length,
            mode: _mode,
            lastAction: _lastAction,
            expectation: _expectation,
          ),
          _ActionBar(
            sections: _sections(),
          ),
        ],
      ),
    );
  }

  Widget _buildModel() {
    return Interactive3d(
      key: ValueKey(_modelKey),
      controller: _controller,
      modelPath: 'assets/models/Tooth-3.glb',
      iblPath: 'assets/models/giuseppe_bridge_4k_ibl.ktx',
      skyboxPath: 'assets/models/giuseppe_bridge_4k_skybox.ktx',
      iOSBackgroundEnvPath: 'assets/models/san_giuseppe_bridge_4k.hdr',
      defaultZoom: 2,
      selectionColor: const [0.0, 0.6, 1.0, 1.0],
      onSelectionChanged: _onSelectionChanged,
      initialMaterialOverrides:
          _useInitialOverrides ? _overrides.values.toList() : null,
    );
  }

  // -- Action sections ----------------------------------------------------

  List<_ActionSection> _sections() => [
        _ActionSection(
          label: 'Full PBR',
          actions: [
            _Action('Cavity', Colors.red.shade700, () => _applyOverride(
                  label: 'Cavity (red matte)',
                  color: const [0.85, 0.15, 0.15, 1.0],
                  metallic: 0.0,
                  roughness: 0.9,
                  expectation:
                      'Red-tinted tooth, enamel texture still visible. Tap to add blue selection on top, tap again to deselect, override returns.',
                )),
            _Action('Filling', Colors.amber.shade700, () => _applyOverride(
                  label: 'Filling (gold metal)',
                  color: const [0.85, 0.7, 0.2, 1.0],
                  metallic: 0.9,
                  roughness: 0.2,
                  expectation:
                      'Tooth looks shiny gold. Light should reflect off it.',
                )),
            _Action('Crown', Colors.grey.shade400, () => _applyOverride(
                  label: 'Crown (white satin)',
                  color: const [1.0, 1.0, 1.0, 1.0],
                  metallic: 0.1,
                  roughness: 0.4,
                  expectation: 'Tooth becomes slightly brighter white.',
                )),
            _Action('Inflamed', Colors.pink.shade300, () => _applyOverride(
                  label: 'Inflamed (pink)',
                  color: const [1.0, 0.5, 0.6, 1.0],
                  metallic: 0.0,
                  roughness: 0.7,
                  expectation: 'Pink tint, texture preserved.',
                )),
          ],
        ),
        _ActionSection(
          label: 'Partial',
          actions: [
            _Action('Color blue', Colors.blue, () => _applyOverride(
                  label: 'Color only blue',
                  color: const [0.2, 0.4, 1.0, 1.0],
                  expectation:
                      'Only color changes. Metallic/roughness from any previous override are preserved (test sticky updates).',
                )),
            _Action('Metallic 1.0', Colors.grey.shade700, () => _applyOverride(
                  label: 'Metallic only 1.0',
                  metallic: 1.0,
                  expectation:
                      'Tooth becomes fully metallic. Color from any previous override is preserved.',
                )),
            _Action('Roughness 0.1', Colors.lightBlue.shade100,
                () => _applyOverride(
                      label: 'Roughness only 0.1',
                      roughness: 0.1,
                      expectation: 'Surface becomes very shiny / smooth.',
                    )),
            _Action('Emissive', Colors.orange.shade200, () => _applyOverride(
                  label: 'Emissive only',
                  emissive: const [0.6, 0.3, 0.0],
                  expectation:
                      'Tooth glows orange even in shadowed areas. Note: emissive replaces any GLB emission map.',
                )),
          ],
        ),
        _ActionSection(
          label: 'Texture',
          actions: [
            _Action('Teeth tex', Colors.brown.shade400, () => _applyTexture(
                  assetPath: 'assets/models/textures/teeth_baseColor.png',
                  label: 'teeth base color',
                  expectation: 'Tooth shows the teeth base-color image.',
                )),
            _Action('Mouth tex', Colors.purple.shade300, () => _applyTexture(
                  assetPath: 'assets/models/textures/mouth_baseColor.png',
                  label: 'mouth base color',
                  expectation: 'Swaps to a different image at runtime.',
                )),
            _Action('Reset tex', Colors.brown.shade200, _resetTexture),
          ],
        ),
        _ActionSection(
          label: 'Reset',
          actions: [
            _Action('Reset selected', Colors.grey.shade600, _resetSelected),
            _Action('Reset all', Colors.grey.shade800, _resetAll),
            _Action('Clear sel.', Colors.indigo.shade300, _clearSelection),
          ],
        ),
        _ActionSection(
          label: 'Reload',
          actions: [
            _Action('Clean', Colors.teal.shade400,
                () => _reload(
                      label: 'Reloaded clean. All overrides cleared.',
                      expectation:
                          'Fresh model. No overrides, no cache, no sequence. Use this between tests.',
                    )),
            _Action('+Initial', Colors.teal.shade600, () {
              if (_overrides.isEmpty) {
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
          ],
        ),
        _ActionSection(
          label: 'Stress',
          actions: [
            _Action('Run 50x', Colors.deepOrange.shade400, _stress),
          ],
        ),
      ];
}

// ============================================================================
// UI primitives
// ============================================================================

class _StatusPanel extends StatelessWidget {
  final String? selectedName;
  final int overrideCount;
  final String mode;
  final String lastAction;
  final String expectation;

  const _StatusPanel({
    required this.selectedName,
    required this.overrideCount,
    required this.mode,
    required this.lastAction,
    required this.expectation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip('Selected', selectedName ?? '-'),
              const SizedBox(width: 6),
              _Chip('Overrides', '$overrideCount'),
              const SizedBox(width: 6),
              _Chip('Mode', mode),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Action: $lastAction',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Expect: $expectation',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  const _Chip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final List<_ActionSection> sections;
  const _ActionBar({required this.sections});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            for (final section in sections) ...[
              _Section(section),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final _ActionSection section;
  const _Section(this.section);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            section.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Row(
          children: [
            for (final action in section.actions) ...[
              _ActionButton(action),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final _Action action;
  const _ActionButton(this.action);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: action.color,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          action.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ActionSection {
  final String label;
  final List<_Action> actions;
  const _ActionSection({required this.label, required this.actions});
}

class _Action {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Action(this.label, this.color, this.onTap);
}
