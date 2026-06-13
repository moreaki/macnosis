import Foundation
import MacnosisCore

enum AppRepairOperation: Sendable {
    case clearQuarantine
    case createDebuggableCopy
    case repairDamagedInPlace
}

struct AppRepairService: Sendable {
    func run(_ operation: AppRepairOperation, appURL: URL) -> CommandResult {
        switch operation {
        case .clearQuarantine:
            return runCommand(["/usr/bin/xattr", "-dr", "com.apple.quarantine", appURL.path])
        case .createDebuggableCopy:
            guard let scriptURL = makeDebuggableScriptURL else {
                return missingScriptResult
            }
            return runCommand([scriptURL.path, appURL.path])
        case .repairDamagedInPlace:
            guard let scriptURL = makeDebuggableScriptURL else {
                return missingScriptResult
            }
            return runCommand([scriptURL.path, "--repair-damaged", appURL.path])
        }
    }

    func debuggableCopyURL(for appURL: URL) -> URL {
        let directory = appURL.deletingLastPathComponent()
        let baseName = appURL.deletingPathExtension().lastPathComponent
        return directory.appending(path: "\(baseName)-debug.app", directoryHint: .isDirectory)
    }

    private var makeDebuggableScriptURL: URL? {
        if let bundled = Bundle.main.url(forResource: "make-debuggable-app", withExtension: "sh") {
            return bundled
        }

        let sourceTree = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "scripts/make-debuggable-app.sh")
        return FileManager.default.fileExists(atPath: sourceTree.path) ? sourceTree : nil
    }

    private var missingScriptResult: CommandResult {
        CommandResult(
            command: ["scripts/make-debuggable-app.sh"],
            exitCode: 127,
            standardOutput: "",
            standardError: "Missing bundled repair script."
        )
    }

    private func runCommand(_ command: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(
                command: command,
                exitCode: 127,
                standardOutput: "",
                standardError: String(describing: error)
            )
        }

        return CommandResult(
            command: command,
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            standardError: String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
