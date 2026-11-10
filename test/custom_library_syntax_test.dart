import 'package:flutter_test/flutter_test.dart';
import 'package:openui_lang/openui_lang.dart';

void main() {
  test('custom function result field access parses inside a ternary', () {
    final library = OpenUILibrary(root: 'Card', components: const [
      ComponentDef('Card', 'card', [PropDef('children', PropType.nodeList, required: true), PropDef('variant', PropType.string), PropDef('padding', PropType.number), PropDef('gap', PropType.number)]),
      ComponentDef('Caption', 'caption', [PropDef('text', PropType.string, required: true)]),
      ComponentDef('Title', 'title', [PropDef('text', PropType.string, required: true), PropDef('size', PropType.string)]),
    ], functions: [
      defineFunction(name: 'Stats', description: 'stats', params: [const PropDef('values', PropType.list, required: true)], fn: (_) => {'mean': 1.2, 'stdev': 0.5}),
      defineFunction(name: 'Format', description: 'format', params: [const PropDef('value', PropType.number, required: true), const PropDef('kind', PropType.string), const PropDef('decimals', PropType.number)], fn: (args) => '${args['value']}'),
    ]);
    final result = parseOpenUI(r'''root = Card([Caption("Mean of the means"), Title(@Count(current) == 0 ? "-" : @Format(@Stats(current).mean, "number", 3), "xl"), Caption("Population: " + @Format(@Stats(pop).mean, "number", 3))], "soft", 3, 1)
current = [1, 2]
pop = [1, 2]''', library);
    expect(result.errors, isEmpty, reason: result.errors.join('; '));
  });

  test('custom input keeps an initially unset state binding', () {
    final library = OpenUILibrary(root: 'Input', components: const [
      ComponentDef('Input', 'input', [PropDef('value', PropType.any, required: true)]),
    ]);
    final result = parseOpenUI(r'root = Input($answer)', library);
    expect(result.root?.bindings['value'], 'answer');
    expect(result.errors, isEmpty);
  });
}
