import Foundation
import Darwin
import XCTest
@testable import MacnosisCore

final class CommandExecutorTests: XCTestCase {
    func testLargeOutputCannotDeadlockAndIsBounded() {
        let executor = CommandExecutor(outputLimitBytes: 128 * 1_024)
        let script = "i=0; while [ $i -lt 20000 ]; do printf '0123456789abcdef0123456789abcdef\\n'; i=$((i+1)); done"

        let result = executor.run(["/bin/sh", "-c", script], timeout: 10)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.standardOutputWasTruncated)
        XCTAssertTrue(result.standardOutput.contains("[Output truncated after 131072 bytes.]"))
    }

    func testTimeoutHasExplicitTerminationState() async throws {
        let executor = CommandExecutor(terminationGracePeriod: 0.1)
        let startedAt = Date()

        let result = executor.run(
            ["/bin/sh", "-c", "sleep 5 & child=$!; printf '%s\\n' \"$child\"; wait \"$child\""],
            timeout: 0.1
        )

        XCTAssertEqual(result.termination, .timedOut(seconds: 1))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        XCTAssertTrue(result.standardError.contains("Command timed out"))
        let childPID = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(childPID)
        if let childPID {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while isProcessRunning(childPID), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertFalse(isProcessRunning(childPID), "Timed-out child process \(childPID) was still running")
        }
    }

    func testLaunchFailureHasExplicitTerminationState() {
        let result = CommandExecutor().run(["/definitely/missing/macnosis-command"], timeout: 1)

        XCTAssertEqual(result.termination, .failedToLaunch)
        XCTAssertFalse(result.didExit)
    }

    func testCancellationTerminatesTheProcessTree() async throws {
        let executor = CommandExecutor(terminationGracePeriod: 0.1)
        let startedAt = Date()
        let task = Task.detached {
            executor.run(
                ["/bin/sh", "-c", "sleep 10 & child=$!; printf '%s\\n' \"$child\"; wait \"$child\""],
                timeout: 20
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result.termination, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        XCTAssertTrue(result.standardError.contains("Command was cancelled"))
        let childPID = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(childPID)
        if let childPID {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while isProcessRunning(childPID), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertFalse(isProcessRunning(childPID), "Cancelled child process \(childPID) was still running")
        }
    }

    private func isProcessRunning(_ processID: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.size
        let actualSize = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, pointer, Int32(expectedSize))
        }
        guard actualSize == expectedSize else {
            return false
        }

        return info.pbi_status != UInt32(SZOMB)
    }
}
