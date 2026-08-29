import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:communal_collector/screens/splash_screen.dart';

/// The splash is sized off the screen width, so the sizes it has to survive are
/// the small phone and the tablet, not one design number. A failed layout here
/// throws, which is the whole assertion.
void main() {
  group('SplashScreen', () {
    for (final size in const [Size(320, 568), Size(430, 932), Size(800, 1280)]) {
      testWidgets('lays out at ${size.width}x${size.height}', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
        await tester.pump(const Duration(milliseconds: 700));

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsOneWidget);
      });
    }

    testWidgets('the loader segment moves', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

      Alignment alignmentNow() => tester
          .widgetList<Align>(find.byType(Align))
          .map((a) => a.alignment)
          .whereType<Alignment>()
          .last;

      final start = alignmentNow();
      await tester.pump(const Duration(milliseconds: 350));
      final later = alignmentNow();

      expect(later.x, isNot(equals(start.x)));
    });
  });
}
