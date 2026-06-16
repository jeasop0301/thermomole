# Memory Clean Research

ThermoMole should not ship a classic "free RAM" button as a default action.
On modern macOS, high used memory alone is not a problem. Activity Monitor's
memory pressure is the safer user-facing signal because it reflects free memory,
swap rate, wired memory, and file cache behavior together.

## Current Decision

- Keep Memory Clean disabled until it has measured benefit on Apple Silicon.
- Ship Memory Doctor first: pressure diagnosis, top-process review, and clear
  messaging when no cleanup is needed.
- Show pressure, swap, compressed memory, cached files, and top memory processes
  before offering any action.
- Treat green pressure as "no cleanup needed" even when RAM used percent is high.
- Prefer coaching the user toward closing heavy apps or tabs when pressure stays
  yellow/red.

## Allowed Design

1. Observe-only first:
   - Status shows Activity Monitor-style used memory.
   - Detail view should add pressure history, swap used, compressed bytes, cached
     files, and top memory processes.

2. Gentle app-local cleanup:
   - Release ThermoMole's own cached scan results, histories, and transient data.
   - Never claim this frees system RAM in a durable way.

3. Optional advanced `purge` action:
   - Hidden behind an explicit advanced confirmation.
   - Explain that it targets disk/file cache behavior, not anonymous app memory,
     can make the next app/file access slower, and may have only temporary
     effects.
   - Never run automatically or from the menu bar default click.

## Forbidden Design

- Do not kill or suspend user apps.
- Do not run `memory_pressure` as a cleanup action; it is for pressure testing.
- Do not delete swap files or restart `dynamic_pager`.
- Do not advertise freed bytes as a lasting performance gain.
- Do not trigger a cleanup while memory pressure is green.

## Product Shape

Memory Clean should eventually be a Doctor-guided flow, not a flashy button:

1. Diagnose pressure.
2. Identify top memory processes.
3. Offer low-risk actions first.
4. Only expose `purge` as an advanced, clearly temporary cache reset.
5. Log every action locally.

Current implementation:

- `MemoryDoctorReport` maps normal/warning/critical pressure to calm/watch/
  critical guidance.
- GUI Status shows Memory Doctor with pressure, compressed memory, free/cache
  memory, and the top memory process.
- CLI `thermomole memory` prints the same doctor report.
- CLI `thermomole memory --purge` prints a gated plan.
- CLI/GUI purge execution is disabled unless memory pressure is critical, uses
  explicit confirmation, runs `/usr/bin/purge`, and logs the result locally.
- External shell reads use timeouts where needed so process inventory cannot
  block menu bar/status refresh indefinitely.

## Measurement Plan

Before enabling any memory action:

- Capture baseline: pressure label, swap used, compressed memory, file cache,
  top process memory, and user-visible app responsiveness notes.
- Run candidate action.
- Capture the same metrics after 5 seconds, 60 seconds, and 5 minutes.
- Reject the action if pressure does not improve, swap behavior does not improve,
  or the next app/file access becomes noticeably worse.

## Sources

- Apple Support: Activity Monitor memory pressure is based on free memory, swap
  rate, wired memory, and file cache.
  https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac
- Apple Developer: `DispatchSourceMemoryPressure` monitors memory pressure
  changes.
  https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure
- Apple Developer: Unix manual pages should be read locally for low-level macOS
  commands.
  https://developer.apple.com/documentation/os/reading-unix-manual-pages
- Local macOS man pages checked on this machine:
  - `man purge`: `purge` flushes disk cache for cold-cache performance analysis
    and does not affect anonymous memory allocated through `malloc` or
    `vm_allocate`.
  - `man memory_pressure`: `memory_pressure` applies or simulates pressure; it
    is a test tool, not a cleanup tool.
