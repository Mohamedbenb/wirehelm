import 'package:flutter/material.dart';

class NetworkIndicatorPreview extends StatefulWidget {
  final Map<String, dynamic> config;
  final ValueChanged<int>? onPositionChanged;
  const NetworkIndicatorPreview({super.key, required this.config, this.onPositionChanged});
  @override
  State<NetworkIndicatorPreview> createState() => _NetworkIndicatorPreviewState();
}

class _NetworkIndicatorPreviewState extends State<NetworkIndicatorPreview> {
  final _trackKey = GlobalKey();
  final _meterKey = GlobalKey();
  double _dragLeft = 0;
  double _travel = 1;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final design = config['indicatorDesign'] as String? ?? 'plain';
    final horizontal = (config['horizontalPosition'] as num?)?.toInt() ?? -1;
    final right = config['position'] == 'right';
    final stacked = config['layout'] != 'inline';
    final upload = config['showUpload'] != false;
    final arrows = config['showArrows'] != false;
    final bits = config['units'] == 'bits';
    final decimals = (config['decimals'] as num?)?.toInt() ?? 1;
    final size = (config['textSize'] as num?)?.toDouble() ?? 10;
    final stackedSize = (config['stackedTextSize'] as num?)?.toDouble() ?? 8;
    final arrowScale = (config['arrowScale'] as num?)?.toDouble() ?? 140;
    final activeSize = stacked ? stackedSize : size;
    final indicatorHeight =
        (config['indicatorHeight'] as num?)?.toDouble() ?? 16;
    final rateWidth = (config['rateWidth'] as num?)?.toDouble() ?? 38;
    final arrowGap = (config['arrowGap'] as num?)?.toDouble() ?? 0;
    final directionGap = (config['directionGap'] as num?)?.toDouble() ?? 6;
    final iconGap = (config['iconGap'] as num?)?.toDouble() ?? 6;
    final verticalOffset = (config['verticalOffset'] as num?)?.toDouble() ?? 0;
    final labelMode = config['unitLabel'] as String? ?? 'full';
    final fullUnit = bits ? 'Kb/s' : 'KB/s';
    final unit = switch (labelMode) {
      'none' => '', 'prefix' => 'K', 'unit' => bits ? 'Kb' : 'KB',
      'custom' => 'K${config['unitSuffix'] ?? 'B/s'}', _ => fullUnit,
    };
    final unitGap = (config['unitGap'] as num?)?.toDouble() ?? 1;
    final unitScale = ((config['unitScale'] as num?)?.toDouble() ?? 100) / 100;
    final valueWeight = config['boldValue'] == true ? FontWeight.bold : FontWeight.normal;
    final textWeight = config['boldText'] == true ? FontWeight.bold : FontWeight.normal;
    final family = design == 'mono' ? 'monospace' : null;
    final ink = design == 'badge' ? Colors.black : Colors.white;
    final tightGap = unitGap.clamp(-activeSize * 0.15, 8.0);
    double textExtent(String value, TextStyle style, {bool height = false}) {
      final painter = TextPainter(text: TextSpan(text: value, style: style), textDirection: TextDirection.ltr)..layout();
      final extent = height ? painter.height : painter.width;
      painter.dispose();
      return extent;
    }
    Widget rate(bool sending) {
      final value = (sending ? (bits ? 25.6 : 3.2) : (bits ? 198.4 : 24.8)).toStringAsFixed(decimals);
      final valueStyle = TextStyle(color: ink, fontSize: activeSize, height: 0.95, fontWeight: valueWeight, fontFamily: family);
      final unitStyle = TextStyle(color: ink, fontSize: activeSize * unitScale, height: 0.95, fontWeight: textWeight, fontFamily: family);
      final unitText = Text(unit, style: unitStyle);
      Widget contents;
      if (stacked && unit.isNotEmpty) {
        final extent = textExtent(unit, unitStyle, height: true).clamp(1.0, double.infinity);
        contents = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: valueStyle),
          if (tightGap >= 0) SizedBox(height: tightGap),
          Align(alignment: Alignment.bottomCenter, heightFactor: tightGap < 0 ? (1 + tightGap / extent).clamp(0.1, 1.0) : 1, child: unitText),
        ]);
      } else {
        final extent = textExtent(unit, unitStyle).clamp(1.0, double.infinity);
        contents = Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: valueStyle),
          if (unit.isNotEmpty) ...[
            if (tightGap >= 0) SizedBox(width: tightGap),
            Align(alignment: Alignment.centerRight, widthFactor: tightGap < 0 ? (1 + tightGap / extent).clamp(0.1, 1.0) : 1, child: unitText),
          ],
        ]);
      }
      final arrowStyle = TextStyle(color: ink, fontSize: activeSize * arrowScale / 100, height: 1, fontWeight: textWeight);
      final arrowText = sending ? '↑' : '↓';
      final arrowWidth = textExtent(arrowText, arrowStyle).clamp(1.0, double.infinity);
      return Padding(padding: EdgeInsets.only(left: sending ? directionGap : 0), child: Container(
        padding: EdgeInsets.symmetric(horizontal: design == 'split' ? 3 : 0),
        decoration: design == 'split' ? BoxDecoration(color: const Color(0x14ffffff), border: Border.all(color: const Color(0x78ffffff), width: 0.65), borderRadius: BorderRadius.circular(3)) : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (arrows) ...[
            Align(alignment: Alignment.centerLeft, widthFactor: arrowGap < 0 ? (1 + arrowGap / arrowWidth).clamp(0.1, 1.0) : 1, child: Text(arrowText, style: arrowStyle)),
            if (arrowGap >= 0) SizedBox(width: arrowGap),
          ],
          SizedBox(width: rateWidth + (stacked ? 0 : 28), height: indicatorHeight, child: FittedBox(fit: BoxFit.scaleDown, child: contents)),
        ]),
      ));
    }

    final indicator = GestureDetector(
      key: _meterKey,
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.onPositionChanged == null ? null : (_) {
        final track = _trackKey.currentContext!.findRenderObject()! as RenderBox;
        final meter = _meterKey.currentContext!.findRenderObject()! as RenderBox;
        _travel = (track.size.width - meter.size.width).clamp(1.0, double.infinity);
        _dragLeft = track.globalToLocal(meter.localToGlobal(Offset.zero)).dx;
      },
      onHorizontalDragUpdate: widget.onPositionChanged == null ? null : (details) {
        _dragLeft = (_dragLeft + details.delta.dx).clamp(0.0, _travel);
        widget.onPositionChanged!((_dragLeft / _travel * 1000).round());
      },
      child: SizedBox(height: 44, child: Center(widthFactor: 1,
        child: Transform.translate(offset: Offset(0, verticalOffset), child: Container(
          height: indicatorHeight,
          padding: EdgeInsets.symmetric(horizontal: const ['plain', 'mono', 'split'].contains(design) ? iconGap : iconGap.clamp(3, 12)),
          decoration: BoxDecoration(
            color: switch (design) { 'pill' => const Color(0x22ffffff), 'badge' => Colors.white, 'box' => const Color(0x14ffffff), _ => null },
            gradient: design == 'glass' ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0x28ffffff), Color(0x08000000), Color(0x38ffffff)]) : null,
            borderRadius: BorderRadius.circular(design == 'box' ? 3 : indicatorHeight / 2),
            border: const ['outline', 'box', 'glass'].contains(design) ? Border.all(color: design == 'glass' ? const Color(0x40ffffff) : const Color(0x78ffffff), width: 0.65) : null,
          ),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240),
            child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [rate(false), if (upload) rate(true)]))),
        )),
      )),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xff171a20), borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: MediaQuery.withNoTextScaling(
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                child: SizedBox(
                  key: _trackKey,
                  height: 44,
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    const Align(alignment: Alignment.centerLeft, child: Text('9:41', style: TextStyle(fontWeight: FontWeight.w600))),
                    const Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi, size: 17, color: Colors.white), SizedBox(width: 5),
                      Icon(Icons.battery_5_bar, size: 17, color: Colors.white),
                    ])),
                    Positioned.fill(child: Padding(
                      padding: horizontal < 0 ? const EdgeInsets.only(left: 42, right: 44) : EdgeInsets.zero,
                      child: Align(
                        alignment: Alignment(horizontal < 0 ? (right ? 1 : -1) : horizontal.clamp(0, 1000) / 500 - 1, 0),
                        child: indicator,
                      ),
                    )),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text('Drag to set a preferred position. The phone adjusts around status icons and the camera cutout.',
          style: Theme.of(context).textTheme.labelSmall),
        if (horizontal >= 0) TextButton(onPressed: widget.onPositionChanged == null ? null : () => widget.onPositionChanged!(-1),
          child: const Text('Reset position')),
      ],
    );
  }
}
