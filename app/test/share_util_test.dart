import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/share_util.dart';

void main() {
  testWidgets('ShareUtil.resolvePositionOrigin returns non-zero origin for widget context', (tester) async {
    late BuildContext targetContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                targetContext = context;
                return const SizedBox(
                  width: 200,
                  height: 100,
                  child: Text('Share target'),
                );
              },
            ),
          ),
        ),
      ),
    );

    final origin = ShareUtil.resolvePositionOrigin(targetContext);
    expect(origin.width, greaterThan(0));
    expect(origin.height, greaterThan(0));
    expect(origin.isEmpty, isFalse);
  });

  test('ShareUtil.resolvePositionOrigin returns non-zero fallback when context is null', () {
    final origin = ShareUtil.resolvePositionOrigin(null);
    expect(origin.width, greaterThan(0));
    expect(origin.height, greaterThan(0));
    expect(origin.isEmpty, isFalse);
  });
}
