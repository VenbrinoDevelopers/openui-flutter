import 'package:flutter/widgets.dart';

import 'lang.dart';

/// Builds a component node. [renderChild] renders a child node through the
/// renderer's own node builder, so theme, form state and Query data flow
/// through a custom component exactly as they do through a built-in one.
typedef OpenUIComponentBuilder = Widget Function(BuildContext context, ElementNode node, Widget Function(ElementNode) renderChild);

/// Host operations available to app-owned interactive components.
abstract class OpenUIBuilderHost {
  bool get isStreaming;
  Object? stateValue(String key);
  bool stateHas(String key);
  void setValue(String key, Object? value);
  Future<void> dispatch(Object? action);
}

typedef OpenUIHostComponentBuilder = Widget Function(
  BuildContext context,
  ElementNode node,
  Widget Function(ElementNode) renderChild,
  OpenUIBuilderHost host,
);

/// Immutable registry of custom component builders, keyed by component name.
class ComponentRegistry {
  const ComponentRegistry({
    Map<String, OpenUIComponentBuilder> builders = const {},
    Map<String, OpenUIHostComponentBuilder> hostBuilders = const {},
  }) : _builders = builders, _hostBuilders = hostBuilders;
  final Map<String, OpenUIComponentBuilder> _builders;
  final Map<String, OpenUIHostComponentBuilder> _hostBuilders;

  OpenUIComponentBuilder? lookup(String name) => _builders[name];
  OpenUIHostComponentBuilder? lookupHost(String name) => _hostBuilders[name];

  ComponentRegistry withBuilder(String name, OpenUIComponentBuilder builder) {
    return ComponentRegistry(builders: {..._builders, name: builder}, hostBuilders: _hostBuilders);
  }

  ComponentRegistry withHostBuilder(String name, OpenUIHostComponentBuilder builder) {
    return ComponentRegistry(builders: _builders, hostBuilders: {..._hostBuilders, name: builder});
  }
}
