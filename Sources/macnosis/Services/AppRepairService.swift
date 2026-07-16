import Foundation
import MacnosisCore

enum AppRepairOperation: Sendable {
    case clearQuarantine
    case createDebuggableCopy
    case repairDamagedInPlace
}

protocol AppRepairServicing: Sendable {
    func run(_ operation: AppRepairOperation, appURL: URL) -> CommandResult
    func debuggableCopyURL(for appURL: URL) -> URL
}

struct AppRepairService: Sendable {
    private let commandExecutor: CommandExecutor
    private let quarantineTimeout: TimeInterval
    private let signingTimeout: TimeInterval

    init(
        commandExecutor: CommandExecutor = CommandExecutor(),
        quarantineTimeout: TimeInterval = 60,
        signingTimeout: TimeInterval = 300
    ) {
        self.commandExecutor = commandExecutor
        self.quarantineTimeout = quarantineTimeout
        self.signingTimeout = signingTimeout
    }

    func run(_ operation: AppRepairOperation, appURL: URL) -> CommandResult {
        switch operation {
        case .clearQuarantine:
            return commandExecutor.run(
                ["/usr/bin/xattr", "-dr", "com.apple.quarantine", appURL.path],
                timeout: quarantineTimeout
            )
        case .createDebuggableCopy:
            guard let scriptURL = makeDebuggableScriptURL else {
                return missingScriptResult
            }
            return commandExecutor.run([scriptURL.path, appURL.path], timeout: signingTimeout)
        case .repairDamagedInPlace:
            guard let scriptURL = makeDebuggableScriptURL else {
                return missingScriptResult
            }
            return commandExecutor.run(
                [scriptURL.path, "--repair-damaged", appURL.path],
                timeout: signingTimeout
            )
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
            termination: .failedToLaunch,
            standardOutput: "",
            standardError: "Missing bundled repair script."
        )
    }
}

extension AppRepairService: AppRepairServicing {}
