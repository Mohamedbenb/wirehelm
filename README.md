# Wirehelm

Wirehelm combines SSH and remote device tools with optional customization for rooted Pixel phones. Earlier builds used the name Node Cockpit.

## Features

- SSH terminal, SFTP file transfers, saved commands, and remote desktop tools.
- An embedded Tailscale client and an authenticated, temporary [Remote ADB relay](docs/REMOTE_ADB.md).
- Optional Pixel customization, including a network speed indicator, an edge launcher with glass materials, a camera notification ring, and Notification Undo.
- A [root file explorer](docs/ROOT_FILE_EXPLORER.md) with read-only browsing by default and time-limited, folder-specific writes.

SSH and SFTP work without root. Pixel customization depends on the supported SystemUI build and its module framework. The glass integration styles Wirehelm's edge panel and handle. Android owns notification, Quick Settings, brightness, and volume rendering.

## Build and development

Start with [Build and deployment](docs/BUILD_AND_DEPLOY.md) for the Android toolchain and fresh-checkout steps. See the [code map](docs/CODE_MAP.md), [behavior guide](docs/BEHAVIOR_GUIDE.md), and [debugging guide](docs/DEBUGGING.md) for implementation details. The [handoff](docs/CODEX_HANDOFF.md) records the last verified device build separately from the current source.

## Project layout

- `lib/`: Flutter UI, device/session models, SSH tools and transport adapters.
- `android/app/`: Android platform bridges and app-owned services.
- `android/customization/`: app-side configuration/recovery and injected SystemUI rendering.
- `native/tsnet/`: embedded Tailscale transport and temporary ADB relay.
- `android/termux-terminal/`: terminal component; see its upstream/license notes.
- `third_party/dartssh2/`: SSH dependency fork; see NODE_COCKPIT_PATCH.md before changing it.
- `scripts/`: backend packaging, native binding builds and APK verification/publication.

## Reusable Liquid Glass engine

The [Liquid Glass engine](android/liquid-glass-engine/README.md) supplies the edge panel's materials. [Glass Lab](glass-lab/README.md) builds the engine and a standalone Android demo.

## Third-party components

See the vendored notices for the [Termux terminal](android/termux-terminal/UPSTREAM.md), [dartssh2](third_party/dartssh2/LICENSE), and [Liquid Glass optics](android/liquid-glass-engine/src/main/assets/licenses/liquid-glass-views.txt).
