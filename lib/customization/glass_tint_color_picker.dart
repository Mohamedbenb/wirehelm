import 'package:flutter/material.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
Future<String?> showGlassTintPicker(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (_) => _GlassTintPicker(initial: initial),
    );

class _GlassTintPicker extends StatefulWidget {
  const _GlassTintPicker({required this.initial});
  final String initial;
  @override
  State<_GlassTintPicker> createState() => _GlassTintPickerState();
}

class _GlassTintPickerState extends State<_GlassTintPicker> {
  final pad = GlobalKey();
  late HSVColor hsv;
  late TextEditingController hex;
  final colors = const [
    0xffffffff,
    0xff000000,
    0xffff5252,
    0xffffb300,
    0xff00c853,
    0xff00b8d4,
    0xff2962ff,
    0xffaa00ff,
  ];
  bool get valid => RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(hex.text);
  @override
  void initState() {
    super.initState();
    final s = widget.initial.replaceFirst('#', '');
    hsv = HSVColor.fromColor(
      Color(0xff000000 | (int.tryParse(s, radix: 16) ?? 0xffffff)),
    );
    hex = TextEditingController(text: _hex(hsv.toColor()));
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void update(HSVColor value) {
    setState(() {
      hsv = value;
      hex.text = _hex(value.toColor());
    });
  }

  void sv(Offset at, Size size) {
    update(
      hsv
          .withSaturation((at.dx / size.width).clamp(0, 1))
          .withValue((1 - at.dy / size.height).clamp(0, 1)),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose tint color'),
    scrollable: true,
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: Semantics(
              label: 'Tint saturation and brightness',
              child: GestureDetector(
                key: const ValueKey('tintSV'),
                onPanDown: (e) => sv(
                  e.localPosition,
                  (pad.currentContext!.findRenderObject() as RenderBox).size,
                ),
                onPanUpdate: (e) => sv(
                  e.localPosition,
                  (pad.currentContext!.findRenderObject() as RenderBox).size,
                ),
                child: CustomPaint(
                  key: pad,
                  painter: _SVPainter(hsv),
                  size: const Size(320, 228),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xffff0000),
                        Color(0xffffff00),
                        Color(0xff00ff00),
                        Color(0xff00ffff),
                        Color(0xff0000ff),
                        Color(0xffff00ff),
                        Color(0xffff0000),
                      ],
                    ),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                ),
                child: Slider(
                  key: const ValueKey('tintHue'),
                  label: 'Hue ${hsv.hue.round()}',
                  value: hsv.hue,
                  min: 0,
                  max: 360,
                  divisions: 360,
                  onChanged: (v) => update(hsv.withHue(v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('pickerHex'),
                  controller: hex,
                  decoration: InputDecoration(
                    labelText: 'Hex color',
                    hintText: '#RRGGBB',
                    errorText: valid ? null : 'Use six hexadecimal digits',
                  ),
                  onChanged: (v) {
                    setState(() {
                      if (valid)
                        hsv = HSVColor.fromColor(
                          Color(
                            0xff000000 |
                                int.parse(v.replaceFirst('#', ''), radix: 16),
                          ),
                        );
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((v) {
              return Semantics(
                label: 'Tint ${_hex(Color(v))}',
                button: true,
                child: InkWell(
                  key: ValueKey('swatch${_hex(Color(v))}'),
                  onTap: () => update(HSVColor.fromColor(Color(v))),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: valid
            ? () => Navigator.pop(context, _hex(hsv.toColor()))
            : null,
        child: const Text('Use color'),
      ),
    ],
  );
}

class _SVPainter extends CustomPainter {
  _SVPainter(this.color);
  final HSVColor color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    canvas.drawRect(
      rect,
      Paint()..color = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();
    final center = Offset(
      (color.saturation * size.width).clamp(7, size.width - 7),
      ((1 - color.value) * size.height).clamp(7, size.height - 7),
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black,
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SVPainter old) => old.color != color;
}
