import Foundation
import XCTest
@testable import MacnosisCore

final class NativeMetadataReadersTests: XCTestCase {
    func testInitialReportAcceptsUppercaseAppExtension() throws {
        let fixture = try AppFixture(appExtension: "APP")
        defer { fixture.remove() }

        let report = try AppBundleInspector().initialReport(bundleURL: fixture.appURL)
        XCTAssertEqual(report.bundleIdentifier, "example.macnosis.fixture")
    }

    func testMachOArchitectureAndSigningMetadataUseNativeReaders() throws {
        let fixture = try AppFixture()
        defer { fixture.remove() }

        let signingResult = CommandExecutor().run(
            ["/usr/bin/codesign", "--force", "--sign", "-", fixture.appURL.path],
            timeout: 10
        )
        XCTAssertTrue(signingResult.succeeded, signingResult.combinedOutput)

        let inspector = AppBundleInspector()
        var report = try inspector.initialReport(bundleURL: fixture.appURL)
        let architectureResult = inspector.run(.executableFileDescription, for: report)
        XCTAssertTrue(architectureResult.result.succeeded)
        XCTAssertEqual(
            architectureResult.result.command.first,
            "Foundation.Bundle.executableArchitectures"
        )
        XCTAssertTrue(architectureResult.result.standardOutput.contains("Mach-O"))
        report.apply(architectureResult)

        let metadataResult = inspector.run(.signingMetadata, for: report)
        XCTAssertTrue(metadataResult.result.succeeded, metadataResult.result.combinedOutput)
        XCTAssertEqual(metadataResult.result.command.first, "Security.framework")
        report.apply(metadataResult)

        XCTAssertEqual(report.signingDetailsAvailability, .available)
        XCTAssertTrue(report.isAdHocSigned)
        XCTAssertEqual(report.debuggingStatus, .notDebuggable)
        XCTAssertNotNil(report.signingDetails?.duration)
        XCTAssertNotNil(report.entitlements?.duration)
    }

    func testUnsignedMachOHasAvailableEmptyEntitlements() throws {
        let fixture = try AppFixture()
        defer { fixture.remove() }

        let removalResult = CommandExecutor().run(
            ["/usr/bin/codesign", "--remove-signature", fixture.executableURL.path],
            timeout: 10
        )
        XCTAssertTrue(removalResult.succeeded, removalResult.combinedOutput)

        let inspector = AppBundleInspector()
        var report = try inspector.initialReport(bundleURL: fixture.appURL)
        report.apply(inspector.run(.executableFileDescription, for: report))
        let metadataResult = inspector.run(.signingMetadata, for: report)
        report.apply(metadataResult)
        report.apply(inspector.run(.signatureVerification, for: report))

        XCTAssertTrue(metadataResult.result.succeeded, metadataResult.result.combinedOutput)
        XCTAssertTrue(report.isUnsigned)
        XCTAssertFalse(report.isAdHocSigned)
        XCTAssertEqual(report.signatureVerificationStatus, .invalid)
        XCTAssertEqual(report.debuggingStatus, .notDebuggable)
        XCTAssertTrue(report.canCreateDebuggableCopy)
        XCTAssertTrue(try entitlementDictionary(from: report.entitlements).isEmpty)
    }

    func testUnsignedScriptHasNotApplicableDebuggerEntitlements() throws {
        let fixture = try AppFixture(executableContents: "#!/bin/sh\nexit 0\n")
        defer { fixture.remove() }

        let inspector = AppBundleInspector()
        var report = try inspector.initialReport(bundleURL: fixture.appURL)
        report.apply(inspector.run(.executableFileDescription, for: report))
        report.apply(inspector.run(.signingMetadata, for: report))

        XCTAssertEqual(report.architectures, [.script])
        XCTAssertTrue(report.isUnsigned)
        XCTAssertEqual(report.debuggingStatus, .notApplicable)
        XCTAssertFalse(report.canCreateDebuggableCopy)
        XCTAssertTrue(try entitlementDictionary(from: report.entitlements).isEmpty)
    }

    func testMissingCodeRemainsAMetadataFailure() {
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "Missing-\(UUID().uuidString).app", directoryHint: .isDirectory)

