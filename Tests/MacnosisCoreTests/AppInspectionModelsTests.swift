import Foundation
import XCTest
@testable import MacnosisCore

final class AppInspectionModelsTests: XCTestCase {
    func testGetTaskAllowMustBeBooleanTrue() throws {
        let enabled = report(entitlementsOutput: try plist(["com.apple.security.get-task-allow": true]))
        XCTAssertEqual(enabled.debuggingStatus, .debuggable)
        XCTAssertTrue(enabled.isDebuggable)

        let disabled = report(entitlementsOutput: try plist(["com.apple.security.get-task-allow": false]))
        XCTAssertEqual(disabled.debuggingStatus, .notDebuggable)
        XCTAssertFalse(disabled.isDebuggable)

        let stringValue = report(entitlementsOutput: try plist(["com.apple.security.get-task-allow": "true"]))
        XCTAssertEqual(stringValue.debuggingStatus, .notDebuggable)
        XCTAssertFalse(stringValue.isDebuggable)
    }

    func testMissingMalformedAndUnavailableEntitlementsRemainDistinct() throws {
        XCTAssertEqual(report(entitlementsOutput: try plist([:])).debuggingStatus, .notDebuggable)
        XCTAssertEqual(report(entitlementsOutput: "not a plist").debuggingStatus, .malformed)

        var unavailable = report()
        unavailable.entitlements = CommandResult(
            command: ["codesign"],
            termination: .timedOut(seconds: 10),
            standardOutput: "",
            standardError: "timed out"
        )
        XCTAssertEqual(unavailable.debuggingStatus, .unavailable)
    }

    func testUnavailableCommandsDoNotBecomeNegativeDiagnoses() {
        var report = report()
        report.signatureVerification = CommandResult(
            command: ["codesign"],
            termination: .timedOut(seconds: 45),
            standardOutput: "",
            standardError: "timed out"
        )
        report.extendedAttributes = CommandResult(
            command: ["xattr"],
            termination: .failedToLaunch,
            standardOutput: "",
            standardError: "missing"
        )
        report.gatekeeperAssessment = CommandResult(
            command: ["spctl"],
            termination: .timedOut(seconds: 60),
            standardOutput: "",
            standardError: "timed out"
        )

        XCTAssertEqual(report.signatureVerificationStatus, .unavailable)
        XCTAssertEqual(report.quarantineStatus, .unavailable)
        XCTAssertEqual(report.gatekeeperStatus, .unavailable)
        XCTAssertFalse(report.hasSignatureVerification)
        XCTAssertFalse(report.hasExtendedAttributes)
        XCTAssertFalse(report.hasGatekeeperAssessment)
    }

    func testExitedVerificationFailureIsStillAConfirmedInvalidSignature() {
        var report = report()
        report.signatureVerification = CommandResult(
            command: ["codesign"],
            exitCode: 1,
            standardOutput: "",
            standardError: "invalid signature"
        )

        XCTAssertEqual(report.signatureVerificationStatus, .invalid)
        XCTAssertTrue(report.hasSignatureVerification)
        XCTAssertFalse(report.isSignatureValid)
    }

    func testTruncatedExtendedAttributesCannotBeReportedClear() {
        var report = report()
        report.extendedAttributes = CommandResult(
            command: ["xattr"],
            exitCode: 0,
            standardOutput: "partial output",
            standardError: "",
            standardOutputWasTruncated: true
        )

        XCTAssertEqual(report.quarantineStatus, .unavailable)
        XCTAssertFalse(report.hasExtendedAttributes)
    }

    func testMissingTeamIdentifierDoesNotOverrideSignedAuthority() {
        var appleSigned = report()
        appleSigned.signingDetails = CommandResult(
            command: ["codesign"],
            exitCode: 0,
            standardOutput: "",
            standardError: "Signature=signed\nAuthority=Software Signing\nTeamIdentifier=not set"
        )
        XCTAssertFalse(appleSigned.isAdHocSigned)

        var adHoc = report()
        adHoc.signingDetails = CommandResult(
            command: ["codesign"],
            exitCode: 0,
            standardOutput: "",
            standardError: "Signature=adhoc\nTeamIdentifier=not set"
        )
        XCTAssertTrue(adHoc.isAdHocSigned)
    }

    private func report(entitlementsOutput: String? = nil) -> AppInspectionReport {
        AppInspectionReport(
            bundleURL: URL(fileURLWithPath: "/Applications/Fixture.app"),
            bundleName: "Fixture",
            bundleIdentifier: "example.fixture",
            version: "1",
            buildVersion: "1",
            bundleInfoString: nil,
            executableName: "Fixture",
            executableURL: URL(fileURLWithPath: "/Applications/Fixture.app/Contents/MacOS/Fixture"),
            executableFileDescription: nil,
            entitlements: entitlementsOutput.map {
                CommandResult(command: ["codesign"], exitCode: 0, standardOutput: $0, standardError: "")
            }
        )
    }

    private func plist(_ values: [String: Any]) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }
}
