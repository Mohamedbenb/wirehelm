import '../models/remote_command.dart';
import 'windows_status_scripts.dart';

const windowsDefaultCommands = [
  RemoteCommand(
    id: 'windows_display_mode',
    templateId: 'windows_display_mode',
    name: 'Display mode',
    category: 'Display',
    icon: 'display',
    stateful: StatefulCommandConfig(
      statusCommand: windowsDisplayStatus,
      statusExecutionMode: 'interactive',
      states: [
        StatefulCommandState(
          id: 'extend',
          label: 'Extend',
          command: 'DisplaySwitch.exe /extend',
          expectedStatus: 'extend',
          executionMode: 'interactive',
        ),
        StatefulCommandState(
          id: 'external',
          label: 'External',
          command: 'DisplaySwitch.exe /external',
          expectedStatus: 'external',
          executionMode: 'interactive',
        ),
        StatefulCommandState(
          id: 'internal',
          label: 'Internal',
          command: 'DisplaySwitch.exe /internal',
          expectedStatus: 'internal',
          executionMode: 'interactive',
        ),
        StatefulCommandState(
          id: 'duplicate',
          label: 'Duplicate',
          command: 'DisplaySwitch.exe /clone',
          expectedStatus: 'duplicate',
          executionMode: 'interactive',
        ),
      ],
    ),
  ),
  RemoteCommand(
    id: 'windows_screen_power',
    templateId: 'windows_screen_power',
    name: 'Screen',
    category: 'Display',
    icon: 'monitor',
    stateful: StatefulCommandConfig(
      statusCommand: windowsScreenStatus,
      statusExecutionMode: 'interactive',
      states: [
        StatefulCommandState(
          id: 'awake',
          label: 'Awake',
          command: windowsScreenWake,
          expectedStatus: 'awake',
          executionMode: 'interactive',
        ),
        StatefulCommandState(
          id: 'sleeping',
          label: 'Sleeping',
          command: windowsScreenSleep,
          expectedStatus: 'sleeping',
          executionMode: 'interactive',
        ),
      ],
    ),
  ),
  RemoteCommand(
    id: 'windows_network_adapter',
    templateId: 'windows_network_adapter',
    name: 'Network adapter',
    category: 'Network',
    icon: 'terminal',
    requiresConfirmation: true,
    stateful: StatefulCommandConfig(
      target: StatefulCommandTarget(
        key: 'adapter',
        label: 'Adapter',
        value: 'Ethernet',
      ),
      statusCommand: 'powershell.exe -NoProfile -NonInteractive -Command "\$a=Get-NetAdapter -Name \'{{target:adapter}}\' -ErrorAction Stop; if(\$a.AdminStatus -eq \'Up\'){\'enabled\'}elseif(\$a.AdminStatus -eq \'Down\'){\'disabled\'}else{\'unknown\'}"',
      states: [
        StatefulCommandState(
          id: 'enabled',
          label: 'Enabled',
          command: 'powershell.exe -NoProfile -NonInteractive -Command "Enable-NetAdapter -Name \'{{target:adapter}}\' -Confirm:\$false -ErrorAction Stop"',
          expectedStatus: 'enabled',
        ),
        StatefulCommandState(
          id: 'disabled',
          label: 'Disabled',
          command: 'powershell.exe -NoProfile -NonInteractive -Command "Disable-NetAdapter -Name \'{{target:adapter}}\' -Confirm:\$false -ErrorAction Stop"',
          expectedStatus: 'disabled',
        ),
      ],
    ),
  ),
  RemoteCommand(
    id: 'windows_lock',

    templateId: 'windows_lock',

    name: 'Lock',

    category: 'Power',

    icon: 'lock',

    executionMode: 'interactive',

    command: 'rundll32.exe user32.dll,LockWorkStation',
  ),

  RemoteCommand(
    id: 'windows_restart',

    templateId: 'windows_restart',

    name: 'Restart',

    category: 'Power',

    icon: 'restart',

    command: 'shutdown /r /t 0',

    requiresConfirmation: true,
  ),
  RemoteCommand(
    id: 'windows_sleep',
    templateId: 'windows_sleep',
    name: 'Sleep',
    category: 'Power',
    icon: 'power',
    executionMode: 'interactive',
    requiresConfirmation: true,
    command: r"Add-Type -AssemblyName System.Windows.Forms; if (-not [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false)) { throw 'Windows rejected the sleep request.' }",
  ),

  RemoteCommand(
    id: 'windows_shutdown',

    templateId: 'windows_shutdown',

    name: 'Shutdown',

    category: 'Power',

    icon: 'power',

    command: 'shutdown /s /t 0',

    requiresConfirmation: true,
  ),

  RemoteCommand(
    id: 'windows_whoami',

    templateId: 'windows_whoami',

    name: 'Who am I?',

    category: 'System',

    icon: 'terminal',

    command: 'whoami',

    verificationCommand: 'whoami',
  ),

  RemoteCommand(
    id: 'windows_hostname',

    templateId: 'windows_hostname',

    name: 'Hostname',

    category: 'System',

    icon: 'terminal',

    command: 'hostname',
  ),
];

