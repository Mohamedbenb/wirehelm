import 'package:flutter/material.dart';

import '../customization/carrier_selection_dialog.dart';
import '../customization/local_customization.dart';
import '../customization/settings_controls.dart';

String carrierOverrideStatus(Map<String, dynamic> carrier) {
  if (carrier['active'] == true) return 'Active';
  if (carrier['rebootRequired'] == true) return 'Change waiting for reboot';
  if (carrier['installed'] != true) return 'Backend not installed';
  final state = carrier['moduleState'];
  return state == null || state == '' ? 'Installed' : 'Installed · $state';
}

class CarrierOverrideScreen extends StatelessWidget {
  const CarrierOverrideScreen({
    super.key,
    required this.carrier,
    required this.busy,
    required this.onOperation,
  });

  final Map<String, dynamic> carrier;
  final bool busy;
  final Future<void> Function(
    String operation, {
    Map<String, dynamic>? arguments,
  })
  onOperation;

  Future<void> _installCarrier(
    BuildContext context, {
    required bool update,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          update ? 'Update carrier backend?' : 'Install carrier backend?',
        ),
        content: Text(
          update
              ? 'This replaces the old bundled database with a firmware-local generator. Disabled overrides stay disabled. Reboot to finish the backend update, then enable it when ready.'
              : 'This installs a disabled KernelSU backend. After reboot, enable it to derive Tunisie Telecom and Orange mappings from the current vendor database. Unsupported database layouts stay stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(update ? 'Update' : 'Install'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await onOperation('installCarrier');
    }
  }

  Future<void> _chooseCarriers(BuildContext context) async {
    final current = '${carrier['selectedCarriers'] ?? '60502,60501'}'
        .split(',')
        .toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => CarrierSelectionDialog(
        selected: current,
        load: (query) =>
            LocalCustomization.call('carrierCatalog', {'query': query}),
      ),
    );
    if (!context.mounted ||
        result == null ||
        (result.length == current.length && result.containsAll(current))) {
      return;
    }
    await onOperation(
      'configureCarriers',
      arguments: {'carriers': (result.toList()..sort()).join(',')},
    );
  }

  Future<void> _setCarrierEnabled(BuildContext context, bool enabled) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          enabled ? 'Enable carrier override?' : 'Restore stock behavior?',
        ),
        content: Text(
          enabled
              ? 'At the next boot, the backend will copy the current vendor database, resolve its stock 5G profile and patch only the selected carrier mappings. Unsupported layouts stay stock. A stock backup is retained.'
              : 'KernelSU will stop exposing the cfgdb override after the next reboot. The stock vendor database itself has never been modified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(enabled ? 'Enable' : 'Restore stock'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await onOperation(enabled ? 'enableCarrier' : 'disableCarrier');
    }
  }

  String _carrierSims(Map<String, dynamic> carrier) {
    final sims =
        (carrier['activeSims'] as List?)?.whereType<Map>().toList() ?? const [];
    if (sims.isEmpty) return 'No supported SIM details';
    return sims.map((s) => '${s['name']} · ${s['mccmnc']}').join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return CustomizationCard('Carrier profile override', [
      Text(
        carrierOverrideStatus(carrier),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      CustomizationDetail(
        'Selected carriers',
        carrier['selectedCarriers'] ?? '60502,60501',
      ),
      if (carrier['installed'] == true && carrier['updateRequired'] != true)
        OutlinedButton.icon(
          onPressed: busy ? null : () => _chooseCarriers(context),
          icon: const Icon(Icons.search),
          label: const Text('Choose carriers'),
        ),
      CustomizationDetail('Mode', 'Firmware-local'),
      CustomizationDetail('SIMs', _carrierSims(carrier)),
      CustomizationDetail(
        'Current carrier ID',
        (carrier['currentCarrierId'] as num? ?? -1) > 0
            ? carrier['currentCarrierId']
            : 'Not reported',
      ),
      CustomizationDetail(
        'Intended profile',
        carrier['intendedProfile'] ?? '—',
      ),
      CustomizationDetail('Data network', carrier['dataNetworkName'] ?? '—'),
      if (carrier['nrAvailable'] != null)
        CustomizationDetail('NR available', carrier['nrAvailable']),
      if (carrier['endcAvailable'] != null)
        CustomizationDetail('EN-DC available', carrier['endcAvailable']),
      if (carrier['nrState'] != null)
        CustomizationDetail('NR state', carrier['nrState']),
      if (carrier['nrFrequencyRange'] != null)
        CustomizationDetail('NR frequency range', carrier['nrFrequencyRange']),
      CustomizationDetail(
        'Configuration',
        carrier['rebootRequired'] == true && carrier['sourceFound'] != 'true'
            ? 'Staged · generates from current firmware after reboot'
            : carrier['configurationValid'] == true
            ? 'Current vendor copy and selected mappings verified'
            : carrier['databaseCompatible'] == true &&
                  carrier['moduleState'] == 'disabled'
            ? 'Compatible vendor database · generates when enabled'
            : carrier['sourceFound'] == 'true'
            ? 'Unexpected database'
            : 'Not installed',
      ),
      CustomizationDetail(
        'Systemless override',
        carrier['mounted'] == true ? 'Mounted' : 'Not mounted',
      ),
      if (carrier['supportedCarrierDetected'] != true)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'No selected carrier is currently detected. You can configure carriers before inserting their SIMs.',
          ),
        ),
      if (carrier['rebootRequired'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Reboot required. Radio or airplane-mode cycling is not used because the modem may retain the previous database.',
          ),
        ),
      if (carrier['lastMount'] != null && '${carrier['lastMount']}'.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${carrier['lastMount']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (carrier['installed'] != true)
            FilledButton.icon(
              onPressed: busy || carrier['backendAvailable'] != true
                  ? null
                  : () => _installCarrier(context, update: false),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Install backend'),
            ),
          if (carrier['updateRequired'] == true)
            FilledButton.icon(
              onPressed: busy || carrier['backendAvailable'] != true
                  ? null
                  : () => _installCarrier(context, update: true),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Update backend'),
            ),
          if (carrier['installed'] == true &&
              carrier['updateRequired'] != true &&
              carrier['rebootRequired'] != true &&
              carrier['moduleState'] == 'disabled')
            FilledButton.icon(
              onPressed: busy || carrier['databaseCompatible'] != true
                  ? null
                  : () => _setCarrierEnabled(context, true),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Enable override'),
            ),
          if (carrier['installed'] == true &&
              carrier['rebootRequired'] != true &&
              carrier['moduleState'] == 'enabled')
            OutlinedButton.icon(
              onPressed: busy ? null : () => _setCarrierEnabled(context, false),
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restore stock'),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Carrier IDs and wildcard_5g are resolved from this firmware. A compatible cfgdb is required; this does not unlock every modem or guarantee network 5G availability.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ], icon: Icons.network_cell_outlined);
  }
}
