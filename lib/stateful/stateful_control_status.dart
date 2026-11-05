import '../models/remote_command.dart';

enum StatefulStatusPhase {
  unchecked,
  checking,
  available,
  unavailable,
}

class StatefulControlStatus {
  final StatefulStatusPhase phase;

  final String? stateId;

  final String? rawValue;

  final String? error;

  const StatefulControlStatus._({
    required this.phase,
    this.stateId,
    this.rawValue,
    this.error,
  });

  const StatefulControlStatus.unchecked()
      : this._(
          phase:
              StatefulStatusPhase.unchecked,
        );

  const StatefulControlStatus.checking()
      : this._(
          phase:
              StatefulStatusPhase.checking,
        );

  const StatefulControlStatus.available({
    required String stateId,
    required String rawValue,
  }) : this._(
          phase:
              StatefulStatusPhase.available,

          stateId:
              stateId,

          rawValue:
              rawValue,
        );

  const StatefulControlStatus.unavailable({
    String? rawValue,
    String? error,
    String? stateId,
  }) : this._(
          phase:
              StatefulStatusPhase.unavailable,
          stateId: stateId,

          rawValue:
              rawValue,

          error:
              error,
        );

  bool get isChecking =>
      phase ==
      StatefulStatusPhase.checking;

  bool get isAvailable =>
      phase ==
      StatefulStatusPhase.available;

  bool get isUnavailable =>
      phase ==
      StatefulStatusPhase.unavailable;

  bool get isUnchecked =>
      phase ==
      StatefulStatusPhase.unchecked;
}

StatefulControlStatus
    resolveStatefulStatus({
  required RemoteCommand command,
  required String rawOutput,
}) {
  final config =
      command.stateful;

  if (config == null) {
    return const StatefulControlStatus
        .unavailable(
      error:
          'Command is not stateful.',
    );
  }

  final normalized =
      rawOutput.trim();

  if (normalized.isEmpty) {
    return const StatefulControlStatus
        .unavailable(
      error:
          'Status command returned no value.',
    );
  }

  for (final state
      in config.states) {
    if (state.expectedStatus
            .trim()
            .toLowerCase() ==
        normalized.toLowerCase()) {
      return StatefulControlStatus
          .available(
        stateId:
            state.id,

        rawValue:
            normalized,
      );
    }
  }

  return StatefulControlStatus
      .unavailable(
    rawValue:
        normalized,

    error:
        'Status does not match any configured state.',
  );
}
