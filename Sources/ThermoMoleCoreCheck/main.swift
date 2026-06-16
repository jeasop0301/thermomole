import Foundation
import ThermoMoleCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        Foundation.exit(1)
    }
}

let batterySample = """
  "Temperature" = 3141
  "VirtualTemperature" = 4089
  "CycleCount" = 7
"""
let parsed = AppleSmartBatteryParser.parse(batterySample)
check(parsed.temperatureC == 31.41, "AppleSmartBattery Temperature parses as 31.41C")
check(parsed.virtualTemperatureC == 40.89, "VirtualTemperature parses separately")

let batteryThermal = BatteryTemperaturePolicy.resolve(
    smcCellTemperaturesC: [32.4, 35.8, 34.1],
    ioregTemperatureC: 31.41
)
check(batteryThermal.batteryDisplayC == 31.41, "ioreg Temperature wins")
check(batteryThermal.batteryTemperatureSource == .ioregTemperature, "ioreg source selected")
check(batteryThermal.batteryWarningLevel == .normal, "31C battery warning is normal")

let cpuThermal = ThermalPolicy.resolveCPUTemperature(cpuDieHotspotC: 72.4, cpuAverageC: 55.1)
check(cpuThermal.valueC == 72.4, "CPU hotspot wins")
check(cpuThermal.source == .cpuDieHotspot, "CPU hotspot source selected")

let memory = MemoryCalculator.snapshot(
    pageSize: 16_384,
    activePages: 200_000,
    wiredPages: 100_000,
    compressedPages: 50_000,
    speculativePages: 20_000,
    inactivePages: 80_000,
    freePages: 50_000,
    totalBytes: 8_192_000_000
)
check(memory.usedBytes == 5_734_400_000, "Activity Monitor style used bytes")
check(memory.usedPercent == 70, "Activity Monitor style memory percent")

let health = HealthScorer.score(
    cpuUsagePercent: 15,
    memoryUsedPercent: 40,
    diskUsedPercent: 50,
    batteryTemperatureC: 40,
    cpuTemperatureC: 55,
    uptimeSeconds: 1_800
)
check(health.issues.contains(.batteryHot), "40C battery issue is hot")

let condition = SystemConditionPolicy.resolve(
    cpuTemperatureC: 95,
    batteryWarningLevel: .normal,
    memoryPressure: .normal,
    healthBand: .excellent
)
check(condition == .hot, "CPU hotspot drives menu bar condition")

let validator = ProtectedPathValidator(homeDirectory: URL(fileURLWithPath: "/Users/jisub"))
check(!validator.canDelete(URL(fileURLWithPath: "/")), "root is protected")
check(validator.canDelete(URL(fileURLWithPath: "/Users/jisub/Library/Caches/com.example")), "cache descendant allowed")

print("ThermoMoleCoreCheck passed")
