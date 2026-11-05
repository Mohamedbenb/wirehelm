# Standalone Liquid Glass engine

Node Cockpit uses stock SystemUI rendering for notifications, Quick Settings, brightness and volume. The edge panel defaults to Card Glass and its collapsed handle uses the Native Glass renderer. Edge panel settings control the materials and preserve the saved search tray geometry.

Card Glass exposes a white veil for Clear and adaptive tone strength for Regular. Both default to zero for the edge panel. Tint strength controls the separate color tint.

Node Cockpit uses the [Liquid Glass engine](../android/liquid-glass-engine/README.md) through its edge controller. The [standalone lab](../glass-lab/README.md) also builds independently. The engine README and its preview coverage document describe the supported APIs and test scenarios.
