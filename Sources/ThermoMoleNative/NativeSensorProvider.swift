import Darwin
import Foundation
import IOKit
import ThermoMoleCore
import ThermoMoleSMC

public protocol SensorProvider {
    func sample() async -> SystemSnapshot
}

public actor NativeSensorProvider: SensorProvider {
    private var previousCPUTicks: [[UInt32]] = []
    private var previousNetworkIn: UInt64 = 0
    private var previousNetworkOut: UInt64 = 0
    private var previousNetworkDate = Date()

    public init() {}

    public func sample() async -> SystemSnapshot {
        sampleSynchronously()
    }

    public func sampleSynchronously() -> SystemSnapshot {
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let disk = sampleDisk()
        let network = sampleNetwork()
        let batteryInfo = sampleBatteryInfo()
        let thermalAndFan = sampleThermals(batteryInfo: batteryInfo)
        let battery = sampleBatteryStatus(info: batteryInfo)
        let topProcesses = sampleTopProcesses()
        let uptimeSeconds = UInt64(ProcessInfo.processInfo.systemUptime)
        let health = HealthScorer.score(
            cpuUsagePercent: cpu.usagePercent,
            memoryUsedPercent: memory.usedPercent,
            diskUsedPercent: disk.usedPercent,
            batteryTemperatureC: thermalAndFan.thermal.batteryDisplayC,
            cpuTemperatureC: thermalAndFan.thermal.cpuDisplayC,
            uptimeSeconds: uptimeSeconds
        )

        return SystemSnapshot(
            sampledAt: Date(),
            chipName: sysctlString("machdep.cpu.brand_string").replacingOccurrences(of: "Apple ", with: ""),
            modelIdentifier: sysctlString("hw.model"),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            uptimeSeconds: uptimeSeconds,
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: network,
            battery: battery,
            thermal: thermalAndFan.thermal,
            fanRPM: thermalAndFan.fanRPM,
            topProcesses: topProcesses,
            health: health
        )
    }

    private func sampleCPU() -> CPUStatus {
        var numCPUs: natural_t = 0
        var rawInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &rawInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let rawInfo else {
            return CPUStatus(
                usagePercent: 0,
                perCorePercent: [],
                logicalCoreCount: ProcessInfo.processInfo.processorCount,
                performanceCoreCount: coreCount(named: "performance"),
                efficiencyCoreCount: coreCount(named: "efficiency"),
                loadAverage: loadAverage()
            )
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: rawInfo),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let cpuCount = Int(numCPUs)
        var current = [[UInt32]](repeating: [0, 0, 0, 0], count: cpuCount)
        for index in 0..<cpuCount {
            let base = index * Int(CPU_STATE_MAX)
            current[index][0] = UInt32(bitPattern: rawInfo[base + Int(CPU_STATE_USER)])
            current[index][1] = UInt32(bitPattern: rawInfo[base + Int(CPU_STATE_SYSTEM)])
            current[index][2] = UInt32(bitPattern: rawInfo[base + Int(CPU_STATE_IDLE)])
            current[index][3] = UInt32(bitPattern: rawInfo[base + Int(CPU_STATE_NICE)])
        }

        var perCore = [Double]()
        if previousCPUTicks.count == current.count {
            for index in 0..<cpuCount {
                let user = current[index][0] &- previousCPUTicks[index][0]
                let system = current[index][1] &- previousCPUTicks[index][1]
                let idle = current[index][2] &- previousCPUTicks[index][2]
                let nice = current[index][3] &- previousCPUTicks[index][3]
                let total = user + system + idle + nice
                let busy = user + system + nice
                perCore.append(total > 0 ? Double(busy) / Double(total) * 100.0 : 0)
            }
        }
        previousCPUTicks = current

        let usage = perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count)
        return CPUStatus(
            usagePercent: usage,
            perCorePercent: perCore,
            logicalCoreCount: cpuCount,
            performanceCoreCount: coreCount(named: "performance"),
            efficiencyCoreCount: coreCount(named: "efficiency"),
            loadAverage: loadAverage()
        )
    }

    private func sampleMemory() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return SystemSnapshot.placeholder.memory
        }

        let pageSize = UInt64(getpagesize())
        return MemoryCalculator.snapshot(
            pageSize: pageSize,
            activePages: UInt64(stats.active_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            speculativePages: UInt64(stats.speculative_count),
            inactivePages: UInt64(stats.inactive_count),
            freePages: UInt64(stats.free_count),
            totalBytes: UInt64(ProcessInfo.processInfo.physicalMemory)
        )
    }

    private func sampleDisk() -> DiskStatus {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        let total = (attrs?[.systemSize] as? NSNumber)?.uint64Value ?? 0
        let free = (attrs?[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        let used = total > free ? total - free : 0
        let percent = total > 0 ? Double(used) / Double(total) * 100 : 0
        return DiskStatus(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            usedPercent: percent,
            readBytesPerSecond: 0,
            writeBytesPerSecond: 0
        )
    }

    private func sampleNetwork() -> NetworkStatus {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return NetworkStatus(receivedBytesPerSecond: 0, sentBytesPerSecond: 0)
        }
        defer { freeifaddrs(ifaddr) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        let elapsed = max(now.timeIntervalSince(previousNetworkDate), 0.001)
        let seeded = previousNetworkIn > 0 || previousNetworkOut > 0
        let inRate = seeded ? UInt64(Double(received &- previousNetworkIn) / elapsed) : 0
        let outRate = seeded ? UInt64(Double(sent &- previousNetworkOut) / elapsed) : 0
        previousNetworkIn = received
        previousNetworkOut = sent
        previousNetworkDate = now
        return NetworkStatus(receivedBytesPerSecond: inRate, sentBytesPerSecond: outRate)
    }

    private func sampleBatteryInfo() -> AppleSmartBatteryInfo {
        // Timeout guards against IOKit-busy hangs (sleep/wake, thermal assertions);
        // on timeout Shell returns status 124, so the guard yields empty (nil temperature).
        let result = Shell.run("/usr/sbin/ioreg", ["-r", "-n", "AppleSmartBattery"], timeoutSeconds: 3.0)
        guard result.status == 0 else { return AppleSmartBatteryInfo() }
        return AppleSmartBatteryParser.parse(result.stdout)
    }

    private func sampleBatteryStatus(info: AppleSmartBatteryInfo) -> BatteryStatus {
        let pmset = Shell.run("/usr/bin/pmset", ["-g", "batt"]).stdout
        let power = PowerStateParser.parse(pmsetOutput: pmset, fallbackPercent: info.currentCapacityPercent)

        return BatteryStatus(
            percent: power.percent,
            isCharging: power.isCharging,
            isCharged: power.isCharged,
            isOnACPower: power.isOnACPower,
            timeRemaining: power.timeRemaining,
            cycleCount: info.cycleCount,
            healthPercent: info.healthPercent,
            currentCapacityMAh: info.rawCurrentCapacityMAh,
            maxCapacityMAh: info.rawMaxCapacityMAh,
            designCapacityMAh: info.designCapacityMAh,
            instantPowerW: info.instantPowerW,
            dailyMaxSoc: info.dailyMaxSoc,
            dailyMinSoc: info.dailyMinSoc
        )
    }

    private func sampleThermals(batteryInfo: AppleSmartBatteryInfo) -> (thermal: ThermalSnapshot, fanRPM: Int) {
        let conn = SMCOpen()
        guard conn != 0 else {
            let battery = BatteryTemperaturePolicy.resolve(
                smcCellTemperaturesC: [],
                ioregTemperatureC: batteryInfo.temperatureC,
                virtualTemperatureC: batteryInfo.virtualTemperatureC
            )
            let cpu = ThermalPolicy.resolveCPUTemperature(cpuDieHotspotC: nil, cpuAverageC: nil)
            var thermal = battery
            thermal.cpuDisplayC = cpu.valueC
            thermal.cpuTemperatureSource = cpu.source
            thermal.ssdTemperatureC = sampleSSDTemperatureC()
            return (thermal, 0)
        }
        defer { SMCClose(conn) }

        let cpuHotspot = smcValue(conn: conn, key: "TCMz")
        let cpuAverage = averageSMC(conn: conn, keys: ["TCMb", "Tp01", "Tp05", "Te04", "Te05", "Ts0K", "Ts0L"])
        let cpu = ThermalPolicy.resolveCPUTemperature(
            cpuDieHotspotC: cpuHotspot,
            cpuAverageC: cpuAverage
        )
        var thermal = BatteryTemperaturePolicy.resolve(
            smcCellTemperaturesC: ["TB0T", "TB1T", "TB2T"].map { smcValue(conn: conn, key: $0) },
            ioregTemperatureC: batteryInfo.temperatureC,
            virtualTemperatureC: batteryInfo.virtualTemperatureC
        )
        thermal.cpuDisplayC = cpu.valueC
        thermal.cpuTemperatureSource = cpu.source
        thermal.cpuDieHotspotC = ThermalPolicy.isValidTemperature(cpuHotspot) ? cpuHotspot : nil
        thermal.cpuAverageC = cpuAverage.flatMap { ThermalPolicy.isValidTemperature($0) ? $0 : nil }
        thermal.ssdTemperatureC = sampleSSDTemperatureC()

        let fan = smcValue(conn: conn, key: "F0Ac")
        return (thermal, fan > 0 ? Int(fan.rounded()) : 0)
    }

    private func sampleSSDTemperatureC() -> Double? {
        let value = SSDTemperatureCelsius()
        return ThermalPolicy.isValidTemperature(value) ? value : nil
    }

    private func sampleTopProcesses() -> [ProcessSnapshot] {
        let result = Shell.run("/bin/ps", ["-axo", "%cpu,rss,pid,comm", "-r"], timeoutSeconds: 1.0)
        guard result.status == 0 else { return [] }

        return result.stdout
            .split(separator: "\n")
            .dropFirst()
            .prefix(12)
            .compactMap { line -> ProcessSnapshot? in
                let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard parts.count == 4,
                      let cpu = Double(parts[0]),
                      let rssKB = UInt64(parts[1]),
                      let pid = Int(parts[2]) else {
                    return nil
                }
                let name = URL(fileURLWithPath: String(parts[3])).lastPathComponent
                guard !name.lowercased().contains("thermomole") else { return nil }
                return ProcessSnapshot(pid: pid, name: name, cpuPercent: cpu, memoryBytes: rssKB * 1024)
            }
            .prefix(8)
            .map { $0 }
    }

    private func averageSMC(conn: io_connect_t, keys: [String]) -> Double? {
        let values = keys
            .map { smcValue(conn: conn, key: $0) }
            .filter(ThermalPolicy.isValidTemperature)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func smcValue(conn: io_connect_t, key: String) -> Double {
        key.withCString { SMCGetFloatValue(conn, $0) }
    }

    private func sysctlString(_ key: String) -> String {
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(key, &buffer, &size, nil, 0)
        let bytes = buffer
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func coreCount(named token: String) -> Int {
        let result = Shell.run("/usr/sbin/sysctl", ["-n",
                                                    "hw.perflevel0.logicalcpu",
                                                    "hw.perflevel0.name",
                                                    "hw.perflevel1.logicalcpu",
                                                    "hw.perflevel1.name"])
        guard result.status == 0 else { return 0 }
        let lines = result.stdout.split(separator: "\n").map { String($0).lowercased() }
        guard lines.count >= 4 else { return 0 }
        var count = 0
        for index in stride(from: 0, to: lines.count - 1, by: 2) {
            if lines[index + 1].contains(token) {
                count = Int(lines[index].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return count
    }

    private func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return loads
    }
}
