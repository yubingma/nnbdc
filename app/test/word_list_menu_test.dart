import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/word_list/word_list.dart';

void main() {
  testWidgets('GestureDetector inside PopupMenuItem pops menu exactly once', (WidgetTester tester) async {
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
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  selectedValue = await showMenu<String>(
                    context: context,
                    useRootNavigator: true,
                    position: const RelativeRect.fromLTRB(800, 50, 0, 600),
                    items: [
                      PopupMenuItem<String>(
                        value: menuWordList,
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.of(context, rootNavigator: true).pop(menuWordList);
                          },
                          child: Container(
                            width: double.infinity,
                            child: const Text(menuWordList),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text(menuWordList), findsOneWidget);

    // Click on menuWordList with mouse
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text(menuWordList)));
    await tester.pump();
    await gesture.down(tester.getCenter(find.text(menuWordList)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectedValue, equals(menuWordList));
    expect(find.text(menuWordList), findsNothing); // Menu closed!

    debugDefaultTargetPlatformOverride = null;
  });
}
