import Foundation

/// System probes for Optimize safety context. Each value only shells out (no UI/actor
/// state), so `live()` is safe to run off the main actor. Inject a stub in tests.
public struct OptimizeSafetyProbe: Equatable, Sendable {
    public var hasActiveVPN: Bool
    public var hasExternalAudio: Bool
    public var hasBluetoothHID: Bool
    public var hasBluetoothAudio: Bool

    public init(
        hasActiveVPN: Bool,
        hasExternalAudio: Bool,
        hasBluetoothHID: Bool,
        hasBluetoothAudio: Bool
    ) {
        self.hasActiveVPN = hasActiveVPN
        self.hasExternalAudio = hasExternalAudio
        self.hasBluetoothHID = hasBluetoothHID
        self.hasBluetoothAudio = hasBluetoothAudio
    }

    public static func live() -> OptimizeSafetyProbe {
        let vpn = Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeoutSeconds: 1)
        let audio = Shell.run("/usr/sbin/system_profiler", ["SPAudioDataType"], timeoutSeconds: 2)
        let bluetooth = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType"], timeoutSeconds: 2)
        return OptimizeSafetyProbe(
            hasActiveVPN: vpn.status == 0 && OptimizeSafetyContextParser.hasActiveVPN(scutilOutput: vpn.stdout),
            hasExternalAudio: audio.status == 0 && OptimizeSafetyContextParser.hasExternalAudio(systemProfilerAudioOutput: audio.stdout),
            hasBluetoothHID: bluetooth.status == 0 && OptimizeSafetyContextParser.hasBluetoothHID(systemProfilerBluetoothOutput: bluetooth.stdout),
            hasBluetoothAudio: bluetooth.status == 0 && OptimizeSafetyContextParser.hasBluetoothAudio(systemProfilerBluetoothOutput: bluetooth.stdout)
        )
    }
}
