import 'package:flutter/material.dart';

const clipboardShelfRoute = '/clipboard-shelf';
const edgeActionsRoute = '/edge-actions';
final appShortcutNavigation = AppShortcutNavigation();

/// Reuse the current app navigator; a repeated shortcut does not stack the same page.
class AppShortcutNavigation extends WidgetsBindingObserver {
  final key = GlobalKey<NavigatorState>();
  final observer = _TopRouteObserver();
  bool _attached = false;
  void attach() {
    if (!_attached) {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    }
  }

  void detach() {
    if (_attached) {
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final route = routeInformation.uri.path;
    if (route != clipboardShelfRoute && route != edgeActionsRoute) return false;
    void open() {
      if (key.currentState != null &&
          observer.current?.settings.name != route) {
        key.currentState!.pushNamed(route);
      }
    }

    if (key.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => open());
    } else {
      open();
    }
    return true;
  }
}

class _TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? current;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    current = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    current = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (current == oldRoute) {
      current = newRoute;
    }
  }
}
