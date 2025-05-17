import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';
import 'package:interactive_3d/interactive_3d_controller.dart';
import 'result_page.dart';

class GlbLoaderExample extends StatefulWidget {
  const GlbLoaderExample({super.key});

  @override
  GlbLoaderExampleState createState() => GlbLoaderExampleState();
}

class GlbLoaderExampleState extends State<GlbLoaderExample> {
  List<EntityData> _selectedEntities = [];

  bool _toothVisibiliy = true;

  final Interactive3dController _controller = Interactive3dController();

  List<String> toothGroup = [
    "Teeth_Lower_1",
    "Teeth_Lower_2",
    "Teeth_Lower_3",
    "Teeth_Lower_4",
    "Teeth_Lower_5",
    "Teeth_Lower_6",
    "Teeth_Lower_7",
    "Teeth_Lower_8",
    "Teeth_Lower_9",
    "Teeth_Lower_10",
    "Teeth_Lower_11",
    "Teeth_Lower_12",
    "Teeth_Lower_13",
    "Teeth_Lower_14",
    "Teeth_Lower_15",
    "Teeth_Lower_16",
    "Teeth_Upper_1",
    "Teeth_Upper_2",
    "Teeth_Upper_3",
    "Teeth_Upper_4",
    "Teeth_Upper_5",
    "Teeth_Upper_6",
    "Teeth_Upper_7",
    "Teeth_Upper_8",
    "Teeth_Upper_9",
    "Teeth_Upper_10",
    "Teeth_Upper_11",
    "Teeth_Upper_12",
    "Teeth_Upper_13",
    "Teeth_Upper_14",
    "Teeth_Upper_15",
    "Teeth_Upper_16",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interactive 3D Viewer Example')),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                  child: Interactive3d(
                controller: _controller,
                modelPath: 'assets/models/Tooth-3.glb',
                iblPath: 'assets/models/giuseppe_bridge_4k_ibl.ktx',
                skyboxPath: 'assets/models/giuseppe_bridge_4k_skybox.ktx',
                iOSBackgroundEnvPath:
                    'assets/models/san_giuseppe_bridge_4k.hdr',
                preselectedEntities: [
                  "Teeth_Lower_1",
                  "Teeth_Lower_2",
                  "Teeth_Lower_3",
                  "Neck"
                ],
                selectionColor: [0.32, 0.49, 0.55, 1.0], // Light Blue Color
                defaultZoom: 2,
                onSelectionChanged: (selectedEntities) {
                  setState(() {
                    _selectedEntities = selectedEntities;
                  });
                },
                patchColors: [
                  PatchColor(
                    name: "Hard_Plate_L",
                    color: [0.41, 0.35, 0.51, 1.0],
                  ),
                  PatchColor(
                    name: "Hard_Plate_R",
                    color: [0.41, 0.35, 0.51, 1.0],
                  ),
                  PatchColor(
                    name: "Soft_Plate_R",
                    color: [0.41, 0.35, 0.51, 1.0],
                  ),
                  PatchColor(
                    name: "Soft_Plate_L",
                    color: [0.41, 0.35, 0.51, 1.0],
                  ),
                  PatchColor(
                    name: "Lower_Jaw_L",
                    color: [0.60, 0.43, 0.28, 1.0],
                  ),
                  PatchColor(
                    name: "Lower_Jaw_R",
                    color: [0.60, 0.43, 0.28, 1.0],
                  ),
                  PatchColor(
                    name: "Upper_Jaw_L",
                    color: [0.60, 0.43, 0.28, 1.0],
                  ),
                  PatchColor(
                    name: "Upper_Jaw_R",
                    color: [0.60, 0.43, 0.28, 1.0],
                  ),
                  PatchColor(
                    name: "Tounge_Lower_L",
                    color: [0.58, 0.50, 0.43, 1.0],
                  ),
                  PatchColor(
                    name: "Tounge_Lower_R",
                    color: [0.58, 0.50, 0.43, 1.0],
                  ),
                  PatchColor(
                    name: "Tounge_Upper_L",
                    color: [0.58, 0.50, 0.43, 1.0],
                  ),
                  PatchColor(
                    name: "Tounge_Upper_R",
                    color: [0.58, 0.50, 0.43, 1.0],
                  ),
                  PatchColor(
                    name: "Neck",
                    color: [0.58, 0.50, 0.43, 1.0],
                  ),
                ],
              )),
              Container(
                height: 150,
                color: Colors.grey[200],
                child: ListView.builder(
                  itemCount: _selectedEntities.length,
                  itemBuilder: (context, index) {
                    final entity = _selectedEntities[index];
                    return ListTile(
                      onTap: () {
                        // Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => ResultPage(data: _selectedEntities)), (route) => false);
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) =>
                                ResultPage(data: _selectedEntities)));
                      },
                      title: Text('Entity ID: ${entity.id}'),
                      subtitle: Text('Name: ${entity.name}'),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_selectedEntities.isNotEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20),
                child: ElevatedButton(
                  onPressed: _clearSelections,
                  child: Text("Clear"),
                ),
              ),
            ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20),
              child: Switch(
                value: _toothVisibiliy,
                onChanged: (visibility) {
                  setState(
                    () {

                      _toothVisibiliy = visibility;

                      _controller.updatePartGroupConfig(
                          isVisible: _toothVisibiliy,
                          group: ModelPartGroup(
                              title: "Teeth", names: toothGroup));
                    },
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }

  void _clearSelections() async {
    try {
      await _controller.clearSelections();
      setState(() {
        _selectedEntities.clear();
      });
    } catch (e) {
      print('Error clearing selections: $e');
    }
  }

  // TO REMOVE SPECIFIC ENTITY SELECTION
  void _removeEntity(int entityId) async {
    try {
      await _controller.unselectEntities(entityIds: [entityId]);
      setState(() {
        _selectedEntities.removeWhere((entity) => entity.id == entityId);
      });
    } catch (e) {
      print('Error unselecting entity: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
