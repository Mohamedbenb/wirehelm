import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/customization/network_indicator_preview.dart';

void main() {
  testWidgets('designs and unit modes fit narrow previews with large UI text', (tester) async {
    for (final design in ['plain', 'pill', 'outline', 'mono', 'glass', 'box', 'split', 'badge']) {
      for (final mode in ['full', 'unit', 'prefix', 'none', 'custom']) {
        for (final layout in ['inline', 'stacked']) {
          for (final gap in [-4, 0, 8]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(width: 240, child: NetworkIndicatorPreview(config: {
            'indicatorDesign': design, 'unitLabel': mode, 'unitSuffix': 'custom',
            'showUpload': true, 'showArrows': true, 'arrowGap': -3,
            'boldValue': true, 'boldText': true, 'unitGap': gap, 'unitScale': 120,
            'rateWidth': 64, 'layout': layout,
          })),
        ))));
        expect(tester.takeException(), isNull, reason: '$design/$mode/$layout/$gap');
          }
        }
      }
    }
  });
  testWidgets('drag publishes bounded live positions and reset restores anchor', (tester) async {
    var config = <String, dynamic>{'showUpload': false, 'showArrows': false};
    final positions = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) => NetworkIndicatorPreview(config: config,
        onPositionChanged: (value) { positions.add(value); setState(() => config = {...config, 'horizontalPosition': value}); }),
    ))));
    await tester.drag(find.text('24.8'), const Offset(150, 0));
    await tester.pump();
    expect(positions, isNotEmpty);
    expect(positions.every((value) => value >= 0 && value <= 1000), isTrue);
    await tester.tap(find.text('Reset position'));
    await tester.pump();
    expect(positions.last, -1);
    expect(tester.takeException(), isNull);
  });
}
