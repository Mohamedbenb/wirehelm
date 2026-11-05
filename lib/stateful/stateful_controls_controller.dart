import 'dart:async';

import 'package:flutter/material.dart';

import '../models/remote_command.dart';
import '../ssh/ssh_session.dart';
import 'stateful_command_executor.dart';
import 'stateful_control_status.dart';
import 'status_batcher.dart';

typedef StatusChecker = Future<StatefulControlStatus> Function({
  required BuildContext context,
  required RemoteCommand command,
  required SshSession session,
  bool allowPrompt,
});

typedef StateRunner = Future<String?> Function({
  required BuildContext context,
  required RemoteCommand command,
  required StatefulCommandState state,
  required SshSession session,
});

class StatefulControlsController extends ChangeNotifier {
  static const refreshInterval = Duration(seconds: 20);
  Duration interval;
  final SshSession session;
  final DateTime Function() _now;
  final StatusChecker _check;
  final StateRunner _run;
  final Map<String, StatefulControlStatus> _statuses = {};
  final Set<String> _runningCommandIds = {};
  final Map<String, Future<StatefulControlStatus>> _checks = {};
  final Map<String, Future<StatefulControlStatus>> _executingChecks = {};
  final Map<String, Object> _versions = {};
  final Map<String, DateTime> _nextChecks = {};
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _checkedAt = {};
  DateTime? checkedAt(RemoteCommand command) => _checkedAt[command.id];
  Timer? _pollTimer;
  bool _disposed = false;
  bool _polling = false;
  BuildContext? _context;
  Iterable<RemoteCommand> Function()? _commands;
  bool Function()? _canPoll;

  StatefulControlsController({
    required this.session,
    StatusChecker? checkStatus,
    StateRunner? runCommand,
    DateTime Function()? now,
    this.interval = refreshInterval,
  }) : _check = checkStatus ?? StatusBatcher().check,
       _now = now ?? DateTime.now,
       _run = runCommand ?? runStatefulStateCommand;

  StatefulControlStatus statusFor(RemoteCommand command) =>
      _statuses[command.id] ?? const StatefulControlStatus.unchecked();

  bool isRunning(RemoteCommand command) =>
      _runningCommandIds.contains(command.id);
  bool isRefreshing(RemoteCommand command) => _checks.containsKey(command.id);
  bool get hasRunningCommands => _runningCommandIds.isNotEmpty;

  void setRefreshInterval(Duration value) {
    if (interval == value) return;
    interval = value;
    for (final id in _nextChecks.keys.toList()) {
      _nextChecks[id] = _now().add(value);
    }
  }

