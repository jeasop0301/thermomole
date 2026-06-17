# Attribution

ThermoMole is an open-source macOS menu-bar utility for Apple Silicon, released under the GNU General Public License v3.0 (see [LICENSE](LICENSE)).

## Prior-art inspiration

The projects below inspired ThermoMole's approach. They are referenced for inspiration only — **no code is copied from any of them**.

- MacMonitor by ryyansafar: https://github.com/ryyansafar/MacMonitor (MIT)
- Mole by tw93: https://github.com/tw93/mole (GPL-3.0)
- Mole product site: https://mole.fit/

MacMonitor's SMC access *pattern* informed ThermoMole's native Apple Silicon thermal reader. Mole informed the five-tool product shape and review-first maintenance workflows.

## Independent implementation

All native sensor, SMC, and IOHIDEvent code in ThermoMole is an independent reimplementation. The in-file notices in `Sources/ThermoMoleSMC/SMC.c` and the IOHIDEvent reader assert that no code was copied from MacMonitor, Mole, or any other project.

ThermoMole's GPL-3.0 license is compatible with the GPL-3.0 licensing of Mole, so any concern about Mole-derived code is moot — and in any case no such code exists here.
