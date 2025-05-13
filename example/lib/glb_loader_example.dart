import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';
import 'package:interactive_3d/interactive_3d_controller.dart';
import 'result_page.dart';

class GlbLoaderExample extends StatefulWidget {
  const GlbLoaderExample({super.key});

  @override
  GlbLoaderExampleState createState() => GlbLoaderExampleState();
}

// Updated camera zoomLevel: 2.5, position: SCNVector3(x: 0.0, y: 0.0, z: 0.64142126)
// Updated camera zoomLevel: 2.5, position: SCNVector3(x: 0.0, y: 0.0, z: 0.5)

class GlbLoaderExampleState extends State<GlbLoaderExample> {
  List<EntityData> _selectedEntities = [];

  final Interactive3dController _controller = Interactive3dController();

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
                  ), PatchColor(
                    name: "Upper_Jaw_L",
                    color: [0.60, 0.43, 0.28, 1.0],
                  ), PatchColor(
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
                child: ElevatedButton(onPressed: _clearSelections, child: Text("Clear"),),
              ),
            ),
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
