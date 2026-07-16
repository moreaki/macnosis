import Foundation
import XCTest

final class RepairScriptTests: XCTestCase {
    func testDebugCopyPreservesNestedEntitlementsAndOnlyDebugsMainApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisRepairTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sourceApp = root.appending(path: "Source.app", directoryHint: .isDirectory)
        let outputApp = root.appending(path: "Output.app", directoryHint: .isDirectory)
        let sourceExecutable = sourceApp.appending(path: "Contents/MacOS/Main")
        let helperBundle = sourceApp.appending(path: "Contents/XPCServices/Helper.xpc", directoryHint: .isDirectory)
        let helperExecutable = helperBundle.appending(path: "Contents/MacOS/Helper")
        try createBundle(
            at: sourceApp,
            executableURL: sourceExecutable,
            identifier: "example.source",
            packageType: "APPL"
        )
        try createBundle(
            at: helperBundle,
            executableURL: helperExecutable,
            identifier: "example.helper",
            packageType: "XPC!"
        )

        let rootEntitlements = root.appending(path: "root-entitlements.plist")
        let helperEntitlements = root.appending(path: "helper-entitlements.plist")
        try writePlist(["com.example.root": true], to: rootEntitlements)
        try writePlist([
            "com.example.helper": true,
            "com.apple.security.get-task-allow": false,
        ], to: helperEntitlements)

        try run(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", helperEntitlements.path, helperBundle.path])
        try run(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", rootEntitlements.path, sourceApp.path])
        try run([repairScriptURL.path, sourceApp.path, outputApp.path])
        try run(["/usr/bin/codesign", "--verify", "--deep", "--strict", outputApp.path])

        let outputRootEntitlements = try readEntitlements(from: outputApp)
        let outputHelperEntitlements = try readEntitlements(
            from: outputApp.appending(path: "Contents/XPCServices/Helper.xpc", directoryHint: .isDirectory)
        )
        XCTAssertEqual(outputRootEntitlements["com.example.root"] as? Bool, true)
        XCTAssertEqual(outputRootEntitlements["com.apple.security.get-task-allow"] as? Bool, true)
        XCTAssertEqual(outputHelperEntitlements["com.example.helper"] as? Bool, true)
        XCTAssertEqual(outputHelperEntitlements["com.apple.security.get-task-allow"] as? Bool, false)
    }

    func testDebugCopyRejectsScriptExecutableBeforeCopying() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisScriptRepairTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceApp = root.appending(path: "Source.app", directoryHint: .isDirectory)
        let outputApp = root.appending(path: "Output.app", directoryHint: .isDirectory)
        let executableURL = sourceApp.appending(path: "Contents/MacOS/run.sh")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try writePlist([
            "CFBundleExecutable": executableURL.lastPathComponent,
            "CFBundleIdentifier": "example.script",
            "CFBundleName": "Script",
            "CFBundlePackageType": "APPL",
        ], to: sourceApp.appending(path: "Contents/Info.plist"))

        let result = try execute([repairScriptURL.path, sourceApp.path, outputApp.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.standardError.contains("debugger entitlements require a Mach-O app executable"),
            result.standardError
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputApp.path))
    }

    private var repairScriptURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "scripts/make-debuggable-app.sh")
    }

    private func createBundle(
        at bundleURL: URL,
        executableURL: URL,
        identifier: String,
        packageType: String
    ) throws {
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executableURL)
        try writePlist([
            "CFBundleExecutable": executableURL.lastPathComponent,
            "CFBundleIdentifier": identifier,
            "CFBundleName": executableURL.lastPathComponent,
            "CFBundlePackageType": packageType,
        ], to: bundleURL.appending(path: "Contents/Info.plist"))
    }

    private func writePlist(_ value: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        try data.write(to: url)
    }

    private func readEntitlements(from codeURL: URL) throws -> [String: Any] {
        let result = try run(["/usr/bin/codesign", "-d", "--xml", "--entitlements", "-", codeURL.path])
        let propertyList = try PropertyListSerialization.propertyList(from: result, format: nil)
        return try XCTUnwrap(propertyList as? [String: Any])
    }

    @discardableResult
    private func run(_ command: [String]) throws -> Data {
        let result = try execute(command)
        XCTAssertEqual(
            result.exitCode,
            0,
            String(decoding: result.standardOutput, as: UTF8.self) + result.standardError
        )
        return result.standardOutput
    }

    private func execute(_ command: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: String(decoding: error, as: UTF8.self)
        )
    }
}

private struct ProcessResult {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: String
}
