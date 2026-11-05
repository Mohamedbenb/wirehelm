Map<String, dynamic> healthSection(Map<String, dynamic> data, String key) =>
    Map<String, dynamic>.from((data[key] as Map?) ?? {});

class CustomizationCheck {
  final String title, detail;
  final bool attention;
  const CustomizationCheck(this.title, this.detail, {this.attention = false});
}

String indicatorStatus(Map<String, dynamic> data) {
  final config = healthSection(data, 'config');
  final hook = healthSection(data, 'hook');
  final metrics = healthSection(hook, 'metrics');
  if (config['emergencyDisabled'] == true) {
    return config['recoveryReason'] == 'Disabled by user'
        ? 'Off'
        : 'Stopped by recovery';
  }
  if (config['enabled'] != true) return 'Off';
  if (hook['fresh'] != true) return 'Waiting for SystemUI';
  if (data['hookUpdateRequired'] == true) return 'Hook update ready';
  if (hook['revision'] != config['revision']) return 'Applying settings';
  return switch (metrics['visibilityReason']) {
    'showing' => 'Showing in status bar',
    'idle' => 'Hidden while idle',
    'screenOff' => 'Screen off',
    'statusBarHidden' => 'Status bar hidden by Android',
    'statusBarCrowded' => 'Hidden until status-bar space is available',
    'detached' || 'waitingForStatusBar' => 'Reattaching to status bar',
    'safetyCheckOverdue' => 'Waiting for safety check',
    'quarantined' => 'Stopped by recovery',
    _ => hook['state'] == 'active' ? 'Active' : 'Waiting for confirmation',
  };
}

