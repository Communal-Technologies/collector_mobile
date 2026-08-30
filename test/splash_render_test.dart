import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:communal_collector/screens/splash_screen.dart';

/// The splash is sized off the screen width, so the sizes it has to survive are
/// the small phone and the tablet, not one design number. A failed layout here
/// throws, which is the whole assertion.
Widget _app({bool blocked = false}) => ScreenUtilInit(
  designSize: const Size(430, 932),
  minTextAdapt: true,
  builder: (context, child) =>
      MaterialApp(home: SplashScreen(blocked: blocked)),
);

void main() {
  group('SplashScreen', () {
    for (final size in const [Size(320, 568), Size(430, 932), Size(800, 1280)]) {
      testWidgets('lays out at ${size.width}x${size.height}', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app());
        await tester.pump(const Duration(milliseconds: 700));

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsOneWidget);
      });
    }

    /// Black, and the same black as `launch_ground` in `res/values/colors.xml`. The two
    /// have to agree: Android paints that window before any Dart runs, so a purple
    /// screen here — which is what this was — flashed on every cold start, and it made
    /// three apps that open identically out of three apps that should not.
    testWidgets('opens on the launch window\'s black', (tester) async {
      tester.view
        ..physicalSize = const Size(430, 932)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF000000));
    });

    testWidgets('the loader segment moves', (tester) async {
      // The default test window is wider than it is tall, which no phone is and
      // the portrait lock forbids; the splash is laid out for a phone.
      tester.view
        ..physicalSize = const Size(430, 932)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump();

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

    /// The mark and the loader sit either side of the middle of the screen, the
    /// way the member app's do — the earlier arrangement pushed the loader to the
    /// bottom edge and read as a screen with a hole in it.
    testWidgets('the mark and the loader are centred', (tester) async {
      tester.view
        ..physicalSize = const Size(430, 932)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 700));

      final mark = tester.getCenter(find.byType(Image));
      final loader = tester.getCenter(find.byType(ClipRRect).last);
      final middle = tester.getCenter(find.byType(Scaffold));

      expect(mark.dx, closeTo(middle.dx, 1));
      expect(loader.dx, closeTo(middle.dx, 1));
      expect(mark.dy, lessThan(middle.dy));
      expect(loader.dy, greaterThan(middle.dy));
      expect(middle.dy - mark.dy, lessThan(300));
      expect(loader.dy - middle.dy, lessThan(300));
    });

    /// Losing the platform covers the splash rather than being stacked beneath it.
    testWidgets('the blocked state is centred over the splash', (tester) async {
      tester.view
        ..physicalSize = const Size(430, 932)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(blocked: true));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Try again'), findsOneWidget);
      final card = tester.getCenter(find.text('Try again'));
      final middle = tester.getCenter(find.byType(Scaffold));
      expect(card.dy, greaterThan(middle.dy * 0.5));
      expect(card.dy, lessThan(middle.dy * 1.5));
    });
  });
}
