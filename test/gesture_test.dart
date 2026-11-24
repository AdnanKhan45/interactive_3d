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
    messenger.setMockMessageHandler('flutter/assets', (_) async => ByteData(8));
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockStreamHandler(events, null);
    messenger.setMockMessageHandler('flutter/assets', null);
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    // Render ratio 1.0, so deltas sent to the platform equal logical pixels.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
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
    calls.clear();
  }

  List<Map<Object?, Object?>> touches(String action) => calls
      .where((c) => c.method == 'onTouchEvent')
      .map((c) => c.arguments as Map<Object?, Object?>)
      .where((a) => a['action'] == action)
      .toList();

  Offset sumDeltas(String action) => touches(action).fold(
        Offset.zero,
        (sum, a) => sum + Offset(a['deltaX'] as double, a['deltaY'] as double),
      );

  double productOfScales() => touches('scale')
      .fold(1.0, (product, a) => product * (a['scale'] as double));

  Set<Object?> actions() => calls
      .where((c) => c.method == 'onTouchEvent')
      .map((c) => (c.arguments as Map)['action'])
      .toSet();

  // Moves are sent once per frame, so every step below is followed by a pump.

  testWidgets('one finger sends only pan', (tester) async {
    await pumpViewer(tester);
    final finger = await tester.startGesture(const Offset(300, 300));
    for (var i = 0; i < 10; i++) {
      await finger.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    await finger.up();

    expect(actions(), {'pan'});
    expect(touches('pan'), isNotEmpty);
  });

  testWidgets('two-finger spread zooms by the spread without moving',
      (tester) async {
    await pumpViewer(tester);
    final a = await tester.startGesture(const Offset(250, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(350, 300), pointer: 2);
    // The first step passes the gesture slop; the scale is measured from there.
    await a.moveBy(const Offset(-20, 0));
    await b.moveBy(const Offset(20, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-5, 0));
      await b.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();

    expect(actions(), {'scale'});
    // Span grows from 140 to 240 after the slop step.
    expect(productOfScales(), closeTo(240 / 140, 1e-9));
  });

  testWidgets(
      'two-finger drag sends only translate, even with fingers reported one at a time',
      (tester) async {
    await pumpViewer(tester);
    final a = await tester.startGesture(const Offset(250, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(350, 300), pointer: 2);
    for (var i = 0; i < 20; i++) {
      await a.moveBy(const Offset(3, 2));
      await b.moveBy(const Offset(3, 2));
      await tester.pump();
    }
    await a.up();
    await b.up();

    expect(actions(), {'translate'});
    // The first steps are spent passing the gesture slop.
    final total = sumDeltas('translate');
    expect(total.dx, inInclusiveRange(45, 60));
    expect(total.dy / total.dx, closeTo(2 / 3, 1e-9));
  });

  testWidgets('slow two-finger drags add up instead of being dropped',
      (tester) async {
    await pumpViewer(tester);
    final a = await tester.startGesture(const Offset(250, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(350, 300), pointer: 2);
    // Pass the slop first, then move in steps under the 0.5 px dispatch limit.
    await a.moveBy(const Offset(20, 0));
    await b.moveBy(const Offset(20, 0));
    await tester.pump();
    final before = sumDeltas('translate');
    for (var i = 0; i < 40; i++) {
      await a.moveBy(const Offset(0, 0.3));
      await b.moveBy(const Offset(0, 0.3));
      await tester.pump();
    }
    await a.up();
    await b.up();

    // 40 steps of 0.3 px: at most one sub-threshold remainder is left unsent.
    expect((sumDeltas('translate') - before).dy, closeTo(12, 0.5));
  });

  testWidgets('a finger landing or lifting causes no jump', (tester) async {
    await pumpViewer(tester);
    final a = await tester.startGesture(const Offset(200, 300), pointer: 1);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    // The second finger lands 200 px away: the focal point jumps by 100 px.
    final b = await tester.startGesture(const Offset(450, 300), pointer: 2);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(0, 4));
      await b.moveBy(const Offset(0, 4));
      await tester.pump();
    }
    await b.up();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    await a.up();

    final all = [...touches('pan'), ...touches('translate')];
    expect(all, isNotEmpty);
    for (final t in all) {
      final step = Offset(t['deltaX'] as double, t['deltaY'] as double);
      expect(step.distance, lessThanOrEqualTo(20), reason: '$t');
    }
    for (final t in touches('scale')) {
      expect(t['scale'] as double, closeTo(1.0, 0.01), reason: '$t');
    }
  });

  testWidgets('motion in the frame a finger lands in is still sent',
      (tester) async {
    await pumpViewer(tester);
    final a = await tester.startGesture(const Offset(200, 300), pointer: 1);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    final before = sumDeltas('pan');
    // No frame between this move, the second finger landing and its first
    // move, which is when Flutter restarts the gesture with onStart.
    await a.moveBy(const Offset(30, 0));
    final b = await tester.startGesture(const Offset(450, 300), pointer: 2);
    await b.moveBy(const Offset(0, 1));
    await tester.pump();
    await a.up();
    await b.up();

    expect((sumDeltas('pan') - before).dx, closeTo(30, 1e-9));
  });
}
