
import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

class ResultPage extends StatefulWidget {
  final List<EntityData> data;
  const ResultPage({super.key, required this.data});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Result page')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.data.length,
              itemBuilder: (context, index) {
                final entity = widget.data[index];
                return ListTile(
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
