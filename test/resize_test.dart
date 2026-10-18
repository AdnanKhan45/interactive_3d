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

  Widget viewer(Size size) => MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: const Interactive3d(
              modelPath: 'assets/model.glb',
              loadingWidget: SizedBox(),
            ),
          ),
        ),
      );

  Iterable<MethodCall> callsTo(String method) =>
      calls.where((call) => call.method == method);

  testWidgets('does not resize on first layout', (tester) async {
    await tester.pumpWidget(viewer(const Size(400, 300)));
    await tester.pump();
    await tester.pump();

    expect(callsTo('updateSize'), isEmpty);
  });

  testWidgets('resizes the render surface with the createTexture scaling',
      (tester) async {
    await tester.pumpWidget(viewer(const Size(400, 300)));
    await tester.pump();
    await tester.pump();
    final created = callsTo('createTexture').single.arguments as Map;
    final ratio = (created['width'] as int) / 400;

    await tester.pumpWidget(viewer(const Size(300, 400)));

    expect(callsTo('updateSize').single.arguments, {
      'textureId': 7,
      'width': (300 * ratio).toInt(),
      'height': (400 * ratio).toInt(),
    });
  });

  testWidgets('does not resize again for the same size', (tester) async {
    await tester.pumpWidget(viewer(const Size(400, 300)));
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(viewer(const Size(300, 400)));
    await tester.pumpWidget(viewer(const Size(300, 400)));

    expect(callsTo('updateSize'), hasLength(1));
  });
}
