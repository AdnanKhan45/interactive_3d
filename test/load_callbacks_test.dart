import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_3d/interactive_3d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plugin = MethodChannel('interactive_3d_plugin');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late Future<Object?> Function() createTexture;
  late Future<Object?> Function() loadModel;
  late Future<Object?> Function() loadEnvironment;

  setUp(() {
    calls = [];
    createTexture = () async => {'textureId': 7};
    loadModel = () async => null;
    loadEnvironment = () async => null;

    messenger.setMockMethodCallHandler(plugin, (call) {
      calls.add(call.method);
      return switch (call.method) {
        'createTexture' => createTexture(),
        'loadModel' => loadModel(),
        'loadEnvironment' => loadEnvironment(),
        _ => Future.value(null),
      };
    });
    messenger.setMockStreamHandler(
      const EventChannel('interactive_3d_events_7'),
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    messenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData(8),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockStreamHandler(
      const EventChannel('interactive_3d_events_7'),
      null,
    );
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  Future<void> pumpViewer(WidgetTester tester, Interactive3d viewer) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: viewer)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('keeps loadingWidget up until the model loads, then calls back',
      (tester) async {
    final load = Completer<Object?>();
    loadModel = () => load.future;
    var loaded = 0;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const Text('loading'),
        onModelLoaded: () => loaded++,
      ),
    );
    expect(find.text('loading'), findsOneWidget);
    expect(loaded, 0);

    load.complete(null);
    await tester.pump();
    await tester.pump();

    expect(find.text('loading'), findsNothing);
    expect(loaded, 1);
  });

  testWidgets('applies defaultZoom before onModelLoaded', (tester) async {
    List<String>? callsAtLoaded;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const SizedBox(),
        defaultZoom: 2,
        onModelLoaded: () => callsAtLoaded = List.of(calls),
      ),
    );

    expect(callsAtLoaded, isNotNull);
    expect(callsAtLoaded!.indexOf('setZoomLevel'),
        greaterThan(callsAtLoaded!.indexOf('loadModel')));
  });

  testWidgets('reports a native load failure to the callback and builder',
      (tester) async {
    loadModel = () async => throw PlatformException(code: 'MODEL_LOAD_FAILED');
    Object? reported;
    var loaded = 0;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const Text('loading'),
        errorBuilder: (_, error) => Text('failed: ${error.runtimeType}'),
        onModelLoaded: () => loaded++,
        onModelLoadError: (error, _) => reported = error,
      ),
    );

    expect(reported, isA<PlatformException>());
    expect((reported! as PlatformException).code, 'MODEL_LOAD_FAILED');
    expect(find.text('failed: PlatformException'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
    expect(loaded, 0);
  });

  testWidgets('reports a texture creation failure', (tester) async {
    createTexture = () async => throw PlatformException(code: 'NO_TEXTURE');
    Object? reported;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const SizedBox(),
        onModelLoadError: (error, _) => reported = error,
      ),
    );

    expect((reported! as PlatformException).code, 'NO_TEXTURE');
    expect(calls, isNot(contains('loadModel')));
  });

  testWidgets('does not retry createTexture after a failure', (tester) async {
    createTexture = () async => throw PlatformException(code: 'NO_TEXTURE');

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const SizedBox(),
        errorBuilder: (_, __) => const Text('failed'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(calls.where((c) => c == 'createTexture'), hasLength(1));
    expect(find.text('failed'), findsOneWidget);
  });

  testWidgets('disposes a texture created after the widget is removed',
      (tester) async {
    final created = Completer<Object?>();
    createTexture = () => created.future;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    created.complete({'textureId': 7});
    await tester.pump();

    expect(calls, contains('disposeTexture'));
    expect(calls, isNot(contains('loadModel')));
  });

  testWidgets('reports a missing model source', (tester) async {
    Object? reported;

    await pumpViewer(
      tester,
      Interactive3d(
        loadingWidget: const SizedBox(),
        onModelLoadError: (error, _) => reported = error,
      ),
    );

    expect(reported, isA<ArgumentError>());
  });

  testWidgets('still loads when only the environment fails', (tester) async {
    loadEnvironment = () async => throw PlatformException(code: 'ENV');
    var loaded = 0;
    Object? reported;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        iblPath: 'assets/ibl.ktx',
        skyboxPath: 'assets/skybox.ktx',
        loadingWidget: const SizedBox(),
        onModelLoaded: () => loaded++,
        onModelLoadError: (error, _) => reported = error,
      ),
    );

    expect(calls, contains('loadEnvironment'));
    expect(loaded, 1);
    expect(reported, isNull);
  });

  testWidgets('does not call back after the widget is removed', (tester) async {
    final load = Completer<Object?>();
    loadModel = () => load.future;
    var callbacks = 0;

    await pumpViewer(
      tester,
      Interactive3d(
        modelPath: 'assets/model.glb',
        loadingWidget: const SizedBox(),
        defaultZoom: 2,
        onModelLoaded: () => callbacks++,
        onModelLoadError: (_, __) => callbacks++,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    load.complete(null);
    await tester.pump();

    expect(callbacks, 0);
    expect(calls, contains('disposeTexture'));
    expect(calls, isNot(contains('setZoomLevel')));
  });
}