        let result = CodeSigningMetadataReader().read(bundleURL: missingURL)

        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.standardError.contains("Signature=unsigned"))
    }

    func testBundleAttributesAvoidRecursiveTraversal() throws {
        let fixture = try AppFixture()
        defer { fixture.remove() }

        let nestedURL = fixture.appURL.appending(path: "Contents/Resources/Nested.txt")
        try FileManager.default.createDirectory(
            at: nestedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: nestedURL)

        let executor = CommandExecutor()
        let nestedAttribute = executor.run(
            ["/usr/bin/xattr", "-w", "com.example.nested", "value", nestedURL.path],
            timeout: 5
        )
        XCTAssertTrue(nestedAttribute.succeeded, nestedAttribute.combinedOutput)

        let rootAttribute = executor.run(
            ["/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;fixture", fixture.appURL.path],
            timeout: 5
        )
        XCTAssertTrue(rootAttribute.succeeded, rootAttribute.combinedOutput)

        let result = BundleAttributeReader().read(bundleURL: fixture.appURL)
        XCTAssertTrue(result.succeeded, result.combinedOutput)
        XCTAssertEqual(result.command, ["/usr/bin/xattr", "-l", fixture.appURL.path])
        XCTAssertTrue(result.standardOutput.contains("com.apple.quarantine"))
        XCTAssertFalse(result.standardOutput.contains("com.example.nested"))
    }

    func testStaticCodeValidatorRejectsAChangedSignedExecutable() throws {
        let fixture = try AppFixture()
        defer { fixture.remove() }

        let signingResult = CommandExecutor().run(
            ["/usr/bin/codesign", "--force", "--sign", "-", fixture.appURL.path],
            timeout: 10
        )
        XCTAssertTrue(signingResult.succeeded, signingResult.combinedOutput)

        let validator = StaticCodeSignatureValidator()
        let validResult = validator.validate(bundleURL: fixture.appURL)
        XCTAssertTrue(validResult.succeeded, validResult.combinedOutput)

        let executableHandle = try FileHandle(forWritingTo: fixture.executableURL)
        try executableHandle.seekToEnd()
        try executableHandle.write(contentsOf: Data([0]))
        try executableHandle.close()

        let invalidResult = validator.validate(bundleURL: fixture.appURL)
        XCTAssertFalse(invalidResult.succeeded)
        XCTAssertTrue(invalidResult.standardError.isEmpty == false)
    }

    func testStaticCodeValidatorRejectsChangedNestedCode() throws {
        let fixture = try AppFixture()
        defer { fixture.remove() }

        let nestedExecutableURL = fixture.appURL.appending(path: "Contents/Helpers/NestedTool")
        try FileManager.default.createDirectory(
            at: nestedExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"),
            to: nestedExecutableURL
        )

        let executor = CommandExecutor()
        let nestedSigningResult = executor.run(
            ["/usr/bin/codesign", "--force", "--sign", "-", nestedExecutableURL.path],
            timeout: 10
        )
        XCTAssertTrue(nestedSigningResult.succeeded, nestedSigningResult.combinedOutput)
        let appSigningResult = executor.run(
            ["/usr/bin/codesign", "--force", "--sign", "-", fixture.appURL.path],
            timeout: 10
        )
        XCTAssertTrue(appSigningResult.succeeded, appSigningResult.combinedOutput)

        let validator = StaticCodeSignatureValidator()
        let validResult = validator.validate(bundleURL: fixture.appURL)
        XCTAssertTrue(validResult.succeeded, validResult.combinedOutput)

        let nestedHandle = try FileHandle(forWritingTo: nestedExecutableURL)
        try nestedHandle.seekToEnd()
        try nestedHandle.write(contentsOf: Data([0]))
        try nestedHandle.close()

        let invalidResult = validator.validate(bundleURL: fixture.appURL)
        XCTAssertFalse(invalidResult.succeeded)
        XCTAssertTrue(invalidResult.standardError.contains(fixture.appURL.path))
    }

    func testSignatureVerificationReaderUsesAnInjectedHelper() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Fixture.app")
        let result = SignatureVerificationReader(helperURL: URL(fileURLWithPath: "/usr/bin/true"))
            .read(bundleURL: bundleURL, commandExecutor: CommandExecutor())

        XCTAssertTrue(result.succeeded, result.combinedOutput)
        XCTAssertEqual(result.command, ["/usr/bin/true", "verify", bundleURL.path])
    }

    func testSignatureVerificationReaderFallsBackAfterHelperFailure() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Fixture.app")
        let result = SignatureVerificationReader(helperURL: URL(fileURLWithPath: "/usr/bin/false"))
            .read(bundleURL: bundleURL, commandExecutor: CommandExecutor())

        XCTAssertEqual(result.command.first, "/usr/bin/codesign")
        XCTAssertNotNil(result.duration)
    }

    private func entitlementDictionary(from result: CommandResult?) throws -> [String: Any] {
        let result = try XCTUnwrap(result)
        XCTAssertTrue(result.succeeded, result.combinedOutput)
        let data = Data(result.standardOutput.utf8)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: Any])
    }
}

private struct AppFixture {
    let rootURL: URL
    let appURL: URL
    let executableURL: URL

    init(appExtension: String = "app", executableContents: String? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacnosisNativeMetadataTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        appURL = rootURL.appending(path: "Fixture.\(appExtension)", directoryHint: .isDirectory)
        executableURL = appURL.appending(path: "Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let executableContents {
            try Data(executableContents.utf8).write(to: executableURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
        } else {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executableURL)
        }

        let info: [String: Any] = [
            "CFBundleExecutable": "Fixture",
            "CFBundleIdentifier": "example.macnosis.fixture",
            "CFBundleName": "Fixture",
            "CFBundlePackageType": "APPL",
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: appURL.appending(path: "Contents/Info.plist"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
