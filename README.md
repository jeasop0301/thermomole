# Patina

Patina is a battery-longevity and aging-insight menu-bar app for Apple Silicon Macs.

It runs entirely on-device — no network telemetry, no account required — and complements charge-limiter tools like AlDente by showing you *why* your battery ages: thermal exposure, high-SoC dwell, and charging habits surfaced as a single 0–100 longevity score with plain-language actions.

- Menu bar HUD with configurable metrics — CPU temperature, battery temperature, and RAM percent are always available; the title tints by system condition.
- Battery temperature policy: `AppleSmartBattery` `Temperature / 100` first, SMC `TB0T`–`TB2T` fallback/diagnostics, `VirtualTemperature` ignored.
- Battery warning policy: 42°C caution, 48°C hot (cell-referenced). No notification by default.
- Thermal exposure tracking: per-day cumulative minutes at/above 40°C and 45°C plus the day's peak battery temperature, persisted locally to `~/Library/Application Support/ThermoMole/`. Surfaced in the Status dashboard and the menu-bar card.
- High state-of-charge dwell tracking: time held at ≥80% / ≥95% while on AC power (a primary calendar-aging factor), persisted locally.
- Accelerated-aging engine: a live "aging speed" multiplier versus an ideal idle baseline (25°C / 50%), derived from published Li-ion kinetics — Arrhenius temperature acceleration (Ea = 0.55 eV) × a state-of-charge factor — plus a cumulative weekly "strain" (effective aging-days) and a cold-charge lithium-plating caution. Labeled throughout as a relative estimate, not a capacity measurement.
- Patina aging card (menu-bar popover): the live multiplier and its dominant driver (heat vs charge); cell temperature / charge / power state (On battery · Charging · Full · AC · Held · AC); the weekly strain with a 7-day sparkline; a health outlook; and a Details expander with an hour-of-day heat strip, a battery-health projection band, longevity factors, and a 0–100 longevity score with plain-language actions.
- Charging-while-hot warning: an in-app banner and a menu-bar flame when the battery is hot while on AC power. No system notification by default.
- Status dashboard with a human-readable system brief, CPU (with a per-core grid), battery, RAM, disk, network, health score, top processes, instant battery power, internal SSD temperature, and 60-second trend sparklines.
- Battery health trend log (daily health %, cycle count, capacity) → longevity score, fade/cycle-rate inference, and projected months to 80%.
- Optional local notifications (off by default) for charging-while-hot, sustained heat, prolonged high charge, and low storage — throttled, with quiet hours.
- Status restores the last sampled snapshot from `~/Library/Application Support/ThermoMole/last-status.json` for instant launch before the first live sample completes.
- Settings: menu bar metric selection/reordering, Dock icon visibility, launch-at-login registration, and a system-notifications toggle.
- SwiftUI controls include accessibility labels for the menu bar popover and Status cards.

## Run

```bash
./scripts/run-dev.sh
```

The script builds with SwiftPM, re-signs the debug executable ad-hoc, and launches the menu bar app.

## Build App Bundle

```bash
./scripts/build-app.sh
open dist/Patina.app
```

The app bundle is menu-bar-first (`LSUIElement`) and hides the Dock icon by default.

### Install a release build

Download `Patina.zip` from the latest [GitHub Release](../../releases), unzip,
and move `Patina.app` to `/Applications`. Release builds are signed with a
Developer ID and notarized by Apple, so they launch without a Gatekeeper prompt.

If you build from source instead, the app is ad-hoc signed; on first launch use
Finder's right-click → Open, or run `xattr -dr com.apple.quarantine dist/Patina.app`.

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
- Insight only — no charge control. Patina reads sensors and never writes to the SMC; pair it with a charge limiter (AlDente) or macOS Optimized Battery Charging to act on what it shows.
- Fan control is intentionally excluded. Fan RPM is read-only when available.
- Runs entirely on-device: no network telemetry, no account. All history is persisted locally under `~/Library/Application Support/ThermoMole/`.
- The aging multiplier and longevity score are relative estimates from published kinetics, not capacity measurements; treat them as directional guidance, not a battery-health readout.

## Longevity

The menu-bar popover surfaces a Patina aging card — a live accelerated-aging multiplier, weekly strain, and a Details expander with the full breakdown: a single 0–100 longevity score, per-factor status (battery, heat, charging habits, storage, memory), and a prioritized list of plain-language actions to keep the Mac healthy longer. Backing it:

- Battery thermal-exposure and CPU/system thermal-exposure tracking (per-day minutes above thresholds, 7-day strips), persisted locally.
- High state-of-charge dwell tracking — time held at ≥80% / ≥95% while on AC power (a primary aging factor), persisted locally.
- Battery health trend log (daily health %, cycle count, capacity) → longevity score, fade/cycle-rate inference, and projected months to 80%.
- Instant battery power (V × A watts) and internal SSD temperature (via IOHIDEvent sensors).
- Optional local notifications (off by default) for charging-while-hot, sustained heat, prolonged high charge, and low storage — throttled, with quiet hours.
- No charge control: Patina reads sensors only and never writes to the SMC.

## License

Patina is licensed under the GNU General Public License v3.0 — see [LICENSE](LICENSE).

Copyright (C) 2026 jeasop0301.
