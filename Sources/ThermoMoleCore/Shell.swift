import Foundation
import Darwin

public struct ShellResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

public enum Shell {
    public static func run(
        _ executable: String,
        _ arguments: [String] = [],
        timeoutSeconds: TimeInterval? = nil
    ) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            let stdoutReader = PipeReader(pipe: outPipe)
            let stderrReader = PipeReader(pipe: errPipe)
            stdoutReader.start()
            stderrReader.start()

            if let timeoutSeconds {
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }

                if process.isRunning {
                    process.terminate()
                    Thread.sleep(forTimeInterval: 0.05)
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                    process.waitUntilExit()
                    return ShellResult(
                        status: 124,
                        stdout: stdoutReader.text(),
                        stderr: "Timed out after \(timeoutSeconds) seconds."
                    )
                }
            } else {
                process.waitUntilExit()
            }

            return ShellResult(
                status: process.terminationStatus,
                stdout: stdoutReader.text(),
                stderr: stderrReader.text()
            )
        } catch {
            return ShellResult(status: 127, stdout: "", stderr: String(describing: error))
        }
    }
}

private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()
    private var started = false

    init(pipe: Pipe) {
        self.pipe = pipe
    }

    func start() {
        guard !started else { return }
        started = true
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let next = self.pipe.fileHandleForReading.readDataToEndOfFile()
            self.lock.lock()
            self.data = next
            self.lock.unlock()
            self.group.leave()
        }
    }

    func text() -> String {
        guard started else { return "" }
        group.wait()
        lock.lock()
        let next = data
        lock.unlock()
        return String(data: next, encoding: .utf8) ?? ""
    }
}
