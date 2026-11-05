class CommandParameter {
  final String key;
  final String label;

  // text | integer | boolean | choice
  final String type;

  final bool required;
  final String? defaultValue;

  // Used by normal choice parameters.
  final List<String> options;

  //
  // Used by boolean / flag parameters.
  //
  // Example:
  //
  // trueValue: '-c'
  //
  // If takesValue == false:
  //
  // OFF -> ''
  // ON  -> '-c'
  //
  // If takesValue == true:
  //
  // OFF -> ''
  // ON  -> '-c 4'
  //
  final String? trueValue;

  final bool takesValue;

  // text | integer | choice
  final String flagValueType;

  final String? flagValueLabel;
  final String? flagValueDefault;
  final List<String> flagValueOptions;

  final String? description;

  const CommandParameter({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.defaultValue,
    this.options = const [],
    this.trueValue,
    this.takesValue = false,
    this.flagValueType = 'text',
    this.flagValueLabel,
    this.flagValueDefault,
    this.flagValueOptions = const [],
    this.description,
  });

  CommandParameter copyWith({
    String? key,
    String? label,
    String? type,
    bool? required,
    String? defaultValue,
    List<String>? options,
    String? trueValue,
    bool? takesValue,
    String? flagValueType,
    String? flagValueLabel,
    String? flagValueDefault,
    List<String>? flagValueOptions,
    String? description,
  }) {
    return CommandParameter(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      required: required ?? this.required,
      defaultValue: defaultValue ?? this.defaultValue,
      options: options ?? this.options,
      trueValue: trueValue ?? this.trueValue,
      takesValue: takesValue ?? this.takesValue,
      flagValueType: flagValueType ?? this.flagValueType,
      flagValueLabel: flagValueLabel ?? this.flagValueLabel,
      flagValueDefault: flagValueDefault ?? this.flagValueDefault,
      flagValueOptions: flagValueOptions ?? this.flagValueOptions,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'type': type,
      'required': required,
      'defaultValue': defaultValue,
      'options': options,
      'trueValue': trueValue,
      'takesValue': takesValue,
      'flagValueType': flagValueType,
      'flagValueLabel': flagValueLabel,
      'flagValueDefault': flagValueDefault,
      'flagValueOptions': flagValueOptions,
      'description': description,
    };
  }

  factory CommandParameter.fromJson(Map<String, dynamic> json) {
    return CommandParameter(
      key: json['key'] as String,
      label: json['label'] as String,
      type: json['type'] as String? ?? 'text',
      required: json['required'] as bool? ?? false,
      defaultValue: json['defaultValue'] as String?,
      options:
          (json['options'] as List?)?.map((item) => item.toString()).toList() ??
          const [],
      trueValue: json['trueValue'] as String?,

      //
      // Backward compatibility:
      // old saved boolean parameters do
      // not have these valued-flag fields.
      //
      takesValue: json['takesValue'] as bool? ?? false,
      flagValueType: json['flagValueType'] as String? ?? 'text',
      flagValueLabel: json['flagValueLabel'] as String?,
      flagValueDefault: json['flagValueDefault'] as String?,
      flagValueOptions:
          (json['flagValueOptions'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      description: json['description'] as String?,
    );
  }
}

//
// Optional object/target owned by a
// stateful command.
//
// Examples:
//
// Network Adapter
//   key:   adapter
//   label: Adapter
//   value: Ethernet
//
// Service
//   key:   service
//   label: Service
//   value: sshd
//
// A fixed stateful command such as
// Display Mode simply has no target.
//
class StatefulCommandTarget {
  final String key;
  final String label;
  final String value;

  const StatefulCommandTarget({
    required this.key,
    required this.label,
    this.value = '',
  });

  StatefulCommandTarget copyWith({String? key, String? label, String? value}) {
    return StatefulCommandTarget(
      key: key ?? this.key,
      label: label ?? this.label,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() {
    return {'key': key, 'label': label, 'value': value};
  }

  factory StatefulCommandTarget.fromJson(Map<String, dynamic> json) {
    return StatefulCommandTarget(
      key: json['key'] as String? ?? 'target',
      label: json['label'] as String? ?? 'Target',
      value: json['value'] as String? ?? '',
    );
  }
}

//
// One selectable state of a stateful command.
//
// Each state owns its execution mode because
// different state commands may need different
// execution environments.
//
// Examples:
//
// Adapter:
//   command: Enable-NetAdapter ...
//   executionMode: standard
//
// Display:
//   command: DisplaySwitch.exe /extend
//   executionMode: interactive
//
class StatefulCommandState {
  final String id;
  final String label;
  final String command;
  final String expectedStatus;

  // standard | interactive
  final String executionMode;

  const StatefulCommandState({
    required this.id,
    required this.label,
    required this.command,
    required this.expectedStatus,
    this.executionMode = 'standard',
  });

  StatefulCommandState copyWith({
    String? id,
    String? label,
    String? command,
    String? expectedStatus,
    String? executionMode,
  }) {
    return StatefulCommandState(
      id: id ?? this.id,
      label: label ?? this.label,
      command: command ?? this.command,
      expectedStatus: expectedStatus ?? this.expectedStatus,
      executionMode: executionMode ?? this.executionMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'command': command,
      'expectedStatus': expectedStatus,
      'executionMode': executionMode,
    };
  }

  factory StatefulCommandState.fromJson(
    Map<String, dynamic> json, {
    String legacyExecutionMode = 'standard',
  }) {
    return StatefulCommandState(
      id: json['id'] as String,
      label: json['label'] as String,
      command: json['command'] as String,
      expectedStatus: json['expectedStatus'] as String? ?? json['id'] as String,

      //
      // Backward compatibility:
      //
      // Existing stateful controls used the
      // parent RemoteCommand.executionMode.
      //
      // Preserve that behaviour when loading
      // an old state without its own mode.
      //
      executionMode: json['executionMode'] as String? ?? legacyExecutionMode,
    );
  }
}

//
// Configuration that turns a RemoteCommand
// into a stateful / switch command.
//
// statusCommand is intentionally optional.
//
// If statusCommand == null:
//
// - switch commands remain usable
// - no current state is claimed
//
// If statusCommand exists and succeeds:
//
// - result maps to one of states.expectedStatus
// - current state can be displayed
// - switches remain usable
//
// If statusCommand exists but cannot be
// evaluated or does not map to a state:
//
// - status is unavailable
// - switch section should be disabled
//
// target is also optional.
//
// Fixed controls such as Display Mode do not
// need one.
//
// The status command has its own execution
// mode independent of all state commands.
//
class StatefulCommandConfig {
  final StatefulCommandTarget? target;

  final String? statusCommand;

  // standard | interactive
  final String statusExecutionMode;

  final List<StatefulCommandState> states;

  const StatefulCommandConfig({
    this.target,
    this.statusCommand,
    this.statusExecutionMode = 'standard',
    this.states = const [],
  });

  bool get hasStatusCommand {
    return statusCommand != null && statusCommand!.trim().isNotEmpty;
  }

  bool get hasTarget {
    return target != null;
  }

  StatefulCommandConfig copyWith({
    StatefulCommandTarget? target,
    String? statusCommand,
    String? statusExecutionMode,
    List<StatefulCommandState>? states,
  }) {
    return StatefulCommandConfig(
      target: target ?? this.target,
      statusCommand: statusCommand ?? this.statusCommand,
      statusExecutionMode: statusExecutionMode ?? this.statusExecutionMode,
      states: states ?? this.states,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'target': target?.toJson(),
      'statusCommand': statusCommand,
      'statusExecutionMode': statusExecutionMode,
      'states': states.map((state) => state.toJson()).toList(),
    };
  }

  factory StatefulCommandConfig.fromJson(
    Map<String, dynamic> json, {
    String legacyStateExecutionMode = 'standard',
  }) {
    final targetJson = json['target'];

    return StatefulCommandConfig(
      target: targetJson is Map
          ? StatefulCommandTarget.fromJson(
              Map<String, dynamic>.from(targetJson),
            )
          : null,

      statusCommand: json['statusCommand'] as String?,

      //
      // Old controls had no separate status
      // execution mode.
      //
      // Standard SSH is the safest migration:
      // a status probe normally reads state
      // rather than manipulating the desktop.
      //
      statusExecutionMode: json['statusExecutionMode'] as String? ?? 'standard',

      states:
          (json['states'] as List?)
              ?.map(
                (item) => StatefulCommandState.fromJson(
                  Map<String, dynamic>.from(item as Map),
                  legacyExecutionMode: legacyStateExecutionMode,
                ),
              )
              .toList() ??
          const [],
    );
  }
}

class RemoteCommand {
  final String id;

  final String? templateId;

  final String name;

  //
  // Normal action command.
  //
  // Stateful-only controls do not require
  // this field to contain anything because
  // their executable commands live in
  // stateful.states.
  //
  final String command;

  final String category;
  final String icon;

  final bool requiresConfirmation;

  //
  // Linux command should be executed
  // through sudo -S.
  //
  final bool requiresSudo;

  //
  // standard | interactive
  //
  // For ordinary Action commands this is
  // still the command's execution mode.
  //
  // Stateful commands now use:
  //
  // stateful.statusExecutionMode
  // stateful.states[].executionMode
  //
  // This field remains for compatibility.
  //
  final String executionMode;

  final String? verificationCommand;
  final String? expectedOutput;

  final List<CommandParameter> parameters;

  //
  // Null:
  //   ordinary one-shot command.
  //
  // Non-null:
  //   stateful / switch command.
  //
  final StatefulCommandConfig? stateful;

  const RemoteCommand({
    required this.id,
    this.templateId,
    required this.name,
    this.command = '',
    required this.category,
    this.icon = 'terminal',
    this.requiresConfirmation = false,
    this.requiresSudo = false,
    this.executionMode = 'standard',
    this.verificationCommand,
    this.expectedOutput,
    this.parameters = const [],
    this.stateful,
  });

  bool get isStateful {
    return stateful != null;
  }

  bool get hasStateCheck {
    return stateful?.hasStatusCommand ?? false;
  }

  /// User-authored commands are confirmed by default because arbitrary shell
  /// text cannot be safely classified as read-only or destructive.
  bool get requiresUserConfirmation =>
      requiresConfirmation || templateId == null;

  RemoteCommand copyWith({
    String? id,
    String? templateId,
    String? name,
    String? command,
    String? category,
    String? icon,
    bool? requiresConfirmation,
    bool? requiresSudo,
    String? executionMode,
    String? verificationCommand,
    String? expectedOutput,
    List<CommandParameter>? parameters,
    StatefulCommandConfig? stateful,
  }) {
    return RemoteCommand(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      name: name ?? this.name,
      command: command ?? this.command,
      category: category ?? this.category,
      icon: icon ?? this.icon,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      requiresSudo: requiresSudo ?? this.requiresSudo,
      executionMode: executionMode ?? this.executionMode,
      verificationCommand: verificationCommand ?? this.verificationCommand,
      expectedOutput: expectedOutput ?? this.expectedOutput,
      parameters: parameters ?? this.parameters,
      stateful: stateful ?? this.stateful,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'name': name,
      'command': command,
      'category': category,
      'icon': icon,
      'requiresConfirmation': requiresConfirmation,
      'requiresSudo': requiresSudo,
      'executionMode': executionMode,
      'verificationCommand': verificationCommand,
      'expectedOutput': expectedOutput,
      'parameters': parameters.map((parameter) => parameter.toJson()).toList(),
      'stateful': stateful?.toJson(),
    };
  }

  factory RemoteCommand.fromJson(Map<String, dynamic> json) {
    final statefulJson = json['stateful'];

    //
    // Read the legacy/root execution mode
    // once because old Stateful commands used
    // this value for all of their states.
    //
    final executionMode = json['executionMode'] as String? ?? 'standard';

    return RemoteCommand(
      id: json['id'] as String,

      templateId: json['templateId'] as String?,

      name: json['name'] as String,

      //
      // Old saved commands always have this.
      //
      // Defaulting to an empty string also allows
      // future stateful-only commands.
      //
      command: json['command'] as String? ?? '',

      category: json['category'] as String,

      icon: json['icon'] as String? ?? 'terminal',

      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,

      //
      // Existing saved commands will
      // simply default to non-sudo.
      //
      requiresSudo: json['requiresSudo'] as bool? ?? false,

      executionMode: executionMode,

      verificationCommand: json['verificationCommand'] as String?,

      expectedOutput: json['expectedOutput'] as String?,

      parameters:
          (json['parameters'] as List?)
              ?.map(
                (item) => CommandParameter.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList() ??
          const [],

      //
      // Backward compatibility:
      //
      // Existing saved RemoteCommands have no
      // "stateful" property, so they deserialize
      // exactly as ordinary action commands.
      //
      // Existing Stateful commands that predate
      // the execution-mode split pass their old
      // root execution mode down to each state.
      //
      stateful: statefulJson is Map
          ? StatefulCommandConfig.fromJson(
              Map<String, dynamic>.from(statefulJson),
              legacyStateExecutionMode: executionMode,
            )
          : null,
    );
  }
}
