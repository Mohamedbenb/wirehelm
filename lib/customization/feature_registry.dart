/// Stable capability IDs, independent of framework branding and transport.
sealed class Requirement {
  const Requirement();
  bool satisfied(Set<String> available);
}

class Capability extends Requirement {
  final String id;
  const Capability(this.id);
  @override
  bool satisfied(Set<String> available) => available.contains(id);
}

class AllOf extends Requirement {
  final List<Requirement> requirements;
  const AllOf(this.requirements);
  @override
  bool satisfied(Set<String> available) =>
      requirements.every((r) => r.satisfied(available));
}

class AnyOf extends Requirement {
  final List<Requirement> requirements;
  const AnyOf(this.requirements);
  @override
  bool satisfied(Set<String> available) =>
      requirements.any((r) => r.satisfied(available));
}

class LocalFeatureDefinition {
  final String id, title;
  final Requirement requirement;
  const LocalFeatureDefinition(this.id, this.title, this.requirement);
}

const networkSpeedFeature = LocalFeatureDefinition(
  'systemui.networkSpeed',
  'Network speed indicator',
  AllOf([
    Capability('xposed.systemuiHook'),
    Capability('xposed.remoteConfiguration'),
    Capability('root.recoveryWatchdog'),
    Capability('device.validatedSystemUi'),
  ]),
);

const edgePanelFeature = LocalFeatureDefinition(
  'systemui.edgePanel',
  'Edge panel',
  AllOf([
    Capability('xposed.systemuiHook'),
    Capability('xposed.remoteConfiguration'),
    Capability('root.recoveryWatchdog'),
    Capability('device.validatedSystemUi'),
  ]),
);

const tunisia5gFeature = LocalFeatureDefinition(
  'carrier.tunisia5g',
  'Tunisia 5G profile',
  AllOf([
    Capability('root.carrierProfileOverride'),
    Capability('carrier.tunisia5gSupported'),
  ]),
);

/// Reserve capabilities for native/kernel providers; do not assume either exists.
const futureBackendCapabilities = {
  'native.processHook',
  'native.jniHook',
  'kernel.specificOperation',
};
