import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

/// This page is specifically designed to test memory leaks
/// by repeatedly navigating back and forth to the 3D viewer
class MemoryTestPage extends StatefulWidget {
  const MemoryTestPage({super.key});

  @override
  State<MemoryTestPage> createState() => _MemoryTestPageState();
}

class _MemoryTestPageState extends State<MemoryTestPage> {
  int navigationCount = 0;
  final List<String> navigationLog = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Leak Test'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memory Leak Test Instructions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Tap "Open 3D Viewer" to load the model\n'
                          '2. Interact with the model if you want\n'
                          '3. Press back button to return here\n'
                          '4. Repeat steps 1-3 multiple times (10-15 times)\n'
                          '5. If the app doesn\'t crash, memory leak is fixed! ✅',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Navigation Counter
            Card(
              color: navigationCount > 10
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Navigation Count',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$navigationCount',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: navigationCount > 10
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                    if (navigationCount > 10)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          '🎉 Great! You\'ve passed 10 navigations!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            ElevatedButton.icon(
              onPressed: _openViewer,
              icon: const Icon(Icons.rotate_90_degrees_ccw),
              label: const Text('Open 3D Viewer'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _resetCounter,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset Counter'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),

            // Navigation Log
            Expanded(
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Navigation Log',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (navigationLog.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  navigationLog.clear();
                                });
                              },
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: navigationLog.isEmpty
                          ? const Center(
                        child: Text(
                          'No navigation history yet.\nTap "Open 3D Viewer" to start.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                          : ListView.builder(
                        itemCount: navigationLog.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.deepPurple,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: Text(navigationLog[index]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer() async {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      navigationCount++;
      navigationLog.add('[$timestamp] Navigated to 3D Viewer (#$navigationCount)');
    });

    // Navigate to the 3D viewer
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MemoryTestViewerPage(),
      ),
    );

    // When we come back
    setState(() {
      final returnTime = DateTime.now().toString().substring(11, 19);
      navigationLog.add('[$returnTime] Returned from 3D Viewer (#$navigationCount)');
    });
  }

  void _resetCounter() {
    setState(() {
      navigationCount = 0;
      navigationLog.clear();
    });
  }
}

/// The actual 3D Viewer page for memory testing
class MemoryTestViewerPage extends StatefulWidget {
  const MemoryTestViewerPage({super.key});

  @override
  State<MemoryTestViewerPage> createState() => _MemoryTestViewerPageState();
}

class _MemoryTestViewerPageState extends State<MemoryTestViewerPage> {
  final Interactive3dController _controller = Interactive3dController();
  List<EntityData> _selectedEntities = [];

  @override
  void dispose() {
    // Important: Ensure controller is properly detached
    debugPrint('MemoryTestViewerPage disposing...');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Model Viewer - Memory Test'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Memory Test Info'),
                  content: const Text(
                    'Interact with the model, then press back.\n\n'
                        'If you can do this 10+ times without crashing, '
                        'the memory leak is fixed!',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 3D Viewer
          Expanded(
            flex: 3,
            child: Interactive3d(
              controller: _controller,
              enableCache: true,
              clearSelectionOnHighlight: true,
              cacheColor: const [0.7, 0.7, 0.2, 0.5],
              onCacheSelectionChanged: (cachedNames) {
                debugPrint('Cached: $cachedNames');
              },
              // solidBackgroundColor: [0.92, 0.92, 0.92, 1.0],
              modelPath: 'assets/models/Tooth-3.glb',
              iblPath: 'assets/models/giuseppe_bridge_4k_ibl.ktx',
              skyboxPath: 'assets/models/giuseppe_bridge_4k_skybox.ktx',
              iOSBackgroundEnvPath: 'assets/models/meadow_2_4k.hdr',
              selectionColor: const [0.0, 0.4, 1.0, 1.0] ,
              defaultZoom: 2,
              onSelectionChanged: (selectedEntities) {
                setState(() {
                  _selectedEntities = selectedEntities;
                });
              },
              selectionSequence: [
                SequenceConfig(
                  group: 'Teeth_Lower',
                  order: List.generate(16, (i) => 'Teeth_Lower_${i + 1}'),
                  bidirectional: true,
                ),
                SequenceConfig(
                  group: 'Teeth_Upper',
                  order: List.generate(16, (i) => 'Teeth_Upper_${i + 1}'),
                  bidirectional: true,
                ),
              ],
              patchColors: [
                PatchColor(name: "Hard_Plate_L", color: [0.41, 0.35, 0.51, 1.0]),
                PatchColor(name: "Hard_Plate_R", color: [0.41, 0.35, 0.51, 1.0]),
                PatchColor(name: "Soft_Plate_R", color: [0.41, 0.35, 0.51, 1.0]),
                PatchColor(name: "Soft_Plate_L", color: [0.41, 0.35, 0.51, 1.0]),
                PatchColor(name: "Neck", color: [0.58, 0.50, 0.43, 1.0]),
              ],
            ),
          ),

          // Selection Info
          Container(
            height: 150,
            color: Colors.grey[100],
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.deepPurple.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected: ${_selectedEntities.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _controller.clearSelections(),
                            child: const Text('Clear'),
                          ),
                          TextButton(
                            onPressed: () => _controller.clearCache(),
                            child: const Text('Clear Cache'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _selectedEntities.isEmpty
                      ? const Center(
                    child: Text(
                      'Tap on model parts to select them',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                      : ListView.builder(
                    itemCount: _selectedEntities.length,
                    itemBuilder: (context, index) {
                      final entity = _selectedEntities[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.deepPurple,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        title: Text(entity.name),
                        subtitle: Text('ID: ${entity.id}'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}