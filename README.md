# ThermoMole

ThermoMole is a menu-bar-first macOS SwiftUI system utility for Apple Silicon Macs.

It pairs a menu-bar HUD with a multi-tab dashboard and native Apple Silicon thermal reads:

- Menu bar HUD with configurable metrics. CPU temperature, battery temperature, and RAM percent are always available.
- Battery temperature policy: `AppleSmartBattery` `Temperature / 100` first, SMC `TB0T`-`TB2T` fallback/diagnostics, `VirtualTemperature` ignored.
- Battery warning policy: 35°C caution, 40°C hot. No notification by default.
- Thermal exposure tracking: per-day cumulative minutes at/above 35°C and 40°C plus the day's peak battery temperature, persisted locally to `~/Library/Application Support/ThermoMole/thermal-exposure.json`. Surfaced as a "Today's battery heat exposure" card in Status and a compact line in the menu bar popover.
- Charging-while-hot warning: an in-app banner and a menu-bar visual (battery token tint, plus a flame at 40°C+ while charging) when the battery is warm/hot while on AC power. No system notification by default.
- Status dashboard with a human-readable system brief, CPU, battery, RAM, disk, network, health score, top processes, and 60-second trend sparklines.
- Clean includes a Smart Clean flow that scans, preselects recommended safe cache/log/installer items, shows category/path examples in the Trash confirmation, then moves selected items to Trash. Manual Review Scan remains available with category totals, search, category filtering, sorting, visible-item selection controls, path detail, Finder reveal, TCC-sensitive media cache skips, and operation logs. Scan categories include app caches, logs, developer artifacts, AI tool caches, browser caches, communication/design/cloud caches, temporary files, installer files, and Trash.
- Software includes auto-loaded app version inventory, startup item inventory, search/filter, Finder reveal/open actions, and confirmation-gated app uninstall-to-Trash.
- Analyze includes home-folder or chosen-folder scanning, cancelable scans, breadcrumb navigation, folder drill-down, Finder reveal, protected-path-aware Trash actions, and a disk treemap.
- Optimize includes a one-click Default Optimize flow that batches runnable maintenance tasks behind one confirmation, with a top safety summary showing current context, runnable task count, command count, and staged tasks. Individual task cards remain available with visible effect summaries for Quick Look, Launch Services, periodic maintenance, and Dock refresh. Saved application state cleanup remains staged, and safety policy stages riskier tasks on battery power, active VPN, external display, external audio, or connected Bluetooth input/audio contexts.
- Memory Doctor diagnoses pressure, compressed memory, free/cache memory, and top memory processes in Status and CLI. Advanced `purge` is gated behind critical memory pressure and explicit confirmation.
- CLI `status` shows freshness, CPU/battery sensor sources, physical battery temperature, and SMC/ioreg battery sensor mismatch evidence. JSON output includes the same trust fields.
- Local operation history records GUI and CLI execute actions to `~/Library/Logs/ThermoMole/operations.jsonl`.
- Status restores the last sampled snapshot from `~/Library/Application Support/ThermoMole/last-status.json` for instant launch before the first live sample completes.
- Settings include a local Doctor panel, diagnostic JSON export/import with summary preview, protected item policy viewer, operation history viewer, Full Disk Access status/open action, menu bar metric selection/reordering, Dock icon visibility, and launch-at-login registration.
- SwiftUI controls include first-pass accessibility labels for the menu bar popover, Status cards, cleanup selection, disk treemap, breadcrumb navigation, search clear controls, and icon-only actions.

## Run

```bash
./scripts/run-dev.sh
```

The script builds with SwiftPM, re-signs the debug executable ad-hoc, and launches the menu bar app.

## CLI

The CLI uses the same core plans as the GUI. Default commands show the one-click
plan; `--execute` runs the recommended action without item-by-item selection.
Add `--json` to any command for machine-readable output.
Analyze and Software default to summary-first output and reserve detailed rows
for supporting context.

