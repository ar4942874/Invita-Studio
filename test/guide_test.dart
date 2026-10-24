import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/services/guide_prefs.dart';
import 'package:invitation_studio/ui/guide/guide_controller.dart';
import 'package:invitation_studio/ui/guide/guide_scope.dart';
import 'package:invitation_studio/ui/guide/guide_spotlight.dart';
import 'package:invitation_studio/ui/guide/guide_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GuideController> _controller() async {
  final controller = GuideController();
  await controller.restore();
  return controller;
}

/// A tiny tour: two steps, so advancing is easy to reason about.
const _twoStopTour = [
  GuideStop(
    anchor: 'a',
    title: 'First step',
    body: 'Point at the first control.',
    why: 'Because the first control exists.',
  ),
  GuideStop(
    anchor: 'b',
    title: 'Second step',
    body: 'Point at the second control.',
    why: 'Because the second control exists.',
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the tour knows what it has shown', () {
    test('nine steps, each pointing at a distinct anchor', () {
      expect(guideStops, hasLength(9));
      expect(
        guideStops.map((stop) => stop.anchor).toSet(),
        hasLength(guideStops.length),
      );
      for (final stop in guideStops) {
        expect(stop.title, isNotEmpty);
        expect(stop.body, isNotEmpty);
        expect(stop.why, isNotEmpty);
      }
    });

    test('an untouched install opens on the first step', () async {
      final controller = await _controller();
      expect(controller.isVisible, isFalse);
      controller.startIfNew();
      expect(controller.isVisible, isTrue);
      expect(controller.current?.title, 'Start with the details');
      expect(controller.position, 1);
      expect(controller.total, 9);
    });

    test('finishing a step hides it for good', () async {
      final controller = await _controller();
      controller.start();
      controller.finishStep();
      expect(controller.position, 2);
      expect(
        controller.finishedAnchors,
        contains(GuideAnchors.details),
      );

      final reopened = await _controller();
      reopened.startIfNew();
      expect(reopened.position, 2, reason: 'a finished step must not return');
    });

    test('skipping does not pretend the step is done', () async {
      final controller = await _controller();
      controller.start();
      final anchor = controller.current!.anchor;
      controller.skip();
      expect(controller.position, 2);
      expect(controller.finishedAnchors, isNot(contains(anchor)));

      // ...so it is still open: the next launch resumes where the tour got to
      // and the skipped step is not in the finished list.
      final reopened = await _controller();
      reopened.startIfNew();
      expect(reopened.finishedAnchors, isNot(contains(anchor)));
      expect(reopened.hasRemaining, isTrue);
    });

    test('dismissing resumes at the same step next launch', () async {
      final controller = await _controller();
      controller.start();
      controller.finishStep();
      final resume = controller.current!.anchor;
      controller.dismiss();
      expect(controller.isVisible, isFalse);

      final reopened = await _controller();
      reopened.startIfNew();
      expect(reopened.current?.anchor, resume);
    });

    test('switching the tour off is remembered until it is switched on', () async {
      final controller = await _controller();
      controller.start();
      controller.turnOff();
      expect(controller.isVisible, isFalse);
      expect(controller.isOff, isTrue);

      final reopened = await _controller();
      reopened.startIfNew();
      expect(reopened.isVisible, isFalse, reason: 'off means off');
      reopened.turnOn();
      expect(reopened.isVisible, isTrue);
      expect(reopened.isOff, isFalse);
    });

    test('a step whose control does not exist is stepped over', () async {
      final controller = GuideController(stops: _twoStopTour);
      await controller.restore();
      // Both controls mount, but the second one is hidden on this screen: it
      // registers once, then never reports a rectangle again.
      controller.registerAnchor('a');
      controller.registerAnchor('b');
      controller.reportAnchor('a', const Rect.fromLTWH(0, 0, 40, 40));
      controller.start();
      expect(controller.position, 1);
      controller.finishStep();
      expect(controller.isVisible, isFalse);
      expect(controller.isComplete, isTrue);
    });

    test('the last step finishes the tour', () async {
      final controller = GuideController(stops: _twoStopTour);
      await controller.restore();
      controller.start();
      controller.finishStep();
      expect(controller.position, 2);
      controller.finishStep();
      expect(controller.isVisible, isFalse);
      expect(controller.isComplete, isTrue);
      expect(controller.hasRemaining, isFalse);
    });
  });

  group('the tour stays quiet when there is nothing to say', () {
    test('a controller with every step done does not start', () async {
      SharedPreferences.setMockInitialValues({
        GuidePrefs.doneKey: guideStops.map((stop) => stop.anchor).toList(),
      });
      final controller = await _controller();
      expect(controller.isComplete, isTrue);
      controller.startIfNew();
      expect(controller.isVisible, isFalse);
    });
  });

  group('the spotlight points at one control at a time', () {
    Future<void> pumpTour(
      WidgetTester tester,
      GuideController controller,
    ) async {
      await tester.pumpWidget(
        GuideScope(
          notifier: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GuideTarget(
                          anchor: 'a',
                          child: SizedBox(
                            width: 120,
                            height: 40,
                            child: TextButton(
                              onPressed: () {},
                              child: const Text('Alpha control'),
                            ),
                          ),
                        ),
                        GuideTarget(
                          anchor: 'b',
                          child: SizedBox(
                            width: 120,
                            height: 40,
                            child: TextButton(
                              onPressed: () {},
                              child: const Text('Beta control'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: GuideSpotlight(controller: controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<BoxShadow> glowFor(WidgetTester tester, String anchor) {
      final widget = tester.widget<AnimatedContainer>(
        find.byKey(ValueKey('guide.target.$anchor')),
      );
      final decoration = widget.decoration! as BoxDecoration;
      return decoration.boxShadow ?? const [];
    }

    testWidgets('only the current control glows, and the card explains it', (
      tester,
    ) async {
      final controller = GuideController(stops: _twoStopTour);
      await controller.restore();
      controller.start();
      await pumpTour(tester, controller);

      expect(glowFor(tester, 'a'), isNotEmpty);
      expect(glowFor(tester, 'b'), isEmpty);
      expect(find.text('First step'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);

      final glow = glowFor(tester, 'a').single;
      expect(glow.blurRadius, greaterThan(0));
      expect(glow.color, isNot(Colors.transparent));
    });

    testWidgets('Next moves the glow to the following control', (tester) async {
      final controller = GuideController(stops: _twoStopTour);
      await controller.restore();
      controller.start();
      await pumpTour(tester, controller);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Second step'), findsOneWidget);
      expect(glowFor(tester, 'a'), isEmpty);
      expect(glowFor(tester, 'b'), isNotEmpty);
      expect(controller.finishedAnchors, contains('a'));
    });

    testWidgets('tapping the dim area closes the tour', (tester) async {
      final controller = GuideController(stops: _twoStopTour);
      await controller.restore();
      controller.start();
      await pumpTour(tester, controller);

      // The highlighted control sits top-left, so the card is pinned to the
      // bottom; a tap in the top-right corner lands on a dim panel.
      await tester.tapAt(const Offset(760, 20));
      await tester.pumpAndSettle();

      expect(controller.isVisible, isFalse);
      expect(find.text('First step'), findsNothing);
    });

    testWidgets('a control stays usable while it is being explained', (
      tester,
    ) async {
      final controller = GuideController(stops: _twoStopTour);
      await controller.restore();
      controller.start();
      var tapped = false;
      await tester.pumpWidget(
        GuideScope(
          notifier: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: GuideTarget(
                      anchor: 'a',
                      child: SizedBox(
                        width: 200,
                        height: 48,
                        child: TextButton(
                          onPressed: () => tapped = true,
                          child: const Text('Alpha control'),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GuideSpotlight(controller: controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha control'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue, reason: 'the spotlight must not swallow the tap');
    });
  });
}
