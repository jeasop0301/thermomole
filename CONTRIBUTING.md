# Contributing to Patina

Thanks for your interest in Patina.

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode 16+ / Swift 6 toolchain

## Build & run

```bash
./scripts/run-dev.sh        # build + ad-hoc sign + launch the menu bar app
swift run ThermoMoleCLI status
```

## Test

`swift test` can hang while loading the XCTest runner on some toolchains, so use:

```bash
bash ./scripts/test-core.sh
```

## Pull requests

- Keep changes focused; one logical change per PR.
- Run `bash ./scripts/test-core.sh` and `swift build -c release` before opening a PR.
- Match the surrounding code style. No fan control and no SMC writes.

## Reporting bugs

Open a GitHub issue with your macOS version, Mac model, and steps to reproduce. CLI `swift run ThermoMoleCLI status --json` output is helpful.
