import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../customization/local_customization.dart';

class BatteryUsageScreen extends StatefulWidget {
  const BatteryUsageScreen({super.key});
  @override
  State<BatteryUsageScreen> createState() => _BatteryUsageScreenState();
}

class _BatteryUsageScreenState extends State<BatteryUsageScreen> {
  Map<String, dynamic> data = {};
  bool busy = false;
  String? error;
  int? selected;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool? enabled, bool? estimates}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final changed = enabled != null || estimates != null;
      var result = await LocalCustomization.call(
        changed ? 'batteryUsageConfigure' : 'batteryUsage',
        {
          'session': selected ?? 0,
          if (changed) 'enabled': enabled ?? data['enabled'] == true,
          if (changed) 'estimates': estimates ?? data['estimates'] == true,
        },
      );
      if (changed && result['enabled'] == true) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        result = await LocalCustomization.call('batteryUsage', {
          'session': selected ?? 0,
        });
      }
      if (mounted) {
        setState(() {
          data = result;
          selected = (result['selected'] as num?)?.toInt();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Map<String, dynamic>> get sessions => (data['sessions'] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  String time(dynamic ms) {
    final minutes = ((ms as num? ?? 0) / 60000).floor();
    return minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';
  }

  String amount(dynamic v, {int digits = 1}) =>
      v is num ? v.toStringAsFixed(digits) : '—';
  String date(dynamic ms) {
    final d = DateTime.fromMillisecondsSinceEpoch((ms as num? ?? 0).toInt());
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatShortDate(d)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }

  Widget row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(value),
      ],
    ),
  );
  Widget card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final all = sessions;
    final matching = all.where((s) => s['id'] == selected);
    final s = matching.isEmpty ? null : matching.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery usage'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('Track battery sessions'),
            subtitle: const Text(
              'Starts on unplug. Pauses on external power. History stays on this phone.',
            ),
            value: data['enabled'] == true,
            onChanged: busy ? null : (v) => load(enabled: v),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'A quiet notification keeps the small native tracker available. It does not keep the screen or CPU awake. Wirehelm’s main app can still close after 30 seconds.',
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: const Text('Include Android estimates'),
            subtitle: Text(
              data['rootApproved'] == true
                  ? 'Read estimated Wirehelm and SystemUI energy with root.'
                  : 'Optional root access is needed for these estimates. Battery-loss tracking still works.',
            ),
            value: data['estimates'] == true,
            onChanged: busy || data['rootApproved'] != true
                ? null
                : (v) => load(estimates: v),
          ),
          if ('${data['trackerError'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${data['trackerError']}'),
            ),
          if (data['enabled'] == true && data['running'] != true)
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton(
                onPressed: busy ? null : () => load(enabled: true),
                child: const Text('Resume tracker'),
              ),
            ),
          if (all.isEmpty)
            card('Ready for a discharge session', [
              const Text(
                'Enable tracking. If the phone is already unplugged, the first session starts now and is marked partial. Future sessions begin when you unplug.',
              ),
            ]),
          if (all.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: DropdownButtonFormField<int>(
                key: ValueKey(selected),
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Discharge session',
                ),
                isExpanded: true,
                items: all
                    .map(
                      (v) => DropdownMenuItem<int>(
                        value: (v['id'] as num).toInt(),
                        child: Text(
                          '${date(v['start'])}${v['active'] == true ? ' · live' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) {
                        selected = v;
                        load();
                      },
              ),
            ),
            if (s != null) ...[
              card(
                s['active'] == true ? 'Current discharge' : 'Discharge summary',
                [
                  Text(
                    '${s['startLevel']}% → ${s['lastLevel']}% · ${s['endReason'] ?? ''}',
                  ),
                  row('On battery', time(s['durationMs'])),
                  row('Battery drop', '${s['lostPercent']} percentage points'),
                  row('Charge used', '${amount(s['lostMah'])} mAh'),
                  row('Average drain', '${amount(s['mahPerHour'])} mAh/h'),
                  row('Screen on', time(s['screenOnMs'])),
                  row('Screen off', time(s['screenOffMs'])),
                  row('Screen-on drain', '${amount(s['screenOnRate'])} mAh/h'),
                  row(
                    'Screen-off drain',
                    '${amount(s['screenOffRate'])} mAh/h',
                  ),
                  if (s['partial'] == true)
                    const Text(
                      'Partial session: tracking started after unplugging.',
                    ),
                  if (s['interrupted'] == true)
                    const Text(
                      'Monitoring was interrupted. The unknown gap is excluded.',
                    ),
                  if (s['counterAdjusted'] == true)
                    const Text(
                      'The battery gauge adjusted during this session; treat charge-based figures as approximate.',
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 130,
                    child: CustomPaint(
                      painter: _BatteryPlot(
                        List<Map<String, dynamic>>.from(
                          (data['samples'] as List? ?? []).map(
                            (v) => Map<String, dynamic>.from(v as Map),
                          ),
                        ),
                        Theme.of(context).colorScheme.primary,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const Text('Battery level over this session'),
                ],
              ),
              card('Customization activity', [
                const Text(
                  'Time in reported states, not a per-feature energy bill. Shared SystemUI work cannot be assigned accurately to individual customizations.',
                ),
                const SizedBox(height: 8),
                for (final label in [
                  'Network indicator',
                  'Edge panel',
                  'Edge handle',
                  'Notification ring',
                  'Shake Undo',
                ])
                  row(label, time((s['features'] as Map? ?? {})[label])),
                if ((s['unknownActivityMs'] as num? ?? 0) > 1000)
                  Text(
                    'Activity reporting unavailable for ${time(s['unknownActivityMs'])}.',
                  ),
                const Text(
                  'States follow the latest SystemUI report between updates. Edge-handle time indicates enabled screen-on time.',
                ),
              ]),
              card('Connection and service activity', [
                for (final label in [
                  'Remote ADB',
                  'SSH keep-alive',
                  'Button monitor',
                ])
                  row(label, time((s['features'] as Map? ?? {})[label])),
                const Text(
                  'Active connections can dominate battery usage. Keep them comparable when evaluating customization changes.',
                ),
              ]),
              card('Android energy estimates', [
                row(
                  'Wirehelm — whole app',
                  '${amount(s['wirehelmMah'], digits: 2)} mAh',
                ),
                row(
                  'SystemUI — including stock UI',
                  '${amount(s['systemuiMah'], digits: 2)} mAh',
                ),
                const Text(
                  'Wirehelm includes this tracker, connections and transfers. SystemUI includes Android’s own work. Display, GPU and root work may be attributed elsewhere.',
                ),
                if (s['energyReset'] == true)
                  const Text(
                    'Android reset its accounting window. Session energy differences are unavailable.',
                  ),
                if ('${s['energyError'] ?? ''}'.isNotEmpty)
                  Text('${s['energyError']}'),
                if ((s['energyAt'] as num? ?? 0) > 0)
                  Text('Estimate checkpoint: ${date(s['energyAt'])}'),
                if (s['wirehelmMah'] == null)
                  const Text(
                    'A complete estimate needs a successful baseline at session start. Enabling estimates midway applies fully to the next session.',
                  ),
              ]),
              card('Configuration during this session', [
                for (final e in Map<String, dynamic>.from(
                  s['configuration'] as Map? ?? {},
                ).entries)
                  row(e.key, '${e.value}'),
                Text(
                  '${s['configChanges'] ?? 0} configuration changes recorded',
                ),
                for (final v in (s['configurations'] as List? ?? []).skip(1))
                  Text('Changed ${date((v as Map)['at'])}'),
              ]),
              TextButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(s),
                  ),
                ),
                icon: const Icon(Icons.copy),
                label: const Text('Copy session report'),
              ),
            ],
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Last 60 sessions kept. Compare similar screen use, signal, brightness and configuration. This tracker does not reset Android’s battery statistics.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BatteryPlot extends CustomPainter {
  _BatteryPlot(this.points, this.color);
  final List<Map<String, dynamic>> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = color.withValues(alpha: .15)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    if (points.length < 2) return;
    final first = (points.first['elapsed'] as num).toDouble();
    final span = math.max(
      1.0,
      (points.last['elapsed'] as num).toDouble() - first,
    );
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x =
          ((points[i]['elapsed'] as num).toDouble() - first) /
          span *
          size.width;
      final y =
          (1 - (points[i]['level'] as num).toDouble().clamp(0, 100) / 100) *
          size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _BatteryPlot old) =>
      old.points != points || old.color != color;
}
