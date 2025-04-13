
import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';
import 'result_page.dart';

class GlbLoaderExample extends StatefulWidget {
  const GlbLoaderExample({super.key});

  @override
  GlbLoaderExampleState createState() =>
      GlbLoaderExampleState();
}

class GlbLoaderExampleState
    extends State<GlbLoaderExample> {
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
                iblPath: 'assets/models/giuseppe_bridge_4k_ibl.ktx',
                skyboxPath: 'assets/models/giuseppe_bridge_4k_skybox.ktx',
                preselectedEntities: ["Teeth_Lower_1", "Teeth_Lower_2", "Teeth_Lower_3", "Neck"],
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
                    // Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => ResultPage(data: _selectedEntities)), (route) => false);
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
