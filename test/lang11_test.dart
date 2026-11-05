import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openui_lang/openui_lang.dart';

/// OpenUI Lang 1.1 alignment suite: elementwise numeric builtins,
/// parse-time state defaults, chained queries with waiting and
/// cycle detection, line-based fence extraction, line comments,
/// and the streaming partial-marker hold.
void main() {
  final library = openUIStandardLibrary();

  String textOf(ParseResult r) => r.root!.stringOf('text');

  group('elementwise numeric builtins', () {
    test('@Round applies to each element of a list', () {
      final r = parseOpenUI(
          'root = TextContent("" + @Round([1.24, 1.26], 1))', library);
      expect(textOf(r), '[1.2, 1.3]');
    });

    test('@Round applies to nested lists', () {
      final r = parseOpenUI(
          'root = TextContent("" + @Round([[1.24, 1.26], [2.5]], 1))',
          library);
      expect(textOf(r), '[[1.2, 1.3], [2.5]]');
    });

    test('@Abs, @Floor and @Ceil apply to lists', () {
      expect(
          textOf(parseOpenUI(
              'root = TextContent("" + @Abs([-1, 2, -3]))', library)),
          '[1.0, 2.0, 3.0]');
      expect(
          textOf(parseOpenUI(
              'root = TextContent("" + @Floor([1.9, 2.1]))', library)),
          '[1.0, 2.0]');
      expect(
          textOf(parseOpenUI(
              'root = TextContent("" + @Ceil([1.1, 2.9]))', library)),
          '[2.0, 3.0]');
    });

    test('scalar behavior is unchanged', () {
      expect(
          textOf(parseOpenUI(
              'root = TextContent("" + @Round(1.26, 1))', library)),
          '1.3');
      expect(
          textOf(parseOpenUI('root = TextContent("" + @Abs(-5))', library)),
          '5.0');
      expect(
          textOf(parseOpenUI('root = TextContent("" + @Round("bad"))',
              library)),
          '');
    });
  });

  group('state defaults are evaluated once at parse time', () {
    test('expression default evaluates to a value', () {
      final r = parseOpenUI(
          '\$total = 1 + 2\nroot = TextContent("" + \$total)', library);
      expect(textOf(r), '3');
    });

    test('default reads earlier states only, not host state', () {
      final r = parseOpenUI(
          '\$price = 100\n\$tax = \$price * 0.18\nroot = TextContent("" + \$tax)',
          library,
          state: {'price': 200});
      // The default freezes the earlier default (100), not the host
      // value (200); a value that should follow is a plain statement.
      expect(textOf(r), '18.0');
    });

    test('plain statement follows host state', () {
      final r = parseOpenUI(
          'tax = \$price * 0.18\nroot = TextContent("" + tax)', library,
          state: {'price': 200});
      expect(textOf(r), '36.0');
    });

    test('a state declared after reads as null', () {
      final r = parseOpenUI(
          '\$a = \$b + 1\n\$b = 5\nroot = TextContent("" + \$a)', library);
      // The forward read still yields null (not the later 5, which
      // would give 6); M2 upstream arithmetic then coerces null to
      // 0, so null + 1 is 1. The old null-propagating + gave ''.
      expect(textOf(r), '1');
    });

    test('plain statements referenced by a default are inlined', () {
      final r = parseOpenUI(
          'base = 5\n\$total = base + 1\nroot = TextContent("" + \$total)',
          library);
      expect(textOf(r), '6');
    });

    test('a plain statement declared after is inlined too', () {
      final r = parseOpenUI(
          '\$total = base + 1\nbase = 5\nroot = TextContent("" + \$total)',
          library);
      expect(textOf(r), '6');
    });

    test('a query result read by a default is null, even with data', () {
      final r = parseOpenUI(
          'q = Query("t")\n\$x = q.value\nroot = TextContent("" + \$x)',
          library,
          queryData: {
            'q': {'value': 7}
          });
      expect(textOf(r), '');
    });

    test('a library function call in a default is null, a builtin works',
        () {
      final lib = openUIStandardLibrary().extend(functions: [
        defineFunction(
            name: 'Double',
            description: 'Double it',
            params: [const PropDef('n', PropType.number, required: true)],
            fn: (args) => (args['n'] as num) * 2),
      ]);
      final custom = parseOpenUI(
          '\$x = @Double(21)\nroot = TextContent("" + \$x)', lib);
      expect(textOf(custom), '');
      final builtin = parseOpenUI(
          '\$y = @Count([1, 2, 3])\nroot = TextContent("" + \$y)',
          library);
      expect(textOf(builtin), '3');
    });

    test('defaults inside lists and objects are evaluated', () {
      final r = parseOpenUI(
          '\$p = 10\n\$xs = [1 + 2, \$p * 2]\nroot = TextContent("" + \$xs)',
          library);
      expect(textOf(r), '[3, 20]');
      final o = parseOpenUI(
          '\$p = 10\n\$o = {v: \$p + 1}\nroot = TextContent("" + \$o)',
          library);
      expect(textOf(o), '{v: 11}');
    });
  });

  group('chained queries', () {
    test('queries that read each other report query-cycle and do not run',
        () {
      final r = parseOpenUI('''
a = Query("ta", {v: b.value})
b = Query("tb", {v: a.value})
root = TextContent("x")
''', library);
      expect(r.errors.map((e) => e.code), contains('query-cycle'));
      expect(r.queries, isEmpty);
      expect(r.root, isNotNull);
    });

    test('a query that reads itself is a cycle', () {
      final r = parseOpenUI('''
a = Query("ta", {v: a.value})
root = TextContent("x")
''', library);
      expect(r.errors.map((e) => e.code), contains('query-cycle'));
      expect(r.queries, isEmpty);
    });

    test('a query waits for a loading query and does not fetch', () {
      final r = parseOpenUI('''
q1 = Query("t1")
q2 = Query("t2", {v: q1.value})
root = TextContent("" + q2.value)
''', library);
      expect(r.queries.map((q) => q.statementName), ['q1']);
      expect(r.root!.component, '__Skeleton');
    });

    test('once the dependency has data, the reader runs with real args',
        () {
      final r = parseOpenUI('''
q1 = Query("t1")
q2 = Query("t2", {v: q1.value})
root = TextContent("" + q2.value)
''', library, queryData: {
        'q1': {'value': 5}
      });
      expect(
          r.queries.map((q) => q.statementName), containsAll(['q1', 'q2']));
      final q2 = r.queries.firstWhere((q) => q.statementName == 'q2');
      expect(q2.params, {'v': 5});
    });

    test('a reader of a failed query keeps its defaults and does not run',
        () {
      // The reader itself evaluates to its initial value; .value
      // would read a field of that string, so assert on the query.
      final r = parseOpenUI('''
q1 = Query("t1")
q2 = Query("t2", {v: q1.value}, "fallback")
root = TextContent("" + q2)
''', library, failedQueries: {'q1'});
      expect(
          r.queries.map((q) => q.statementName), contains('q1'));
      expect(r.queries.map((q) => q.statementName), isNot(contains('q2')));
      expect(textOf(r), 'fallback');
    });

    test('a query that reads a cyclic query waits and keeps defaults', () {
      final r = parseOpenUI('''
a = Query("ta", {v: b.value})
b = Query("tb", {v: a.value})
c = Query("tc", {v: a.value}, "cdefault")
root = TextContent("" + c)
''', library);
      expect(r.errors.map((e) => e.code), contains('query-cycle'));
      expect(r.queries, isEmpty);
      expect(textOf(r), 'cdefault');
    });

    test('query args read forward references and aliases', () {
      // The root reads the query so its request is collected.
      final forward = parseOpenUI('''
q = Query("save", {amount: amount})
amount = 42
root = TextContent("" + q.value)
''', library);
      expect(forward.errors, isEmpty);
      expect(forward.queries.single.params, {'amount': 42});

      final alias = parseOpenUI('''
q = Query("t", args)
args = {v: \$n * 2}
root = TextContent("" + q.value)
''', library, state: {'n': 3});
      expect(alias.errors, isEmpty);
      expect(alias.queries.single.params, {'v': 6});
    });

    test('mutation args read other statements', () {
      // Referencing the mutation evaluates it, collecting its request.
      final r = parseOpenUI('''
m = Mutation("save", {v: total})
total = 40
x = m
root = TextContent("" + x)
''', library);
      expect(r.errors, isEmpty);
      expect(r.mutations.single.params, {'v': 40});
    });
  });

  group('shared nodes are copied per statement', () {
    test('an alias renders with its own statement id', () {
      final r = parseOpenUI('''
a = TextContent("hi")
b = a
root = Stack([a, b])
''', library);
      final children = r.root!.nodesOf('children');
      expect(children.map((c) => c.statementId), ['a', 'b']);
    });
  });

  group('fence extraction', () {
    test('a fenced program renders, prose is ignored', () {
      final r = parseOpenUI(
          'Here is the UI:\n```openui\nroot = TextContent("hi")\n```\nHope that helps',
          library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('an inline backtick pair in prose does not eat the program', () {
      final r = parseOpenUI(
          'Use ```openui``` inline here\nroot = TextContent("hi")',
          library);
      // The program survives. Unlike upstream, which silently skips
      // invalid lines, this package still reports the prose line as
      // parse-failed (deliberate, pre-existing behavior).
      expect(textOf(r), 'hi');
      expect(r.errors.map((e) => e.code), ['parse-failed']);
    });

    test('code on the opener line is kept', () {
      final r = parseOpenUI(
          '```openui root = TextContent("hi")\n```', library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('openui-js blocks are skipped', () {
      final r = parseOpenUI(
          '```openui-js\nconsole.log(1)\n```\nroot = TextContent("hi")',
          library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('a stray closing fence falls back to the unfenced program', () {
      final r = parseOpenUI('root = TextContent("hi")\n```', library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('js helper blocks after the program do not hide it', () {
      final r = parseOpenUI(
          'root = TextContent("hi")\n```js\nconst x = 1;\n```', library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('backticks inside a string value do not open a fence', () {
      final r = parseOpenUI('root = TextContent("```")', library);
      expect(r.errors, isEmpty);
      expect(textOf(r), '```');
    });

    test('an unterminated fence runs to the end of the text', () {
      final r = parseOpenUI('```openui\nroot = TextContent("hi")', library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });
  });

  group('line comments', () {
    test('full-line // and # comments are skipped', () {
      final r = parseOpenUI(
          '// note\n# note\nroot = TextContent("hi")', library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('trailing comments are stripped', () {
      final r = parseOpenUI(
          'root = TextContent("hi") // trailing\nx = 1 # trailing',
          library);
      expect(r.errors, isEmpty);
      expect(textOf(r), 'hi');
    });

    test('comment markers inside strings are kept', () {
      final r = parseOpenUI(
          'root = TextContent("http://x/#y")', library);
      expect(textOf(r), 'http://x/#y');
      final h = parseOpenUI('root = TextContent("a#b")', library);
      expect(textOf(h), 'a#b');
    });

    test('division is not a comment', () {
      final r = parseOpenUI(
          'v = 10 / 2\nroot = TextContent("" + v)', library);
      expect(textOf(r), '5.0');
    });
  });

  group('chained queries end to end', () {
    testWidgets('a chained query does not fetch until its dependency resolves',
        (tester) async {
      final calls = <String, Map<String, Object?>>{};
      final q1Completer = Completer<Object?>();
      Future<Object?> provider(String tool, Map<String, Object?> params) {
        calls[tool] = params;
        if (tool == 't1') return q1Completer.future;
        if (tool == 't2') return Future.value({'label': 'done'});
        return Future.value(null);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: OpenUIRenderer(
            library: library,
            response: '''
root = Stack([t])
t = TextContent("" + q2.label)
q1 = Query("t1")
q2 = Query("t2", {v: q1.value})
''',
            toolProvider: provider,
          ),
        ),
      );
      await tester.pump();
      // q1 fetched; q2 has not, it waits for q1's result.
      expect(calls.containsKey('t1'), isTrue);
      expect(calls.containsKey('t2'), isFalse);

      q1Completer.complete({'value': 9});
      await tester.pumpAndSettle();
      // Now q2 fetches with the real argument, and renders its data.
      expect(calls['t2'], {'v': 9});
      expect(find.text('done'), findsOneWidget);
    });
  });

  group('streaming partial-marker hold', () {
    test('a chunk ending mid-marker produces no parse error', () {
      final parser = StreamingParser(library);
      final r = parser.push('root = TextContent("hi")\n]]>op');
      expect(r.errors.map((e) => e.code), isNot(contains('parse-failed')));
      expect(textOf(r), 'hi');
    });

    test('a complete marker line is still skipped', () {
      final parser = StreamingParser(library);
      final r = parser.push('root = TextContent("hi")\n]]>openui:content\n');
      expect(r.errors.map((e) => e.code), isNot(contains('parse-failed')));
      expect(textOf(r), 'hi');
    });
  });
}
