import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:streamdown/streamdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openui_lang/openui_lang.dart';

void main() {
  testWidgets('MarkDownRenderer uses Streamdown for full Markdown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OpenUIRenderer(
              library: openUIStandardLibrary(),
              response: '''
root = MarkDownRenderer("# 标题\\n\\n- 一\\n- 二\\n\\n| a | b |\\n|---|---|\\n| 1 | 2 |\\n\\n> 引用\\n\\n`code` **粗体**")
''',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Streamdown), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
  });

  testWidgets('CodeBlock preserves fences and offers copy and highlighting', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OpenUIRenderer(
      library: openUIStandardLibrary(),
      response: 'root = CodeBlock("dart", "void main() { print(1); }\\n``` nested")',
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(Streamdown), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(tester.widget<HighlightView>(find.byType(HighlightView)).source, contains('``` nested'));
  });
}
