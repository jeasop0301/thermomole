import Foundation

/// Human-readable byte size. Shared by GUI, CLI, and app-layer models.
public func formatBytes(_ value: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var amount = Double(value)
    var index = 0
    while amount >= 1024, index < units.count - 1 {
        amount /= 1024
        index += 1
    }
    return index == 0 ? "\(Int(amount)) \(units[index])" : String(format: "%.1f %@", amount, units[index])
}
