import Darwin
import Foundation

public struct CommandExecutor: Sendable {
    public static let defaultOutputLimitBytes = 2 * 1_024 * 1_024

    private let outputLimitBytes: Int
    private let terminationGracePeriod: TimeInterval

    public init(
        outputLimitBytes: Int = CommandExecutor.defaultOutputLimitBytes,
        terminationGracePeriod: TimeInterval = 2
    ) {
        self.outputLimitBytes = max(1, outputLimitBytes)
        self.terminationGracePeriod = max(0, terminationGracePeriod)
    }

    public func run(_ command: [String], timeout: TimeInterval) -> CommandResult {
        guard let executable = command.first else {
            return CommandResult(
                command: command,
                termination: .failedToLaunch,
                standardOutput: "",
                standardError: "No executable was provided."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())

        let captureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Macnosis-\(UUID().uuidString)", directoryHint: .isDirectory)
        let standardOutputURL = captureDirectory.appending(path: "stdout.txt")
        let standardErrorURL = captureDirectory.appending(path: "stderr.txt")

        do {
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil),
                  FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
            else {
                throw CocoaError(.fileWriteUnknown)
            }

            let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
            let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
            defer {
                try? standardOutputHandle.close()
                try? standardErrorHandle.close()
                try? FileManager.default.removeItem(at: captureDirectory)
            }

            process.standardOutput = standardOutputHandle
            process.standardError = standardErrorHandle

            let terminationSemaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                terminationSemaphore.signal()
            }

            do {
                try process.run()
            } catch {
                return CommandResult(
                    command: command,
                    termination: .failedToLaunch,
                    standardOutput: "",
                    standardError: String(describing: error)
                )
            }

            let normalizedTimeout = max(0, timeout)
            let timedOut = terminationSemaphore.wait(timeout: .now() + normalizedTimeout) == .timedOut
            if timedOut {
                let processTree = processTreePIDs(rootPID: process.processIdentifier)
                signal(processTree: processTree, with: SIGTERM)

                let rootTimedOut = terminationSemaphore.wait(timeout: .now() + terminationGracePeriod) == .timedOut
                if rootTimedOut, process.isRunning {
                    signal(processTree: processTree, with: SIGKILL)
                    process.waitUntilExit()
                } else {
                    signal(processTree: Array(processTree.dropFirst()), with: SIGKILL)
                }
            }

            try standardOutputHandle.close()
            try standardErrorHandle.close()

            let capturedStandardOutput = try capturedOutput(at: standardOutputURL)
            let capturedStandardError = try capturedOutput(at: standardErrorURL)
            let standardOutput = capturedStandardOutput.text
            var standardError = capturedStandardError.text
            let termination: CommandTermination
            if timedOut {
                let seconds = max(0, Int(normalizedTimeout.rounded(.up)))
                let timeoutMessage = "Command timed out after \(seconds) seconds."
                standardError = [standardError, timeoutMessage]
                    .filter { $0.isEmpty == false }
                    .joined(separator: "\n")
                termination = .timedOut(seconds: seconds)
            } else {
                termination = .exited(process.terminationStatus)
            }

            return CommandResult(
                command: command,
                termination: termination,
                standardOutput: standardOutput,
                standardError: standardError,
                standardOutputWasTruncated: capturedStandardOutput.wasTruncated,
                standardErrorWasTruncated: capturedStandardError.wasTruncated
            )
        } catch {
            try? FileManager.default.removeItem(at: captureDirectory)
            return CommandResult(
                command: command,
                termination: .failedToLaunch,
                standardOutput: "",
                standardError: String(describing: error)
            )
        }
    }

    private func capturedOutput(at url: URL) throws -> CapturedOutput {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: outputLimitBytes + 1) ?? Data()
        let wasTruncated = data.count > outputLimitBytes
        let capturedData = data.prefix(outputLimitBytes)
        let captured = String(decoding: capturedData, as: UTF8.self)

        guard wasTruncated else {
            return CapturedOutput(text: captured, wasTruncated: false)
        }

        return CapturedOutput(
            text: captured + "\n[Output truncated after \(outputLimitBytes) bytes.]",
            wasTruncated: true
        )
    }

    private func processTreePIDs(rootPID: pid_t) -> [pid_t] {
        var result = [rootPID]
        var seen = Set(result)
        var index = 0
        while index < result.count {
            for childPID in childPIDs(of: result[index]) where seen.insert(childPID).inserted {
                result.append(childPID)
            }
            index += 1
        }
        return result
    }

    private func childPIDs(of parentPID: pid_t) -> [pid_t] {
        var capacity = 16
        let maximumCapacity = 32_768

        while true {
            var children = [pid_t](repeating: 0, count: capacity)
            let childCount = children.withUnsafeMutableBytes { buffer in
                proc_listchildpids(parentPID, buffer.baseAddress, Int32(buffer.count))
            }
            guard childCount > 0 else {
                return []
            }

            let capturedCount = min(Int(childCount), children.count)
            let capturedChildren = Array(children.prefix(capturedCount)).filter { $0 > 0 }
            guard childCount >= capacity, capacity < maximumCapacity else {
                return capturedChildren
            }

            capacity = min(max(capacity * 2, Int(childCount)), maximumCapacity)
        }
    }

    private func signal(processTree: [pid_t], with signal: Int32) {
        for processID in processTree.reversed() {
            kill(processID, signal)
        }
    }
}

private struct CapturedOutput {
    let text: String
    let wasTruncated: Bool
}