List<CustomizationCheck> customizationChecks(Map<String, dynamic> data) {
  final config = healthSection(data, 'config');
  final hook = healthSection(data, 'hook');
  final metrics = healthSection(hook, 'metrics');
  final root = healthSection(data, 'root');
  final xp = healthSection(data, 'xposed');
  final enabled = config['enabled'] == true;
  final userDisabled =
      !enabled && config['recoveryReason'] == 'Disabled by user';
  final scope = ((xp['scope'] as List?) ?? []).contains('com.android.systemui');
  final hookBridge = hook['fresh'] == true &&
      hook['state'] != 'error' &&
      hook['state'] != 'unsupported';
  final current = hook['revision'] == config['revision'];
  final interval = (config['intervalMs'] as num?)?.toInt() ?? 1000;
  final sampleAge = (metrics['sampleAgeMs'] as num?)?.toInt() ?? -1;
  final delayedSample =
      enabled && metrics['visible'] == true && sampleAge > interval * 3 + 1000;
  final rootWarning = root['probeWarning']?.toString();
  final carrier = healthSection(data, 'carrier');
  final carrierInstalled = carrier['installed'] == true;
  final carrierEnabled = carrier['moduleState'] == 'enabled';
  return [
    CustomizationCheck(
      'Indicator',
      (hook['error'] as String? ?? '').isNotEmpty
          ? '${hook['error']}'
          : indicatorStatus(data),
      attention:
          (config['emergencyDisabled'] == true && !userDisabled) ||
          (enabled &&
              (hook['fresh'] != true ||
                  hook['state'] == 'error' ||
                  hook['state'] == 'unsupported' ||
                  metrics['visibilityReason'] == 'safetyCheckOverdue')),
    ),
    CustomizationCheck(
      'Hook version',
      data['hookUpdateRequired'] == true
          ? 'Restart SystemUI once to load the installed update.'
          : 'Revision ${hook['version'] ?? '—'} · PID ${hook['pid'] ?? '—'}',
      attention: data['hookUpdateRequired'] == true,
    ),
    CustomizationCheck(
      'Framework',
      xp['connected'] == true
          ? '${xp['name']} · API ${xp['api']} · ${scope ? 'SystemUI scoped' : 'scope missing'}'
          : hookBridge
          ? 'SystemUI hook bridge active · manager service connection unavailable'
          : 'Not connected to the Xposed service',
      attention: !hookBridge && (xp['connected'] != true || !scope),
    ),
    CustomizationCheck(
      'Recovery watchdog',
      rootWarning ??
          (root['quarantined'] == 'true'
              ? (userDisabled
                    ? 'Customization is off by user choice; watchdog is available.'
                    : 'Customization has been quarantined by recovery.')
              : (root['moduleState'] == 'healthy'
                    ? 'Heartbeat ${root['watchdogAgeSeconds'] ?? '—'} s old at last check'
                    : '${root['moduleState'] ?? 'Not checked'}')),
      attention:
          root['moduleState'] != 'healthy' ||
          rootWarning != null ||
          (root['quarantined'] == 'true' && !userDisabled),
    ),
    CustomizationCheck(
      'Settings synchronization',
      current
          ? 'Manager and hook agree on revision ${config['revision']}.'
          : 'Requested ${config['revision'] ?? '—'} · observed ${hook['revision'] ?? '—'}',
      attention: enabled && !current && data['restartRequired'] == true,
    ),
    CustomizationCheck(
      'Safety lease',
      '${((_dataLease(data)) / 1000).round()} seconds remaining before a fresh check is required',
      attention: enabled && _dataLease(data) <= 0,
    ),
    CustomizationCheck(
      'Status bar attachment',
      metrics['attached'] == true
          ? '${metrics['attachments'] ?? 0} attachments · ${metrics['detachments'] ?? 0} detachments this process'
          : 'Waiting for the normal status bar window',
      attention:
          enabled &&
          hook['fresh'] == true &&
          metrics['visibilityReason'] == 'detached',
    ),
    CustomizationCheck(
      'Text layout',
      metrics['textClipped'] == true
          ? 'Text may be clipped. Reduce text size or decimal places.'
          : 'No clipping reported',
      attention: metrics['textClipped'] == true,
    ),
    CustomizationCheck(
      'Traffic sampling',
      delayedSample
          ? 'Samples are delayed while the meter is visible.'
          : sampleAge >= 0
          ? 'Latest sample $sampleAge ms before the last report · ${metrics['counterResets'] ?? 0} counter resets'
          : 'No sample reported yet',
      attention: delayedSample,
    ),
    CustomizationCheck(
      'SystemUI restarts',
      '${root['systemUiRestarts'] ?? '—'} in the current watchdog window',
      attention: (int.tryParse('${root['systemUiRestarts']}') ?? 0) > 0,
    ),
    CustomizationCheck(
      'Device compatibility',
      data['safeMode'] == true
          ? 'Android safe mode is active.'
          : data['supported'] == true
          ? 'This Android build is validated.'
          : 'This Android build is not validated.',
      attention: data['safeMode'] == true || data['supported'] != true,
    ),
    if (carrierInstalled || carrier['supportedCarrierDetected'] == true)
      CustomizationCheck(
        'Carrier backend',
        !carrierInstalled
            ? 'Supported Tunisian carrier detected; backend is not installed.'
            : carrier['updateRequired'] == true
            ? 'A managed backend update is available.'
            : carrier['rebootRequired'] == true
            ? 'A carrier backend change is waiting for reboot.'
            : carrierEnabled
            ? 'Enabled · version ${carrier['moduleVersion'] ?? '—'}'
            : 'Stock behavior selected',
        attention:
            carrier['supportedCarrierDetected'] == true &&
            (!carrierInstalled || carrier['updateRequired'] == true),
      ),
    if (carrierInstalled)
      CustomizationCheck(
        'Carrier database',
        carrier['rebootRequired'] == true && carrier['sourceFound'] != 'true'
            ? 'The staged database will be verified after reboot.'
            : carrier['configurationValid'] == true
            ? 'Known-good cfgdb and approved Tunisia mappings verified.'
            : 'The installed cfgdb does not match the approved artifact.',
        attention:
            carrier['configurationValid'] != true &&
            !(carrier['rebootRequired'] == true &&
                carrier['sourceFound'] != 'true'),
      ),
    if (carrierInstalled && carrierEnabled && carrier['rebootRequired'] != true)
      CustomizationCheck(
        'Carrier override',
        carrier['active'] == true
            ? 'The systemless cfgdb override is mounted and matches its source.'
            : 'The enabled backend is not mounted or its visible target differs.',
        attention: carrier['active'] != true,
      ),
  ];
}

num _dataLease(Map<String, dynamic> data) =>
    data['safetyLeaseRemainingMs'] as num? ?? 0;