const linuxDefaultCommands = [
  RemoteCommand(
    id: 'linux_disk_space',
    templateId: 'linux_disk_space',
    name: 'Disk space',
    category: 'System',
    icon: 'terminal',
    command: 'df -h',
  ),
  RemoteCommand(
    id: 'linux_memory',
    templateId: 'linux_memory',
    name: 'Memory',
    category: 'System',
    icon: 'terminal',
    command: 'free -h',
  ),
  RemoteCommand(
    id: 'linux_network_addresses',
    templateId: 'linux_network_addresses',
    name: 'Network addresses',
    category: 'Network',
    icon: 'terminal',
    command: 'ip -brief address',
  ),
  RemoteCommand(
    id: 'linux_suspend',
    templateId: 'linux_suspend',
    name: 'Suspend',
    category: 'Power',
    icon: 'power',
    command: 'systemctl suspend',
    requiresConfirmation: true,
    requiresSudo: true,
  ),
  RemoteCommand(
    id: 'linux_whoami',

    templateId: 'linux_whoami',

    name: 'Who am I?',

    category: 'System',

    icon: 'terminal',

    command: 'whoami',

    verificationCommand: 'whoami',
  ),

  RemoteCommand(
    id: 'linux_hostname',

    templateId: 'linux_hostname',

    name: 'Hostname',

    category: 'System',

    icon: 'terminal',

    command: 'hostname',
  ),

  RemoteCommand(
    id: 'linux_uptime',

    templateId: 'linux_uptime',

    name: 'Uptime',

    category: 'System',

    icon: 'terminal',

    command: 'uptime',
  ),

  RemoteCommand(
    id: 'linux_wake_pc',

    templateId: 'linux_wake_pc',

    name: 'Wake PC',

    category: 'Power',

    icon: 'power',

    command: "command -v wakeonlan >/dev/null 2>&1 || { printf '%s\\n' 'Install wakeonlan on this Linux device first.' >&2; exit 1; }; wakeonlan -i {{param:broadcast}} {{param:mac}}",

    parameters: [
      CommandParameter(
        key: 'mac',

        label: 'MAC address',

        type: 'text',

        required: true,

        description: 'MAC address of the PC network adapter.',
      ),

      CommandParameter(
        key: 'broadcast',

        label: 'Broadcast address',

        type: 'text',

        required: true,

        defaultValue: '192.168.1.255',

        description: 'Broadcast address of the local network.',
      ),
    ],
  ),

  RemoteCommand(
    id: 'linux_ping',

    templateId: 'linux_ping',

    name: 'Ping',

    category: 'Network',

    icon: 'terminal',

    command: 'ping -c {{param:count}} -W 2 -- {{param:host}}',

    parameters: [
      CommandParameter(
        key: 'host',

        label: 'Host',

        type: 'text',

        required: true,

        defaultValue: '127.0.0.1',
      ),

      CommandParameter(
        key: 'count',

        label: 'Packet count',

        type: 'integer',

        defaultValue: '4',

        required: true,
        description: 'Always stop after this number of packets.',
      ),
    ],
  ),

  RemoteCommand(
    id: 'linux_restart',

    templateId: 'linux_restart',

    name: 'Restart',

    category: 'Power',

    icon: 'restart',

    command: 'systemctl reboot',

    requiresConfirmation: true,

    requiresSudo: true,
  ),

  RemoteCommand(
    id: 'linux_shutdown',

    templateId: 'linux_shutdown',

    name: 'Shutdown',

    category: 'Power',

    icon: 'power',

    command: 'systemctl poweroff',

    requiresConfirmation: true,

    requiresSudo: true,
  ),
];

const autoDefaultCommands = [
  RemoteCommand(
    id: 'auto_whoami',

    templateId: 'auto_whoami',

    name: 'Who am I?',

    category: 'System',

    icon: 'terminal',

    command: 'whoami',

    verificationCommand: 'whoami',
  ),

  RemoteCommand(
    id: 'auto_hostname',

    templateId: 'auto_hostname',

    name: 'Hostname',

    category: 'System',

    icon: 'terminal',

    command: 'hostname',
  ),
];

List<RemoteCommand> defaultCommandsFor(String shellStyle) {
  switch (shellStyle) {
    case 'windows':
      return windowsDefaultCommands;

    case 'linux':
      return linuxDefaultCommands;

    default:
      return autoDefaultCommands;
  }
}

List<RemoteCommand> get allDefaultCommands => [
  ...windowsDefaultCommands,
  ...linuxDefaultCommands,
  ...autoDefaultCommands,
];

RemoteCommand commandFromTemplate(RemoteCommand template) {
  return RemoteCommand(
    id: DateTime.now().microsecondsSinceEpoch.toString(),

    templateId: template.templateId ?? template.id,

    name: template.name,

    category: template.category,

    command: template.command,

    icon: template.icon,

    executionMode: template.executionMode,

    requiresConfirmation: template.requiresConfirmation,

    requiresSudo: template.requiresSudo,

    verificationCommand: template.verificationCommand,

    expectedOutput: template.expectedOutput,

    parameters: template.parameters,
    stateful: template.stateful,
  );
}
