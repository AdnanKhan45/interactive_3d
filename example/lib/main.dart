// main.dart
import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';
import 'package:interactive_3d/interactive_3d_platform_interface.dart';

import 'result_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Interactive3DExample());
  }
}

class Interactive3DExample extends StatefulWidget {
  @override
  _Interactive3DExampleState createState() =>
      _Interactive3DExampleState();
}

class _Interactive3DExampleState
    extends State<Interactive3DExample> {
  List<EntityData> _selectedEntities = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interactive 3D Viewer Example')),
      body: Column(
        children: [
          Expanded(
              child: Interactive3d(
                modelPath: 'assets/models/Tooth-3.glb',
                iblPath: 'assets/models/venetian_crossroads_2k_ibl.ktx',
                skyboxPath: 'assets/models/venetian_crossroads_2k_skybox.ktx',
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
