import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/search_overlay_size_controls.dart';

void main() {
  testWidgets(
    'search dimensions preserve position and shared optical settings',
    (t) async {
      Map<String, dynamic> config = {
        'backend': 'native',
        'engine': 'card',
        'cardMaterial': {'blurStrength': 12, 'glassTintColor': '#225588'},
        'searchTray': {'x': .3, 'y': .6},
      };
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => SingleChildScrollView(
                child: SearchOverlaySizeControls(
                  config: config,
                  onChanged: (v) => set(() => config = v),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Search overlay size'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-overlay-width')), findsNothing);
      await t.tap(find.text('Custom search dimensions'));
      await t.pumpAndSettle();
      t
          .widget<Slider>(find.byKey(const ValueKey('search-overlay-width')))
          .onChanged!(340);
      await t.pump();
      t
          .widget<Slider>(find.byKey(const ValueKey('search-overlay-height')))
          .onChanged!(720);
      await t.pump();
      expect(config['searchTray'], {
        'x': .3,
        'y': .6,
        'width': 340,
        'height': 720,
      });
      expect(config['cardMaterial'], {
        'blurStrength': 12,
        'glassTintColor': '#225588',
      });
      expect(config['backend'], 'native');
      expect(config['engine'], 'card');
      await t.ensureVisible(find.text('Custom search dimensions'));
      await t.tap(find.text('Custom search dimensions'));
      await t.pumpAndSettle();
      expect(config['searchTray'], {'x': .3, 'y': .6, 'width': 0, 'height': 0});
      expect(find.byKey(const ValueKey('search-overlay-height')), findsNothing);
    },
  );
}