```bash
swift run ThermoMoleCLI status
swift run ThermoMoleCLI clean
swift run ThermoMoleCLI clean --execute
swift run ThermoMoleCLI installer
swift run ThermoMoleCLI installer --execute
swift run ThermoMoleCLI uninstall "App Name"
swift run ThermoMoleCLI uninstall "App Name" --execute
swift run ThermoMoleCLI optimize
swift run ThermoMoleCLI optimize --execute
swift run ThermoMoleCLI analyze
swift run ThermoMoleCLI software
swift run ThermoMoleCLI memory
swift run ThermoMoleCLI memory --purge
swift run ThermoMoleCLI memory --purge --execute
swift run ThermoMoleCLI history
swift run ThermoMoleCLI status --json
```

## Build App Bundle

```bash
./scripts/build-app.sh
open dist/ThermoMole.app
```

The app bundle is menu-bar-first (`LSUIElement`) and hides the Dock icon by default.

### Install a release build

Download `ThermoMole.zip` from the latest [GitHub Release](../../releases), unzip,
and move `ThermoMole.app` to `/Applications`. Release builds are signed with a
Developer ID and notarized by Apple, so they launch without a Gatekeeper prompt.

If you build from source instead, the app is ad-hoc signed; on first launch use
Finder's right-click → Open, or run `xattr -dr com.apple.quarantine dist/ThermoMole.app`.

## Verify

```bash
bash ./scripts/test-core.sh

swift build --product ThermoMoleCoreCheck
codesign --force --sign - .build/arm64-apple-macosx/debug/ThermoMoleCoreCheck
.build/arm64-apple-macosx/debug/ThermoMoleCoreCheck
```

`swift test` can hang in Xcode 26.4.1 while loading the XCTest runner on this machine. `scripts/test-core.sh` builds the tests, clears generated xattrs, re-signs the test bundle binary, and runs `xcrun xctest` directly.

## Notes

- Target: Apple Silicon only, macOS 14+.
- Fan control is intentionally excluded. Fan RPM is read-only when available.
- Quick tools are intentionally excluded from the current build.
- Full Disk Access is not requested automatically; it improves scan coverage if granted manually.
- Clean and Analyze skip privacy-sensitive default media/file roots before sizing to avoid surprise Apple Music, Photos, Desktop, Documents, and Downloads permission prompts. Choose a folder directly when you want to inspect one of those roots.
- Settings shows the protected roots, allowed Trash prefixes, and default scan skips used by cleanup and analyze flows.
- Smart Clean auto-selects recommended safe cleanup items, then requires confirmation before moving anything to Trash. Manual Review Scan remains unselected-by-default. Permanent deletion is intentionally excluded.
- Memory Doctor is pressure-first diagnosis, not a classic "free RAM" button. Advanced purge is only executable at critical pressure with explicit confirmation and operation history logging.
- Optimize safety checks are conservative: Quick Look remains runnable, periodic maintenance is kept out of the one-click default because it needs administrator privileges (still runnable individually), Launch Services uses a safe incremental re-register (no `-kill` database wipe, no `system` domain), and Dock refresh is staged when external display, default external audio output, connected Bluetooth input, or connected Bluetooth audio is detected. External audio and Bluetooth checks use short-timeout `system_profiler` probes; failed probes are treated as absent context.
- Diagnostic reports are local JSON files containing status, Doctor checks, and recent operation history for troubleshooting. Settings can export a new report or import an existing report and show a local summary preview.

## Longevity

A dedicated Longevity tab turns the raw signals into a single 0–100 score, per-factor status (battery, heat, charging habits, storage, memory), and a prioritized list of plain-language actions to keep the Mac healthy longer. Backing it:

- Battery thermal-exposure and CPU/system thermal-exposure tracking (per-day minutes above thresholds, 7-day strips), persisted locally.
- High state-of-charge dwell tracking — time held at ≥80% / ≥95% while on AC power (a primary aging factor), persisted locally.
- Battery health trend log (daily health %, cycle count, capacity) → longevity score, fade/cycle-rate inference, and projected months to 80%.
- Instant battery power (V × A watts) and internal SSD temperature (via IOHIDEvent sensors).
- Optional local notifications (off by default) for charging-while-hot, sustained heat, prolonged high charge, and low storage — throttled, with quiet hours.
- No charge control: ThermoMole reads sensors only and never writes to the SMC.

## License

ThermoMole is licensed under the GNU General Public License v3.0 — see [LICENSE](LICENSE).

Copyright (C) 2026 jeasop0301.
