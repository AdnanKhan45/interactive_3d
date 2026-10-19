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

  late MockStreamHandlerEventSink? sink;

  setUp(() {
    sink = null;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      return call.method == 'createTexture' ? {'textureId': 7} : null;
    });
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

  // Registered inside the test body so events are delivered in the fake-async zone.
  void mockEvents() => messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, events) {
          sink = events;
        }),
      );

  testWidgets('reports a rejected tap without changing the selection',
      (tester) async {
    mockEvents();
    final rejected = <String>[];
    var selectionChanges = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Interactive3d(
          modelPath: 'assets/model.glb',
          loadingWidget: const SizedBox(),
          onSelectionRejected: rejected.add,
          onSelectionChanged: (_) => selectionChanges++,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    sink!.success({'event': 'selectionRejected', 'name': 'Teeth_Lower_9'});
    await tester.pump();

    expect(rejected, ['Teeth_Lower_9']);
    expect(selectionChanges, 0);
  });

  testWidgets('ignores a rejected tap without a callback', (tester) async {
    mockEvents();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Interactive3d(
          modelPath: 'assets/model.glb',
          loadingWidget: SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    sink!.success({'event': 'selectionRejected', 'name': 'Teeth_Lower_9'});
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
