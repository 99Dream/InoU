import 'package:flutter/widgets.dart';

/// Material 3 window width size classes.
enum WindowClass {
  compact,
  medium,
  expanded;

  static WindowClass fromWidth(double widthDp) {
    if (widthDp < 600) return WindowClass.compact;
    if (widthDp < 840) return WindowClass.medium;
    return WindowClass.expanded;
  }
}

/// Provides [WindowClass] down the widget tree based on window width.
class AdaptiveScope extends InheritedWidget {
  const AdaptiveScope({
    super.key,
    required this.windowClass,
    required super.child,
  });

  final WindowClass windowClass;

  static WindowClass of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdaptiveScope>();
    if (scope != null) return scope.windowClass;
    return WindowClass.fromWidth(MediaQuery.sizeOf(context).width);
  }

  @override
  bool updateShouldNotify(AdaptiveScope oldWidget) =>
      windowClass != oldWidget.windowClass;
}

/// Wraps [child] in an [AdaptiveScope] computed from [MediaQuery.sizeOf].
class AdaptiveScopeProvider extends StatelessWidget {
  const AdaptiveScopeProvider({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AdaptiveScope(
      windowClass: WindowClass.fromWidth(width),
      child: child,
    );
  }
}

/// Renders layout variants based on [WindowClass].
class AdaptiveBuilder extends StatelessWidget {
  const AdaptiveBuilder({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  final WidgetBuilder compact;
  final WidgetBuilder? medium;
  final WidgetBuilder? expanded;

  @override
  Widget build(BuildContext context) {
    final windowClass = AdaptiveScope.of(context);
    return switch (windowClass) {
      WindowClass.compact => compact(context),
      WindowClass.medium => (medium ?? compact)(context),
      WindowClass.expanded => (expanded ?? medium ?? compact)(context),
    };
  }
}
