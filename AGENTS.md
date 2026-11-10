# Working on Wirehelm

- Start with [the code map](docs/CODE_MAP.md) for feature ownership. Read the relevant section and its linked files. Use [the handoff](docs/CODEX_HANDOFF.md) for the current build and device state.
- Search the relevant source directory with `rg`. Read historical reports in `docs/history/` only when tracing a regression or checking earlier evidence. Use `rg --no-ignore` with an explicit archive path.
- Consult [build and deployment](docs/BUILD_AND_DEPLOY.md) for release work. Report build, installation, hook activation, and user-visible validation separately.
- Preserve the Android package, signing identity, and stored settings during updates. The standalone glass engine and live edge-panel materials are active. Android owns notification, Quick Settings, brightness, and volume styling.
