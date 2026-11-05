import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openui_lang/openui_lang.dart';

/// Pumps [response] through the renderer in a 400x300 box, the
/// golden-test convention from conformance_test.dart.
Future<void> pumpGolden(WidgetTester tester, String response) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: OpenUIRenderer(
            library: openUIStandardLibrary(),
            response: response,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // M1: tooltip text stays readable under a dark host theme.
  testWidgets('tooltip text is explicitly dark under a dark host theme',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: OpenUIRenderer(
            library: openUIStandardLibrary(),
            response: 'root = BarChart(["A", "B"], [Series("S", [10, 20])])',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final topLeft = tester.getTopLeft(find.byKey(const Key('chart-plot')));
    final size = tester.getSize(find.byKey(const Key('chart-plot')));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(
        topLeft + Offset(size.width * 0.75, size.height * 0.5));
    await tester.pump();
    expect(find.byKey(const Key('chart-tip-title')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('chart-tip-title')))
            .style
            ?.color,
        Colors.black87);
    final rowTexts = find.descendant(
        of: find.byKey(const Key('chart-tip-row-0')),
        matching: find.byType(Text));
    expect(rowTexts, findsNWidgets(2));
    expect(tester.widget<Text>(rowTexts.at(0)).style?.color, Colors.black87);
    expect(tester.widget<Text>(rowTexts.at(1)).style?.color, Colors.black87);
    await gesture.removePointer();
  });

  // m1: a donut's hole is empty for hover and tap alike.
  testWidgets('donut hole shows no tooltip and fires no tap',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PieChartWidget(
            labels: const ['A', 'B'],
            values: const [1, 1],
            variant: 'donut',
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paint = find.byType(CustomPaint);
    expect(paint, findsOneWidget);
    final center = tester.getCenter(paint);
    final size = tester.getSize(paint);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(center);
    await tester.pump();
    expect(find.byKey(const Key('chart-tip-title')), findsNothing);
    await gesture.removePointer();
    await tester.tapAt(center);
    await tester.pump();
    expect(tapped, isNull);
    // Control: the ring itself still hits.
    final outerR = math.min(size.width, size.height) / 2 - 4;
    await tester.tapAt(center + Offset(0, -(outerR + 40) / 2));
    await tester.pump();
    expect(tapped, isNotNull);
  });

  // m2: a hidden legend row keeps its share of the original total.
  testWidgets('hidden pie legend row keeps its share of the original total',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PieChartWidget(labels: const ['A', 'B'], values: const [1, 3]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    // B re-normalizes to 100%; the dimmed A row keeps 25.0% (1/4),
    // not 33.3% (1/3 of the visible total).
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('33.3%'), findsNothing);
  });

  // m3: no ghost ring past the last value.
  testWidgets('radial hit test has no ghost ring past the last value',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RadialChartWidget(
              labels: const ['A', 'B', 'C'], values: const [1, 2]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paint = find.byType(CustomPaint);
    expect(paint, findsOneWidget);
    final center = tester.getCenter(paint);
    final size = tester.getSize(paint);
    final outerR = math.min(size.width, size.height) / 2 - 8;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    // The third ring exists only in labels, not in values.
    await gesture.moveTo(center + Offset(outerR - 32, 0));
    await tester.pump();
    expect(find.byKey(const Key('chart-tip-title')), findsNothing);
    // Control: the first ring still hits.
    await gesture.moveTo(center + Offset(outerR, 0));
    await tester.pump();
    expect(find.byKey(const Key('chart-tip-title')), findsOneWidget);
    await gesture.removePointer();
  });

  // m4: a line chart with no categories paints nothing in the plot.
  testWidgets('line chart with no categories paints nothing in the plot',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: OpenUIRenderer(
            library: openUIStandardLibrary(),
            response: 'root = LineChart([], [Series("S", [1, 2])])',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-plot')), paintsNothing);
  });

  // m5: a single category's slot spans the whole content.
  test('single-category layout keeps slot and content widths equal', () {
    final layout = cartesianLayout(
      categories: const ['A'],
      all: const [
        [1.0],
      ],
      stacked: false,
      viewport: const Size(100, 200),
    );
    expect(layout.slotWidth, layout.contentWidth);
  });

  // m6: a tiny viewport never yields a negative label area.
  test('horizontal bar layout never yields a negative label area', () {
    final layout = hbarLayout(
      categories: const ['A'],
      all: const [
        [1.0],
      ],
      stacked: false,
      viewport: const Size(10, 200),
    );
    expect(layout.labelArea, greaterThanOrEqualTo(0));
    expect(layout.barW, greaterThanOrEqualTo(0));
  });

  // m7: a scatter dot with z names it in the tooltip.
  testWidgets('scatter tooltip names z when the dot has one',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: OpenUIRenderer(
            library: openUIStandardLibrary(),
            response:
                'root = ScatterChart([ScatterSeries("S", [Point(1, 2, 5), Point(3, 4)])])',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final widget =
        tester.widget<ScatterChartWidget>(find.byType(ScatterChartWidget));
    final paint = find.byType(CustomPaint);
    expect(paint, findsOneWidget);
    final topLeft = tester.getTopLeft(paint);
    final size = tester.getSize(paint);
    final layout = computeScatterLayout(widget.series);
    final plot = scatterPlotFor(layout, size);
    final d = layout.dots.first;
    final px = plot.left +
        plot.plotW *
            (d.x - plot.xDomain.min) /
            (plot.xDomain.max - plot.xDomain.min);
    final py = plot.plotH -
        (d.y - plot.yDomain.min) /
            (plot.yDomain.max - plot.yDomain.min) *
            plot.plotH;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(topLeft + Offset(px, py));
    await tester.pump();
    expect(find.byKey(const Key('chart-tip-title')), findsOneWidget);
    expect(find.text('z'), findsOneWidget);
    await gesture.removePointer();
  });

  // m8: right-click fires no tap.
  testWidgets('right-click does not fire chart onTap', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PieChartWidget(
            labels: const ['A', 'B'],
            values: const [1, 1],
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(CustomPaint));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(center);
    await gesture.down(center);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(tapped, isNull);
    await gesture.removePointer();
  });

  // m8: a second finger neither fires nor hijacks a tap.
  testWidgets('second finger does not hijack the first tap',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PieChartWidget(
            labels: const ['A', 'B'],
            values: const [1, 1],
            onTap: taps.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(CustomPaint));
    final first = await tester.startGesture(center);
    await tester.pump();
    final second = await tester.startGesture(center + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await tester.pump();
    expect(taps, hasLength(1));
    await second.up();
    await tester.pump();
    expect(taps, hasLength(1));
  });

  // m9: grouped bars pack after hiding a series (golden).
  testWidgets('golden: grouped bar packs after hiding a series',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: OpenUIRenderer(
              library: openUIStandardLibrary(),
              response: '''
root = BarChart(["A", "B"], [s1, s2])
s1 = Series("One", [10, 20])
s2 = Series("Two", [30, 40])
''',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_grouped_hidden.png'),
    );
  });

  // m10: hiding the last visible slice is refused.
  testWidgets('legend refuses to hide the last visible slice',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: PieChartWidget(labels: const ['A', 'B'], values: const [1, 1]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    int dimmed() => find
        .byWidgetPredicate((w) => w is Opacity && w.opacity == 0.3)
        .evaluate()
        .length;
    expect(dimmed(), 0);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(dimmed(), 1);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(dimmed(), 1);
  });

  // M2 goldens: one per previously uncovered chart type.
  testWidgets('golden: pie chart', (tester) async {
    await pumpGolden(tester, 'root = PieChart(["A", "B"], [3, 1])');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_pie.png'),
    );
  });

  testWidgets('golden: donut chart', (tester) async {
    await pumpGolden(
        tester, 'root = PieChart(["A", "B"], [3, 1], "donut")');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_donut.png'),
    );
  });

  testWidgets('golden: radial chart', (tester) async {
    await pumpGolden(tester, 'root = RadialChart(["A", "B"], [3, 1])');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_radial.png'),
    );
  });

  testWidgets('golden: scatter chart', (tester) async {
    await pumpGolden(tester,
        'root = ScatterChart([ScatterSeries("S", [Point(1, 2), Point(3, 4)])])');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_scatter.png'),
    );
  });

  testWidgets('golden: single stacked bar chart', (tester) async {
    await pumpGolden(
        tester, 'root = SingleStackedBarChart(["A", "B"], [3, 1])');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_stacked.png'),
    );
  });

  testWidgets('golden: area chart', (tester) async {
    await pumpGolden(
        tester, 'root = AreaChart(["A", "B"], [Series("S", [1, 2])])');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_area.png'),
    );
  });

  testWidgets('golden: step line chart', (tester) async {
    await pumpGolden(tester,
        'root = LineChart(["A", "B", "C"], [Series("S", [1, 3, 2])], "step")');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/chart_step.png'),
    );
  });
}