  void startPolling({
    required BuildContext context,
    required Iterable<RemoteCommand> Function() commands,
    required bool Function() canPoll,
  }) {
    _context = context;
    _commands = commands;
    _canPoll = canPoll;
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    final context = _context;
    if (_disposed ||
        _polling ||
        context == null ||
        !context.mounted ||
        !(_canPoll?.call() ?? false)) {
      return;
    }
    _polling = true;
    try {
      final reads = <Future<StatefulControlStatus>>[];
      for (final command in List<RemoteCommand>.of(_commands!())) {
        if (_disposed || !context.mounted || !(_canPoll?.call() ?? false)) {
          break;
        }
        if (!command.hasStateCheck ||
            isRunning(command) ||
            isRefreshing(command) ||
            _executingChecks.containsKey(command.id)) {
          continue;
        }
        final due = _nextChecks[command.id];
        if (due != null && _now().isBefore(due)) continue;
        reads.add(
          refreshCommand(
            context: context,
            command: command,
            allowPrompt: false,
          ),
        );
      }
      await Future.wait(reads);
    } finally {
      _polling = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void removeCommand(String commandId) {
    _checkedAt.remove(commandId);
    _versions[commandId] = Object();
    _statuses.remove(commandId);
    _nextChecks.remove(commandId);
    _failures.remove(commandId);
    _notify();
  }

  void clear() {
    _checkedAt.clear();
    for (final id in {..._versions.keys, ..._statuses.keys, ..._checks.keys}) {
      _versions[id] = Object();
    }
    _statuses.clear();
    _nextChecks.clear();
    _failures.clear();
    _notify();
  }

  void markDisconnected() {
    for (final id in {..._versions.keys, ..._statuses.keys, ..._checks.keys}) {
      _versions[id] = Object();
      final previous = _statuses[id];
      _statuses[id] = StatefulControlStatus.unavailable(
        stateId: previous?.stateId,
        rawValue: previous?.rawValue,
        error: 'Disconnected. Last known status may be stale.',
      );
    }
    _nextChecks.clear();
    _notify();
  }

  Future<StatefulControlStatus> refreshCommand({
    required BuildContext context,
    required RemoteCommand command,
    bool allowPrompt = true,
  }) {
    if (_disposed) return Future.value(statusFor(command));
    final pending = _checks[command.id];
    if (pending != null) return pending;
    // A timed-out read may still be finishing. Never start a second remote read.
    if (_executingChecks.containsKey(command.id)) {
      return Future.value(statusFor(command));
    }
    final version = _versions.putIfAbsent(command.id, Object.new);
    final previous = statusFor(command);
    if (previous.stateId == null) {
      _statuses[command.id] = const StatefulControlStatus.checking();
    }
    // Defer execution until the in-flight entry is installed.
    final future = Future<StatefulControlStatus>.microtask(() async {
      StatefulControlStatus result;
      try {
        if (!context.mounted) return previous;
        if (command.hasStateCheck) {
          final operation = _check(
            context: context,
            command: command,
            session: session,
            allowPrompt: allowPrompt,
          );
          _executingChecks[command.id] = operation;
          unawaited(
            operation
                .then<void>(
                  (_) {},
                  onError: (Object error, StackTrace stack) {},
                )
                .whenComplete(() {
                  if (identical(_executingChecks[command.id], operation)) {
                    _executingChecks.remove(command.id);
                  }
                }),
          );
          result = await operation.timeout(
            const Duration(seconds: 45),
            onTimeout: () => const StatefulControlStatus.unavailable(
              error: 'Status check timed out. Use Test status to inspect the command.',
            ),
          );
        } else {
          result = const StatefulControlStatus.unchecked();
        }
      } catch (error) {
        result = StatefulControlStatus.unavailable(error: error.toString());
      }
      if (_disposed || _versions[command.id] != version) return result;
      if (result.isUnavailable) {
        final failures = (_failures[command.id] ?? 0) + 1;
        _failures[command.id] = failures;
        final seconds = (interval.inSeconds * failures.clamp(1, 3)).clamp(
          5,
          900,
        );
        _nextChecks[command.id] = _now().add(Duration(seconds: seconds));
        // Retain the confirmed value only for failed reads, not unmatched output.
        if (result.rawValue == null && previous.stateId != null) {
          result = StatefulControlStatus.unavailable(
            stateId: previous.stateId,
            rawValue: previous.rawValue,
            error: result.error,
          );
        }
      } else {
        _failures.remove(command.id);
        _nextChecks[command.id] = _now().add(interval);
      }
      _statuses[command.id] = result;
      _checkedAt[command.id] = _now();
      return result;
    });
    _checks[command.id] = future;
    _notify();
    unawaited(
      future.whenComplete(() {
        if (identical(_checks[command.id], future)) _checks.remove(command.id);
        _notify();
      }),
    );
    return future;
  }

  Future<void> refreshCommands({
    required BuildContext context,
    required Iterable<RemoteCommand> commands,
    bool allowPrompt = false,
  }) async {
    final reads = <Future<StatefulControlStatus>>[];
    for (final command in List<RemoteCommand>.of(commands)) {
      if (_disposed || !context.mounted) return;
      if (!allowPrompt && _canPoll != null && !_canPoll!()) return;
      if (!command.isStateful || isRunning(command)) continue;
      reads.add(
        refreshCommand(
          context: context,
          command: command,
          allowPrompt: allowPrompt,
        ),
      );
    }
    await Future.wait(reads);
  }

  Future<StatefulStateRunResult> runState({
    required BuildContext context,
    required RemoteCommand command,
    required StatefulCommandState state,
  }) async {
    if (_disposed || isRunning(command)) {
      return const StatefulStateRunResult.busy();
    }
    if (!session.isConnected) {
      return const StatefulStateRunResult.failed(message: 'Disconnected.');
    }
    _runningCommandIds.add(command.id);
    _notify();
    try {
      // Drain a routine read before switching so it cannot overwrite newer status.
      final pending = _checks[command.id];
      if (pending != null) {
        await pending.timeout(const Duration(seconds: 5));
      }
      if (_executingChecks.containsKey(command.id)) {
        return const StatefulStateRunResult.failed(
          message:
              'The previous status read is still finishing. Try again shortly.',
        );
      }
      if (_disposed || !context.mounted || !session.isConnected) {
        return const StatefulStateRunResult.cancelled();
      }
      final version = _versions.putIfAbsent(command.id, Object.new);
      String? output;
      try {
        output = await _run(
          context: context,
          command: command,
          state: state,
          session: session,
        );
      } on TimeoutException {
        return const StatefulStateRunResult.failed(
          message: 'Command timed out. It may still have completed; check the device before retrying.',
        );
      }
      if (output == null) return const StatefulStateRunResult.cancelled();
      StatefulControlStatus? refreshed;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!_disposed &&
          context.mounted &&
          session.isConnected &&
          _versions[command.id] == version) {
        if (!context.mounted) break;
        if (_canPoll != null && !_canPoll!()) break;
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        refreshed = await refreshCommand(
          context: context,
          command: command,
          allowPrompt: false,
        ).timeout(remaining);
        if (!command.hasStateCheck ||
            refreshed.stateId == state.id && refreshed.isAvailable ||
            DateTime.now().isAfter(deadline)) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_canPoll != null && !_canPoll!()) break;
      }
      if (command.hasStateCheck &&
          refreshed != null &&
          (!refreshed.isAvailable || refreshed.stateId != state.id)) {
        return StatefulStateRunResult.failed(
          message: 'Command sent, but ${state.label} was not confirmed.',
        );
      }
      return StatefulStateRunResult.success(output: output, status: refreshed);
    } on TimeoutException {
      return const StatefulStateRunResult.failed(
        message:
            'Status check timed out. The requested state is not confirmed.',
      );
    } catch (error) {
      return StatefulStateRunResult.failed(message: error.toString());
    } finally {
      _runningCommandIds.remove(command.id);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}

enum StatefulStateRunOutcome { success, cancelled, busy, failed }

class StatefulStateRunResult {
  final StatefulStateRunOutcome outcome;

  final String? output;

  final String? message;

  final StatefulControlStatus? status;

  const StatefulStateRunResult._({
    required this.outcome,
    this.output,
    this.message,
    this.status,
  });

  const StatefulStateRunResult.success({
    String? output,
    StatefulControlStatus? status,
  }) : this._(
         outcome: StatefulStateRunOutcome.success,
         output: output,
         status: status,
       );

  const StatefulStateRunResult.cancelled()
    : this._(outcome: StatefulStateRunOutcome.cancelled);

  const StatefulStateRunResult.busy()
    : this._(outcome: StatefulStateRunOutcome.busy);

  const StatefulStateRunResult.failed({required String message})
    : this._(outcome: StatefulStateRunOutcome.failed, message: message);

  bool get succeeded => outcome == StatefulStateRunOutcome.success;
}
