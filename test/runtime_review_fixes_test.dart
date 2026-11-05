import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openui_lang/openui_lang.dart';

// Regression tests for the runtime/widgets review fixes (M1-M6,
// minors 1/2/3/5/8/9, charts m14). The M5 scalar-data end-to-end
// case needs the library change (Col data widened to _any), which
// landed with the core batch, so it is covered below.

Future<void> _pumpResponse(
  WidgetTester tester,
  String response, {
  Map<String, Object?> initialState = const {},
  ComponentRegistry? registry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SingleChildScrollView(
        child: OpenUIRenderer(
          library: openUIStandardLibrary(),
          response: response,
          initialState: initialState,
          registry: registry,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The single text field on screen, read through its inner TextField.
String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  group('M1 synced text fields', () {
    testWidgets('Input value prop change updates the display', (tester) async {
      await _pumpResponse(tester, 'root = Stack([q])\nq = Input("name", null, null, null, "甲")\n');
      expect(_fieldText(tester), '甲');
      await _pumpResponse(tester, 'root = Stack([q])\nq = Input("name", null, null, null, "乙")\n');
      expect(_fieldText(tester), '乙');
    });

    testWidgets('Input follows controller setFormValue', (tester) async {
      final controller = OpenUIController(library: openUIStandardLibrary());
      controller.push('root = Stack([q])\nq = Input("name")\n');
      controller.finish();
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: OpenUIRenderer(library: controller.library, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_fieldText(tester), '');
      controller.setFormValue('name', '外部值');
      await tester.pump();
      expect(_fieldText(tester), '外部值');
      controller.dispose();
    });

    testWidgets('TextArea value prop change updates the display', (tester) async {
      await _pumpResponse(tester, 'root = Stack([a])\na = TextArea("bio", null, null, null, "甲")\n');
      expect(_fieldText(tester), '甲');
      await _pumpResponse(tester, 'root = Stack([a])\na = TextArea("bio", null, null, null, "乙")\n');
      expect(_fieldText(tester), '乙');
    });

    testWidgets('table cell data change updates the display', (tester) async {
      const columns = '[{"type": "text", "key": "name", "header": "姓名"}]';
      await _pumpResponse(
        tester,
        'root = Stack([t])\nt = EditableTable("staff", $columns, [{"id": "r1", "values": ["甲"]}])\n',
      );
      expect(_fieldText(tester), '甲');
      await _pumpResponse(
        tester,
        'root = Stack([t])\nt = EditableTable("staff", $columns, [{"id": "r1", "values": ["乙"]}])\n',
      );
      expect(_fieldText(tester), '乙');
    });

    testWidgets('typing keeps focus across rebuilds', (tester) async {
      await _pumpResponse(tester, 'root = Stack([q])\nq = Input("name")\n');
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      expect(focus, isNotNull);
      // enterText drives onChanged, which rebuilds the field with
      // the new value. A per-keystroke rebuild (e.g. ValueKey on
      // the value) would replace the FocusNode and drop focus;
      // the synced controller keeps the same node focused.
      await tester.enterText(find.byType(TextFormField), 'hello');
      await tester.pump();
      expect(_fieldText(tester), 'hello');
      expect(FocusManager.instance.primaryFocus, same(focus));
    });
  });

  group('M2 touched tracking', () {
    const form = 'root = Stack([f])\nf = FormControl("邮箱", Input("email", null, null, {"email": true}), "提示")\n';

    testWidgets('initialState invalid email shows no error pre-interaction', (tester) async {
      await _pumpResponse(tester, form, initialState: {'email': 'bad'});
      expect(find.text('Enter a valid email address.'), findsNothing);
    });

    testWidgets('controller setFormValue invalid email shows no error pre-interaction', (tester) async {
      final controller = OpenUIController(library: openUIStandardLibrary());
      controller.push(form);
      controller.finish();
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: OpenUIRenderer(library: controller.library, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.setFormValue('email', 'bad');
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsNothing);
      controller.dispose();
    });

    testWidgets('typing invalid after prefill shows error', (tester) async {
      await _pumpResponse(tester, form, initialState: {'email': 'a@b.com'});
      expect(find.text('Enter a valid email address.'), findsNothing);
      await tester.enterText(find.byType(TextFormField), 'bad');
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('blur marks the field touched', (tester) async {
      await _pumpResponse(
        tester,
        'root = Stack([f])\nf = FormControl("姓名", Input("name", null, null, {"required": true}), "提示")\n',
      );
      expect(find.text('This field is required.'), findsNothing);
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      expect(find.text('This field is required.'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
    });

    testWidgets('Reset clears touched so the required error stays gone', (tester) async {
      await _pumpResponse(
        tester,
        'root = Stack([f, btn])\nf = FormControl("姓名", Input("name", null, null, {"required": true}), "提示")\nbtn = Button("重置", Action([@Reset(\$name)]))\n',
      );
      expect(find.text('This field is required.'), findsNothing);
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
      // Without the touched clear, Reset empties the field but the
      // error reappears immediately with no new interaction.
      await tester.tap(find.text('重置'));
      await tester.pump();
      expect(find.text('This field is required.'), findsNothing);
    });

    testWidgets('controller mode Reset clears touched', (tester) async {
      final controller = OpenUIController(library: openUIStandardLibrary());
      controller.push(
        'root = Stack([f, btn])\nf = FormControl("姓名", Input("name", null, null, {"required": true}), "提示")\nbtn = Button("重置", Action([@Reset(\$name)]))\n',
      );
      controller.finish();
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            child: OpenUIRenderer(library: controller.library, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This field is required.'), findsNothing);
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
      await tester.tap(find.text('重置'));
      await tester.pump();
      expect(find.text('This field is required.'), findsNothing);
      controller.dispose();
    });
  });

  group('M3 numbered ListBlock routing', () {
    const program = 'root = Stack([l])\nl = ListBlock([ListItem("甲"), ListItem("乙")], "number")\n';

    testWidgets('custom ListItem builder wins over numbered tiles', (tester) async {
      final registry = ComponentRegistry(builders: {
        'ListItem': (context, node, renderChild) => Text('CUSTOM:${node.stringOf('title')}'),
      });
      await _pumpResponse(tester, program, registry: registry);
      expect(find.text('CUSTOM:甲'), findsOneWidget);
      expect(find.text('CUSTOM:乙'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('no custom builder still renders numbered tiles', (tester) async {
      await _pumpResponse(tester, program);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('乙'), findsOneWidget);
    });
  });

  testWidgets('M4 EditableTable string width renders', (tester) async {
    await _pumpResponse(
      tester,
      'root = Stack([t])\nt = EditableTable("staff", [{"type": "text", "key": "name", "header": "姓名", "width": "120"}], [{"id": "r1", "values": ["甲"]}])\n',
    );
    expect(find.text('姓名'), findsOneWidget);
    expect(_fieldText(tester), '甲');
  });

  testWidgets('M4 EditableTable non-finite string widths fall back', (tester) async {
    // double.tryParse accepts 'NaN'/'Infinity'; a NaN width would
    // trip the BoxConstraints assertion, so rendering proves the
    // 120.0 fallback.
    await _pumpResponse(
      tester,
      'root = Stack([t])\nt = EditableTable("staff", [{"type": "text", "key": "name", "header": "姓名", "width": "NaN"}], [{"id": "r1", "values": ["甲"]}])\n',
    );
    expect(find.text('姓名'), findsOneWidget);
    expect(_fieldText(tester), '甲');
    await _pumpResponse(
      tester,
      'root = Stack([t])\nt = EditableTable("staff", [{"type": "text", "key": "name", "header": "姓名", "width": "Infinity"}], [{"id": "r1", "values": ["甲"]}])\n',
    );
    expect(find.text('姓名'), findsOneWidget);
    expect(_fieldText(tester), '甲');
  });

  testWidgets('M5 Table Col list data still renders', (tester) async {
    await _pumpResponse(
      tester,
      'root = Stack([t])\nt = Table([m])\nm = Col("Month", ["Jan", "Feb"])\n',
    );
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Jan'), findsOneWidget);
    expect(find.text('Feb'), findsOneWidget);
  });

  testWidgets('M5 Table Col scalar data renders as a single row', (tester) async {
    await _pumpResponse(
      tester,
      'root = Stack([t])\nt = Table([m])\nm = Col("M", "Jan")\n',
    );
    expect(find.text('M'), findsOneWidget);
    expect(find.text('Jan'), findsOneWidget);
  });

  group('M6 and minor 9 date pickers', () {
    testWidgets('DatePickerField opens on its 1995 value and writes it back', (tester) async {
      Object? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatePickerField(
              stateKey: 'd',
              value: '1995-06-15',
              onChanged: (key, v) => saved = v,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Opening on the current value (not today) is what makes the
      // round-trip exact; a 2000 firstDate would have asserted.
      expect(saved, '1995-06-15');
    });

    testWidgets('DateRangeField opens on its 1995 range and confirms it', (tester) async {
      Object? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateRangeField(
              stateKey: 'r',
              value: {'from': '1995-01-01', 'to': '1995-12-31'},
              onChanged: (key, v) => saved = v,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, {'from': '1995-01-01', 'to': '1995-12-31'});
    });
  });

  testWidgets('minor 8 SliderField with min greater than max renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderField(
            label: '音量',
            stateKey: 'v',
            value: 50,
            min: 100,
            max: 0,
            onChanged: (key, v) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 50);
  });

  group('minor 2 Run refetch loading', () {
    const program = '''
root = Stack([count, btn])
count = TextContent("" + @Count(tickets.rows))
tickets = Query("list_tickets", {}, {"rows": []})
btn = Button("刷新", Action([@Run(tickets)]))
''';

    testWidgets('renderer mode shows loading immediately on refetch', (tester) async {
      final secondFetch = Completer<Object?>();
      var calls = 0;
      Future<Object?> provider(String tool, Map<String, Object?> params) {
        calls++;
        if (calls == 1) return Future.value({'rows': [1]});
        return secondFetch.future;
      }
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUIRenderer(
            library: openUIStandardLibrary(),
            response: program,
            toolProvider: provider,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('刷新'));
      await tester.pump();
      // The old result must be gone before the fetch completes:
      // without the post-clear rebuild it would still show '1'.
      expect(find.text('1'), findsNothing);
      secondFetch.complete({'rows': [1, 2, 3]});
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('controller mode shows loading immediately on refetch', (tester) async {
      final secondFetch = Completer<Object?>();
      var calls = 0;
      Future<Object?> provider(String tool, Map<String, Object?> params) {
        calls++;
        if (calls == 1) return Future.value({'rows': [1]});
        return secondFetch.future;
      }
      final controller = OpenUIController(library: openUIStandardLibrary(), toolProvider: provider);
      controller.push(program);
      controller.finish();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OpenUIRenderer(library: controller.library, controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('刷新'));
      await tester.pump();
      expect(find.text('1'), findsNothing);
      secondFetch.complete({'rows': [1, 2, 3]});
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      controller.dispose();
    });
  });

  testWidgets('minor 1 Modal dialog content follows state changes while open', (tester) async {
    final controller = OpenUIController(library: openUIStandardLibrary());
    // TextContent (not bare Text): bare Text is not in Modal's
    // content child union and is dropped at parse time.
    controller.push('root = Stack([m])\nm = Modal("标题", true, [TextContent("" + \$msg)])\n');
    controller.finish();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpenUIRenderer(library: controller.library, controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    controller.setFormValue('msg', 'first');
    // pumpAndSettle: the content bump is deferred to post-frame,
    // so one pump only schedules it and a second frame applies it.
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    controller.setFormValue('msg', 'second');
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    controller.dispose();
  });

  test('minor 3 controller formValue/hasFormValue read without copying', () {
    final controller = OpenUIController(library: openUIStandardLibrary());
    expect(controller.hasFormValue('a'), isFalse);
    controller.setFormValue('a', 1);
    expect(controller.hasFormValue('a'), isTrue);
    expect(controller.formValue('a'), 1);
    controller.dispose();
  });

  test('minor 5 OpenUIColorScheme compares by value', () {
    // Runtime-built plain Colors defeat const canonicalization, so
    // this proves == is value-based rather than identity-based.
    // (MaterialColor and plain Color of one value are NOT equal:
    // Color's == also requires matching runtimeType, so both sides
    // must be plain Colors for the comparison to be meaningful.)
    final blue = Colors.blue.toARGB32();
    final white = Colors.white.toARGB32();
    final black87 = Colors.black87.toARGB32();
    final a = OpenUIColorScheme(
      primary: Color(blue),
      surface: Color(white),
      onSurface: Color(black87),
    );
    final b = OpenUIColorScheme(
      primary: Color(Colors.blue.toARGB32()),
      surface: Color(Colors.white.toARGB32()),
      onSurface: Color(Colors.black87.toARGB32()),
    );
    expect(identical(a, b), isFalse);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    expect(
      a ==
          OpenUIColorScheme(
            primary: const Color(0xFFFF0000),
            surface: Color(white),
            onSurface: Color(black87),
          ),
      isFalse,
    );
  });

  testWidgets('m14 dark-theme bar chart axis labels use the theme axisText color', (tester) async {
    final controller = OpenUIController(
      library: openUIStandardLibrary(),
      theme: OpenUIThemeData.dark(),
    );
    controller.push(
      'root = Stack([c])\nc = BarChart(["a", "b"], [Series("s", [1, 2])], null, "months", "value")\n',
    );
    controller.finish();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpenUIRenderer(library: controller.library, controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    // Dark textMuted, not the old hardcoded grey (0xFF9E9E9E).
    expect(tester.widget<Text>(find.text('months')).style?.color, const Color(0xFFBDBDBD));
    expect(tester.widget<Text>(find.text('value')).style?.color, const Color(0xFFBDBDBD));
    controller.dispose();
  });
}
