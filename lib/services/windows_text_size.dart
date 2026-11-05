import 'dart:convert';

import '../ssh/ssh_session.dart';

const windowsTextSizeStatus = r'''
$ErrorActionPreference='Stop'
$null=[Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime]
$ui=New-Object Windows.UI.ViewManagement.UISettings
[int][Math]::Round($ui.TextScaleFactor*100)
''';

String windowsTextSizeApply(int percent) {
  if (percent < 100 || percent > 225) {
    throw RangeError.range(percent, 100, 225);
  }
  return r'''
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Start-Process 'ms-settings:easeofaccess-display'
$sliderId='SystemSettings_EaseOfAccess_Experience_TextScalingDesktop_Slider'
$buttonId='SystemSettings_EaseOfAccess_Experience_TextScalingDesktop_ButtonRemove'
$root=[Windows.Automation.AutomationElement]::RootElement
$deadline=(Get-Date).AddSeconds(12)
$slider=$null; $button=$null
while ((Get-Date) -lt $deadline) {
 $windows=$root.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)
 $settingsIds=@(Get-Process -Name SystemSettings -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
 foreach ($window in $windows) {
  if ($window.Current.ClassName -ne 'ApplicationFrameWindow' -and $settingsIds -notcontains $window.Current.ProcessId) { continue }
  $slider=$window.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$sliderId))
  if ($slider) {
   $button=$window.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$buttonId))
   break
  }
 }
 if ($slider -and $button) { break }
 Start-Sleep -Milliseconds 150
}
if (-not $slider -or -not $button) { throw 'Windows Text size controls were not found. Sign into the desktop and unlock it, then retry. This Windows version may use different controls.' }
$range=$slider.GetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern)
$wanted=__PERCENT__
if ($wanted -lt $range.Current.Minimum -or $wanted -gt $range.Current.Maximum) { throw 'Text size is outside the supported Windows range.' }
$range.SetValue($wanted)
$enableDeadline=(Get-Date).AddSeconds(3)
while (-not $button.Current.IsEnabled -and (Get-Date) -lt $enableDeadline) { Start-Sleep -Milliseconds 100 }
if ($button.Current.IsEnabled) {
 $invoke=$button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
 $invoke.Invoke()
}
$null=[Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime]
$deadline=(Get-Date).AddSeconds(10)
do {
 $ui=New-Object Windows.UI.ViewManagement.UISettings
 $actual=[int][Math]::Round($ui.TextScaleFactor*100)
 if ($actual -eq $wanted) { Write-Output $actual; return }
 Start-Sleep -Milliseconds 200
} while ((Get-Date) -lt $deadline)
throw ('Windows did not confirm the active text size. Requested '+$wanted+'%, active '+$actual+'%.')
'''
      .replaceAll('__PERCENT__', '$percent');
}

Future<int> readWindowsTextSize(SshSession session) async => _value(
  await session.runPowerShell(
    windowsTextSizeStatus,
    desktop: true,
    label: 'Read text size',
  ),
);
Future<int> applyWindowsTextSize(SshSession session, int percent) async =>
    _value(
      await session.runPowerShell(
        windowsTextSizeApply(percent),
        desktop: true,
        label: 'Apply text size',
        timeout: const Duration(seconds: 45),
      ),
    );
int _value(List<int> bytes) {
  final value = int.tryParse(utf8.decode(bytes).trim());
  if (value == null || value < 100 || value > 225) {
    throw StateError('Windows returned an invalid text size.');
  }
  return value;
}
