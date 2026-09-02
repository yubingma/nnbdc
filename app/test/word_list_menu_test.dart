import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/word_list/word_list.dart';

void main() {
  testWidgets('PopupMenuButton on macOS opens and selects item cleanly with mouse', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? selectedValue;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                position: PopupMenuPosition.under,
                onSelected: (val) {
                  selectedValue = val;
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: menuWordList,
                    height: 40,
                    child: Text(menuWordList),
                  ),
                ],
              ),
            ],
          ),
          body: const Center(child: Text('Body')),
        ),
      ),
    );

    // Open menu
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text(menuWordList), findsOneWidget);

    // Click on menuWordList with mouse at top center, center, anywhere
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text(menuWordList)));
    await tester.pump();
    await gesture.down(tester.getCenter(find.text(menuWordList)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedValue, equals(menuWordList));
    expect(find.text(menuWordList), findsNothing); // Menu closed cleanly!

    debugDefaultTargetPlatformOverride = null;
  });
}
