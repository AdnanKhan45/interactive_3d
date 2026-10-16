import 'package:flutter/material.dart';

import 'pages/cache/cache_page.dart';
import 'pages/camera/camera_page.dart';
import 'pages/diagnostics/memory_test_page.dart';
import 'pages/getting_started/glb_page.dart';
import 'pages/getting_started/gltf_page.dart';
import 'pages/getting_started/url_page.dart';
import 'pages/materials/patch_colors_page.dart';
import 'pages/materials/pbr_testbed_page.dart';
import 'pages/selection/preselect_page.dart';
import 'pages/selection/selection_page.dart';
import 'pages/selection/sequence_page.dart';
import 'pages/visibility/part_groups_page.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'interactive_3d examples',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class _Demo {
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  const _Demo(this.icon, this.title, this.subtitle, this.builder);
}

class _DemoGroup {
  final String title;
  final List<_Demo> demos;
  const _DemoGroup(this.title, this.demos);
}

final _groups = [
  _DemoGroup('Getting started', [
    _Demo(Icons.view_in_ar, 'Load a GLB model',
        'One file from assets, with lighting', (_) => const GlbPage()),
    _Demo(Icons.folder_open, 'Load a glTF with files',
        'Separate .bin and texture files', (_) => const GltfPage()),
    _Demo(Icons.cloud_download_outlined, 'Load from a URL',
        'Download a model over the network', (_) => const UrlPage()),
  ]),
  _DemoGroup('Selection', [
    _Demo(Icons.touch_app_outlined, 'Tap to select',
        'Select, unselect by id, clear all', (_) => const SelectionPage()),
    _Demo(
        Icons.format_list_numbered,
        'Selection order',
        'Only neighbouring parts can be picked next',
        (_) => const SequencePage()),
    _Demo(Icons.playlist_add_check, 'Preselected parts',
        'Select parts by name on load', (_) => const PreselectPage()),
  ]),
  _DemoGroup('Cache', [
    _Demo(Icons.bookmark_border, 'Saved selections',
        'Selections that come back next time', (_) => const CachePage()),
  ]),
  _DemoGroup('Visibility', [
    _Demo(Icons.layers_outlined, 'Show and hide part groups',
        'Toggle named groups of parts', (_) => const PartGroupsPage()),
  ]),
  _DemoGroup('Materials and textures', [
    _Demo(
        Icons.palette_outlined,
        'Materials and textures',
        'Runtime color, PBR, and texture overrides',
        (_) => const PbrOverrideTestbed()),
    _Demo(Icons.format_color_fill, 'Per-part selection colors',
        'patchColors for specific parts', (_) => const PatchColorsPage()),
  ]),
  _DemoGroup('Camera', [
    _Demo(Icons.zoom_in, 'Camera', 'Default zoom and zoom from code',
        (_) => const CameraPage()),
  ]),
  _DemoGroup('Diagnostics', [
    _Demo(Icons.memory, 'Memory test', 'Open and close the viewer repeatedly',
        (_) => const MemoryTestPage()),
  ]),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('interactive_3d examples')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Text(
                group.title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final demo in group.demos)
              ListTile(
                leading: Icon(demo.icon, color: theme.colorScheme.primary),
                title: Text(demo.title),
                subtitle: Text(demo.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: demo.builder)),
              ),
          ],
        ],
      ),
    );
  }
}
