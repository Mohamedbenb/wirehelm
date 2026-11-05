import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../ssh/ssh_session.dart';
import '../utils/stateful_command_templates.dart';
import 'stateful_command_executor.dart';
import 'stateful_control_status.dart';
import '../ssh/windows_command_host.dart';

class _Request {
  final RemoteCommand command;
  final SshSession session;
  final String script;
  final Completer<StatefulControlStatus> result = Completer();
  _Request(this.command, this.session, this.script);
}

// One instance belongs to one device controller. Calls in the same refresh
// are coalesced, while manual refresh and switch verification still work alone.
class StatusBatcher {
  final List<_Request> _pending = [];
  Future<StatefulControlStatus> check({
    required BuildContext context,
    required RemoteCommand command,
    required SshSession session,
    bool allowPrompt = true,
  }) {
    final config = command.stateful;
    final text = normalizeWindowsTypes(
      renderStatefulCommand(
        command: command,
        template: config?.statusCommand ?? '',
      ),
    );
    final body = powerShellStatusBody(text);
    final compatible =
        config?.statusExecutionMode == 'interactive' || body != null;
    if (!compatible ||
        requiresFreshWindowsProcess(text) ||
        command.requiresSudo ||
        text.isEmpty ||
        statefulTargetPlaceholders(text).isNotEmpty) {
      return checkStatefulCommandStatus(
        context: context,
        command: command,
        session: session,
        allowPrompt: allowPrompt,
      );
    }
    final request = _Request(
      command,
      session,
      config?.statusExecutionMode == 'interactive' ? text : body!,
    );
    if (_pending.isEmpty) scheduleMicrotask(_flush);
    _pending.add(request);
    return request.result.future;
  }

  Future<void> _flush() async {
    final pending = List<_Request>.of(_pending);
    _pending.clear();
    final groups = <String, List<_Request>>{};
    for (final request in pending) {
      groups
          .putIfAbsent(request.command.stateful!.statusExecutionMode, () => [])
          .add(request);
    }
    // Desktop task startup must not hold up ordinary SSH probes.
    await Future.wait(
      groups.entries.map((group) => _execute(group.key, group.value)),
    );
  }

  Future<void> _execute(String mode, List<_Request> requests) async {
    try {
      final scripts = <String, List<String>>{};
      for (final request in requests) {
        scripts.putIfAbsent(request.script, () => []).add(request.command.id);
      }
      final script = buildStatusBatchScript(scripts);
      final session = requests.first.session;
      Uint8List bytes;
      if (mode == 'interactive') {
        bytes = await session.runCommand(
          script,
          executionMode: mode,
          timeout: const Duration(seconds: 20),
        );
      } else {
        bytes = await session.runPowerShell(
          script,
          label: 'Status: ${requests.map((r) => r.command.name).join(', ')}',
        );
      }
      final results = decodeStatusBatch(
        utf8.decode(bytes, allowMalformed: true),
      );
      for (final request in requests) {
        final row = results[request.command.id];
        request.result.complete(
          row == null
              ? const StatefulControlStatus.unavailable(
                  error: 'Status missing from batch.',
                )
              : row['error'] != null
              ? StatefulControlStatus.unavailable(error: row['error'] as String)
              : resolveStatefulStatus(
                  command: request.command,
                  rawOutput: row['value'] as String? ?? '',
                ),
        );
      }
    } catch (error) {
      for (final request in requests) {
        if (!request.result.isCompleted) {
          request.result.complete(
            StatefulControlStatus.unavailable(error: error.toString()),
          );
        }
      }
    }
  }
}

// CMD passes this quoted body literally, but PowerShell would expand $variables
// when nesting the original command inside a batch. Execute the body directly.
// Only unwrap the unambiguous form; other standard commands keep their normal path.
String? powerShellStatusBody(String text) => RegExp(
  r'^\s*powershell\.exe\s+(?:(?:-NoProfile|-NonInteractive|-NoLogo)\s+)*-Command\s+"([^"]*)"\s*$',
  caseSensitive: false,
).firstMatch(text)?.group(1);

String buildStatusBatchScript(Map<String, List<String>> scripts) {
  final result = StringBuffer(
    r"[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; $ProgressPreference='SilentlyContinue'; $results=@{}"
    '\n',
  );
  for (final entry in scripts.entries) {
    final encoded = base64Encode(utf8.encode(cacheWindowsTypes(entry.key)));
    result.writeln(
      r"try { $value=(& { $ErrorActionPreference='Stop'; & ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" +
          encoded +
          r"')))) } | Out-String).Trim(); $row=@{value=$value} } catch { $row=@{error=$_.Exception.Message} }",
    );
    for (final id in entry.value) {
      final key = base64Encode(utf8.encode(id));
      result.writeln(
        r"$results[[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" +
            key +
            r"'))]=$row",
      );
    }
  }
  result.writeln(
    r"Write-Output ('__RC_STATUS_JSON__' + (ConvertTo-Json -InputObject $results -Compress -Depth 5))",
  );
  return result.toString();
}

Map<String, dynamic> decodeStatusBatch(String output) {
  const marker = '__RC_STATUS_JSON__';
  final line = const LineSplitter()
      .convert(output)
      .lastWhere((line) => line.startsWith(marker));
  return jsonDecode(line.substring(marker.length)) as Map<String, dynamic>;
}
