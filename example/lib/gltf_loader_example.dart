
import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';
import 'package:interactive_3d/interactive_3d_platform_interface.dart';
import 'result_page.dart';

class GltfLoaderExample extends StatefulWidget {
  @override
  _GltfLoaderExampleState createState() =>
      _GltfLoaderExampleState();
}

class _GltfLoaderExampleState
    extends State<GltfLoaderExample> {
  List<EntityData> _selectedEntities = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interactive 3D Viewer Example')),
      body: Column(
        children: [
          Expanded(
              child: Interactive3d(
                modelPath: 'assets/models/Tooth-2.gltf',
                iblPath: 'assets/models/venetian_crossroads_2k_ibl.ktx',
                skyboxPath: 'assets/models/venetian_crossroads_2k_skybox.ktx',
                resources: [
                  'scene.bin',
                  'textures/mouth_baseColor.png',
                  'textures/mouth_metallicRoughness.png',
                  'textures/mouth_normal.png',
                  'textures/teeth_baseColor.png',
                  'textures/teeth_metallicRoughness.png',
                  'textures/teeth_normal.png',
                ],
                onSelectionChanged: (selectedEntities) {
                  setState(() {
                    _selectedEntities = selectedEntities;
                  });
                },
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
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => ResultPage(data: _selectedEntities)));
                  },
                  title: Text('Entity ID: ${entity.id}'),
                  subtitle: Text('Name: ${entity.name}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
