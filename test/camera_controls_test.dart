import 'dart:async';

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
    messenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData(8),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockStreamHandler(events, null);
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  Future<Interactive3dController> pumpViewer(
    WidgetTester tester, {
    double? defaultZoom,
  }) async {
    final controller = Interactive3dController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Interactive3d(
          controller: controller,
          modelPath: 'assets/model.glb',
          defaultZoom: defaultZoom,
          loadingWidget: const SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    calls.clear();
    return controller;
  }

  MethodCall single(String method) =>
      calls.singleWhere((call) => call.method == method);

  testWidgets('resetCamera returns to defaultZoom', (tester) async {
    final controller = await pumpViewer(tester, defaultZoom: 2);

    await controller.resetCamera();

    expect(single('resetCamera').arguments, {'textureId': 7, 'zoom': 2.0});
  });

  testWidgets('resetCamera falls back to zoom 1.0 without defaultZoom',
      (tester) async {
    final controller = await pumpViewer(tester);

    await controller.resetCamera();

    expect(single('resetCamera').arguments, {'textureId': 7, 'zoom': 1.0});
  });

  testWidgets('resetCamera treats an invalid defaultZoom as unset',
      (tester) async {
    final controller = await pumpViewer(tester, defaultZoom: 0);

    await controller.resetCamera();

    expect(single('resetCamera').arguments, {'textureId': 7, 'zoom': 1.0});
  });

  testWidgets('ignores camera calls until the model has loaded',
      (tester) async {
    final controller = Interactive3dController();
    messenger.setMockMethodCallHandler(plugin, (call) async {
      calls.add(call);
      if (call.method == 'createTexture') return {'textureId': 7};
      if (call.method == 'loadModel') return Completer<Object?>().future;
      return null;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Interactive3d(
          controller: controller,
          modelPath: 'assets/model.glb',
          loadingWidget: const SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await controller.zoomBy(0.25);
    await controller.resetCamera();

    expect(calls.map((c) => c.method), isNot(contains('zoomBy')));
    expect(calls.map((c) => c.method), isNot(contains('resetCamera')));
  });

  testWidgets('zoomBy sends the delta to the platform', (tester) async {
    final controller = await pumpViewer(tester);

    await controller.zoomBy(-0.25);

    expect(single('zoomBy').arguments, {'textureId': 7, 'delta': -0.25});
  });

  testWidgets('ignores non-finite zoom values', (tester) async {
    final controller = await pumpViewer(tester);

    await controller.zoomBy(double.nan);
    await controller.zoomBy(double.infinity);
    await controller.setCameraZoomLevel(double.infinity);
    await controller.setCameraZoomLevel(0);

    expect(calls, isEmpty);
  });

  test('throws when used before it is attached', () {
    final controller = Interactive3dController();

    expect(controller.resetCamera, throwsStateError);
    expect(() => controller.zoomBy(0.25), throwsStateError);
  });
}
