import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_3d/interactive_3d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plugin = MethodChannel('interactive_3d_plugin');
  const events = EventChannel('interactive_3d_events_7');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      return call.method == 'createTexture' ? {'textureId': 7} : null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      return key.contains('missing') ? null : ByteData(8);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockStreamHandler(events, null);
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  Future<void> pumpViewer(
    WidgetTester tester, {
    String? iblPath,
    String? skyboxPath,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Interactive3d(
          modelPath: 'assets/model.glb',
          iblPath: iblPath,
          skyboxPath: skyboxPath,
          loadingWidget: const SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Map<dynamic, dynamic>? environmentArgs() => calls
      .where((call) => call.method == 'loadEnvironment')
      .singleOrNull
      ?.arguments as Map<dynamic, dynamic>?;

  testWidgets('loads the IBL without a skybox', (tester) async {
    await pumpViewer(tester, iblPath: 'assets/ibl.ktx');

    final args = environmentArgs()!;
    expect(args['iblBytes'], isNotNull);
    expect(args['skyboxBytes'], isNull);
  });

  testWidgets('loads the skybox without an IBL', (tester) async {
    await pumpViewer(tester, skyboxPath: 'assets/skybox.ktx');

    final args = environmentArgs()!;
    expect(args['iblBytes'], isNull);
    expect(args['skyboxBytes'], isNotNull);
  });

  testWidgets('still sends the IBL when the skybox file is missing',
      (tester) async {
    await pumpViewer(
      tester,
      iblPath: 'assets/ibl.ktx',
      skyboxPath: 'assets/missing.ktx',
    );

    final args = environmentArgs()!;
    expect(args['iblBytes'], isNotNull);
    expect(args['skyboxBytes'], isNull);
  });

  testWidgets('skips the environment when no file is given', (tester) async {
    await pumpViewer(tester);

    expect(environmentArgs(), isNull);
  });
}
