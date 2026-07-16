import Foundation
import MacnosisCore
import SwiftUI

struct MacnosisContentView: View {
    @ObservedObject var model: MacnosisAppModel
    let onQuit: () -> Void
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var headerHint: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspace
        }
        .background(MacnosisTheme.background)
        .dropDestination(for: URL.self) { urls, _ in
            model.inspect(urls)
            return urls.contains { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame || $0.hasDirectoryPath }
        } isTargeted: { isTargeted in
            model.isDropTargeted = isTargeted
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Macnosis")
                    .font(.system(size: 24, weight: .semibold))
                Text("Diagnose and repair macOS app bundles.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.activeInspectionCount > 0 {
                InspectionActivityView(
                    activeInspectionCount: model.activeInspectionCount,
                    activeLightWorkerCount: model.activeLightInspectionCommandCount,
                    lightWorkerCount: model.lightInspectionWorkerCount,
                    activeDeepWorkerCount: model.activeDeepInspectionCommandCount,
                    deepWorkerCount: model.deepInspectionWorkerCount
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Text(headerHint ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)
                .animation(.easeInOut(duration: 0.12), value: headerHint)

            HStack(spacing: 6) {
                ToolbarIconButton(
                    symbol: "folder.badge.plus",
                    label: "Inspect Apps",
                    onHoverLabel: setHeaderHint,
                    action: model.chooseApp
                )

                ToolbarIconButton(
                    symbol: "power",
                    label: "Quit Macnosis",
                    onHoverLabel: setHeaderHint,
                    action: onQuit
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .animation(.easeInOut(duration: 0.18), value: model.activeInspectionCount)
    }

    private func setHeaderHint(_ hint: String?) {
        headerHint = hint
    }

    @ViewBuilder
    private var workspace: some View {
        if model.inspectedApps.isEmpty {
            detailPane
        } else {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                inspectedAppsSidebar
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 440)
            } detail: {
                detailPane
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var inspectedAppsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspected Apps")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.inspectedApps) { app in
                        InspectedAppRow(
                            app: app,
                            isSelected: model.selectedAppID == app.id,
                            select: { model.selectApp(id: app.id) },
                            close: { model.closeApp(id: app.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let app = model.selectedApp {
            if let report = app.report {
                InspectionReportView(
                    app: app,
                    report: report,
                    clearQuarantine: { model.clearQuarantine(for: app.id) },
                    createDebuggableCopy: { model.createDebuggableCopy(for: app.id) },
                    repairDamagedInPlace: { model.repairDamagedInPlace(for: app.id) }
                )
            } else if app.isInspecting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Inspecting \(app.displayName)...")
                        .font(.system(size: 14, weight: .medium))
                    Text(app.url.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AppDropZone(
                    title: app.errorMessage ?? "Inspection blocked.",
                    message: "Drop more macOS .app bundles here, or choose one or more from the toolbar.",
                    isTargeted: model.isDropTargeted,
                    chooseApp: { model.chooseApp() }
                )
            }
        } else {
            AppDropZone(
                title: "Drop into a diagnosis.",
                message: "Choose or drop one or more macOS .app bundles to inspect signing, quarantine, architecture, and Gatekeeper state.",
                isTargeted: model.isDropTargeted,
                chooseApp: { model.chooseApp() }
            )
        }
    }
}

private struct ToolbarIconButton: View {
    let symbol: String
    let label: String
    var onHoverLabel: (String?) -> Void = { _ in }
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 22, height: 22)
            .frame(width: 34, height: 30)
            .background(isHovered ? MacnosisTheme.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
                onHoverLabel(hovering ? label : nil)
            }
            .onDisappear {
                onHoverLabel(nil)
            }
    }
}

private struct InspectionActivityView: View {
    let activeInspectionCount: Int
    let activeLightWorkerCount: Int
    let lightWorkerCount: Int
    let activeDeepWorkerCount: Int
    let deepWorkerCount: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(activeInspectionCount == 1 ? "Inspecting 1 app" : "Inspecting \(activeInspectionCount) apps")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.82))

            InspectionLaneIndicator(
                title: "Light",
                activeWorkerCount: activeLightWorkerCount,
                workerCount: lightWorkerCount,
                tint: MacnosisTheme.accent,
                barLimit: 8
            )

            InspectionLaneIndicator(
                title: "Deep",
                activeWorkerCount: activeDeepWorkerCount,
                workerCount: deepWorkerCount,
                tint: MacnosisTheme.neutral,
                barLimit: 4
            )
        }
        .quickTip("Light diagnostics run broadly; deep security checks are throttled.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activeInspectionCount) apps still inspecting. \(activeLightWorkerCount) of \(lightWorkerCount) light workers and \(activeDeepWorkerCount) of \(deepWorkerCount) deep workers are active.")
    }
}

private struct InspectionLaneIndicator: View {
    let title: String
    let activeWorkerCount: Int
    let workerCount: Int
    let tint: Color
    let barLimit: Int

    var body: some View {
        HStack(spacing: 6) {
            WorkerPulseView(activeWorkerCount: activeWorkerCount, workerCount: workerCount, tint: tint, barLimit: barLimit)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                Text("\(activeWorkerCount)/\(workerCount)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct WorkerPulseView: View {
    let activeWorkerCount: Int
    let workerCount: Int
    let tint: Color
    let barLimit: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.34)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.34)

            HStack(spacing: 2) {
                ForEach(0..<min(max(workerCount, 1), max(1, barLimit)), id: \.self) { index in
                    Capsule()
                        .fill(tint.opacity(opacity(for: index, phase: phase, activeWorkerCount: activeWorkerCount)))
                        .frame(width: 3, height: height(for: index, phase: phase))
                }
            }
            .frame(width: CGFloat(min(max(workerCount, 1), max(1, barLimit))) * 5, height: 12)
        }
    }

    private func opacity(for index: Int, phase: Int, activeWorkerCount: Int) -> Double {
        guard activeWorkerCount > 0 else {
            return 0.18
        }

        let isActiveSlot = index < activeWorkerCount
        let isPulsing = ((index + phase) % 8) < 3
        return isActiveSlot ? (isPulsing ? 0.78 : 0.42) : 0.18
    }

    private func height(for index: Int, phase: Int) -> CGFloat {
        ((index + phase) % 8) < 3 ? 11 : 6
    }
}

private struct InspectedAppRow: View {
    let app: InspectedApp
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            rowIdentity

            Spacer(minLength: 4)

            if app.isInspecting && app.report == nil {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close \(app.displayName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(isSelected ? MacnosisTheme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: select)
    }

    private var rowIdentity: some View {
        HStack(spacing: 10) {
            AppIconView(url: app.url, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: statusImage)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(statusColor)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1)
                        }
                        .offset(x: 3, y: 3)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                RowStatusLine(app: app)
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded(select)
        )
    }

    private var statusImage: String {
        if app.isInspecting && app.report == nil {
            return "clock"
        }

        return app.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if app.isInspecting && app.report == nil {
            return MacnosisTheme.accent
        }

        return app.hasWarning ? MacnosisTheme.warning : MacnosisTheme.good
    }
}

private struct AppDropZone: View {
    let title: String
    let message: String
    let isTargeted: Bool
    let chooseApp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: isTargeted ? "arrow.down.app.fill" : "stethoscope")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(isTargeted ? MacnosisTheme.good : MacnosisTheme.accent)

                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                Button {
                    chooseApp()
                } label: {
                    Label("Choose Apps", systemImage: "folder")
                }
                .controlSize(.large)
                .padding(.top, 2)
            }
            .padding(28)
            .frame(maxWidth: 560)
            .background(MacnosisTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isTargeted ? MacnosisTheme.good : MacnosisTheme.border, style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [7, 5]))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct RowStatusLine: View {
    let app: InspectedApp

    var body: some View {
        if let report = app.report {
            let architectures = Array(architectureBadges(for: report).prefix(1))
            let diagnostics = Array(diagnosticBadges(for: report).prefix(3))

            if architectures.isEmpty && diagnostics.isEmpty {
                Text(app.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    ForEach(architectures) { badge in
                        ArchitectureGlyph(badge: badge, size: .compact)
                    }

                    ForEach(diagnostics) { badge in
                        RowStatusIcon(badge: badge)
                    }
                }
                .lineLimit(1)
            }
        } else {
            Text(app.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct RowStatusIcon: View {
    let badge: DiagnosticBadge

    var body: some View {
        DiagnosticSymbol(symbol: badge.symbol, color: badge.color, size: 10, isCrossed: badge.isCrossed)
            .frame(width: 13, height: 13)
            .quickTip(badge.title)
    }
}

private struct InspectionReportView: View {
    let app: InspectedApp
    let report: AppInspectionReport
    let clearQuarantine: () -> Void
    let createDebuggableCopy: () -> Void
    let repairDamagedInPlace: () -> Void

    @State private var pendingAction: RepairAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary
                detailGrid
                diagnosticPanels
                if let actionMessage = app.actionMessage {
                    ActionMessageView(message: actionMessage.text, isError: actionMessage.isError)
                }
                technicalLogs
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if $0 == false { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.confirmTitle, role: pendingAction.role) {
                    run(pendingAction)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(pendingAction.message)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                AppIconView(url: report.bundleURL, size: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(packageName)
                        .font(.system(size: 26, weight: .semibold))

                    Text(report.bundleURL.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 24)
                DiagnosticChipStack(badges: diagnosticBadges(for: report))
            }
        }
    }

    private var detailGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 22, verticalSpacing: 10) {
            detailRow("Bundle ID", report.bundleIdentifier ?? "Unknown")
            detailRow("Bundle Name", report.bundleName)
            detailRow("Version", report.version ?? "Unknown")
            if let buildVersion = report.buildVersion, buildVersion != report.version {
                detailRow("Build", buildVersion)
            }
            if let builderSummary = report.builderSummary {
                detailRow("Built With", builderSummary)
            }
            detailRow("Executable", report.executableName ?? "Unknown")
            architectureRow
        }
        .font(.system(size: 13))
    }

    private var diagnosticPanels: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], alignment: .leading, spacing: 12) {
            DiagnosticPanel(
                symbol: signatureSymbol,
                title: "Code Signature",
                status: signatureStatusText,
                tone: signatureTone,
                message: signingMessage,
                actionTitle: report.signatureVerificationStatus == .invalid ? "Repair In Place" : nil,
                isWorking: app.isRepairing,
                action: { pendingAction = .repairDamagedInPlace }
            )

            DiagnosticPanel(
                symbol: developerIDSymbol,
                title: "Developer ID",
                status: developerIDStatusText,
                tone: developerIDTone,
                message: developerIDMessage,
                actionTitle: nil,
                isWorking: app.isRepairing,
                action: {}
            )

            DiagnosticPanel(
                symbol: gatekeeperSymbol,
                title: "Gatekeeper",
                status: gatekeeperStatusText,
                tone: gatekeeperTone,
                message: gatekeeperMessage,
                actionTitle: report.gatekeeperStatus == .rejected ? "Repair In Place" : nil,
                isWorking: app.isRepairing,
                action: { pendingAction = .repairDamagedInPlace }
            )

            DiagnosticPanel(
                symbol: quarantineSymbol,
                title: "Quarantine",
                status: quarantineStatusText,
                tone: quarantineTone,
                message: quarantineMessage,
                actionTitle: report.quarantineStatus == .quarantined ? "Clear Quarantine" : nil,
                isWorking: app.isRepairing,
                action: { pendingAction = .clearQuarantine }
            )

            DiagnosticPanel(
                symbol: debuggingSymbol,
                isSymbolCrossed: report.debuggingStatus == .notDebuggable,
                title: "Debugging",
                status: debuggingStatusText,
                tone: debuggingTone,
                message: debuggingMessage,
                actionTitle: report.canCreateDebuggableCopy ? "Create Debug Copy" : nil,
                isWorking: app.isRepairing,
                action: { pendingAction = .createDebuggableCopy }
            )
        }
    }

    private var technicalLogs: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                CommandLogSection(title: "Code Signing", result: report.signingDetails)
                CommandLogSection(title: "Entitlements", result: report.entitlements)
                CommandLogSection(title: "Strict Verification", result: report.signatureVerification)
                CommandLogSection(title: "Gatekeeper", result: report.gatekeeperAssessment)
                CommandLogSection(title: "Bundle Attributes", result: report.extendedAttributes)
            }
            .padding(.top, 10)
        } label: {
            Label("Technical Logs", systemImage: "terminal")
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private var architectureRow: some View {
        GridRow {
            Text("Architecture")
                .foregroundStyle(.secondary)
            switch report.executableFileDescriptionAvailability {
            case .available:
                ArchitecturePillStack(badges: architectureBadges(for: report))
            case .pending:
                Text("Checking")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("Unknown")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private var packageName: String {
        report.bundleURL.deletingPathExtension().lastPathComponent
    }

    private var signatureSymbol: String {
        switch report.signatureVerificationStatus {
        case .pending: "clock"
        case .valid: "checkmark.seal.fill"
        case .invalid: "signature"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var signatureStatusText: String {
        switch report.signatureVerificationStatus {
        case .pending: "Checking"
        case .valid: "Valid on disk"
        case .invalid: report.isUnsigned ? "Unsigned" : "Signature issue"
        case .unavailable: "Unavailable"
        }
    }

    private var signatureTone: DiagnosticTone {
        switch report.signatureVerificationStatus {
        case .pending, .unavailable: .neutral
        case .valid: .good
        case .invalid: .warning
        }
    }

    private var signingMessage: String {
        switch report.signatureVerificationStatus {
        case .pending:
            return "Strict code signature verification is still running."
        case .valid:
            return report.isAdHocSigned ? "The local ad-hoc signature is structurally valid." : "The bundle satisfies strict code signature verification."
        case .invalid:
            if report.isUnsigned {
                return "No code signature is present. Re-signing can create a local ad-hoc signature."
            }
            return "Strict verification confirmed a signature problem. Re-signing can repair stale or missing bundle seals."
        case .unavailable:
            return "Signature verification did not complete. Review the technical log before taking action."
        }
    }

    private var developerIDSymbol: String {
        switch report.signingDetailsAvailability {
        case .pending:
            return "clock"
        case .unavailable:
            return "questionmark.circle.fill"
        case .available:
            if report.hasDeveloperIDSignature {
                return "person.crop.circle.badge.checkmark"
            }

            return report.isAdHocSigned ? "signature" : "person.crop.circle.badge.xmark"
        }
    }

    private var developerIDStatusText: String {
        switch report.signingDetailsAvailability {
        case .pending:
            return "Checking"
        case .unavailable:
            return "Unavailable"
        case .available:
            if report.hasDeveloperIDSignature {
                return "Present"
            }

            if report.isUnsigned {
                return "Unsigned"
            }

            return report.isAdHocSigned ? "Ad-hoc only" : "Not present"
        }
    }

    private var developerIDTone: DiagnosticTone {
        switch report.signingDetailsAvailability {
        case .pending, .unavailable:
            return .neutral
        case .available:
            if report.hasDeveloperIDSignature {
                return .good
            }

            return report.isAdHocSigned ? .neutral : .warning
        }
    }

    private var developerIDMessage: String {
        switch report.signingDetailsAvailability {
        case .pending:
            return "Code signing identity details are still being read."
        case .unavailable:
            return "Code signing identity details could not be read. Review the technical log for the command failure."
        case .available:
            if report.isUnsigned {
                return "This bundle is unsigned, so it has no Developer ID distribution identity or TeamIdentifier."
            }

            if let authority = report.developerIDAuthority {
                if let teamIdentifier = report.teamIdentifier {
                    return "\(authority). TeamIdentifier \(teamIdentifier)."
                }

                return "\(authority). No TeamIdentifier was reported."
            }

            if report.isAdHocSigned {
                return "This bundle is ad-hoc signed for local use. It has no Developer ID distribution identity or TeamIdentifier."
            }

            return "No Developer ID Application certificate was found in the code signing details."
        }
    }

    private var gatekeeperSymbol: String {
        return switch report.gatekeeperStatus {
        case .pending: "clock"
        case .accepted: "checkmark.seal.fill"
        case .rejected: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var gatekeeperStatusText: String {
        return switch report.gatekeeperStatus {
        case .pending: "Checking"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        case .unknown: "Unknown"
        case .unavailable: "Unavailable"
        }
    }

    private var gatekeeperTone: DiagnosticTone {
        switch report.gatekeeperStatus {
        case .accepted: .good
        case .rejected: .warning
        case .pending, .unknown, .unavailable: .neutral
        }
    }

    private var gatekeeperMessage: String {
        switch report.gatekeeperStatus {
        case .pending:
            return "Gatekeeper assessment is still running."
        case .accepted:
            return "macOS trusts this app for normal launch."
        case .rejected:
            return "macOS does not trust this app for normal distribution or first launch."
        case .unknown:
            return "Gatekeeper did not return a clear accept/reject result."
        case .unavailable:
            return "Gatekeeper assessment did not complete. Review the technical log before taking action."
        }
    }

    private var quarantineSymbol: String {
        switch report.quarantineStatus {
        case .pending: "clock"
        case .quarantined: "lock.fill"
        case .clear: "lock.open.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var quarantineStatusText: String {
        switch report.quarantineStatus {
        case .pending: "Checking"
        case .quarantined: "Quarantined"
        case .clear: "Clear"
        case .unavailable: "Unavailable"
        }
    }

    private var quarantineTone: DiagnosticTone {
        switch report.quarantineStatus {
        case .pending, .unavailable: .neutral
        case .quarantined: .warning
        case .clear: .good
        }
    }

    private var quarantineMessage: String {
        switch report.quarantineStatus {
        case .pending:
            return "Extended attributes are still being read."
        case .quarantined:
            return "The app bundle has a downloaded-origin attribute that may trigger launch prompts."
        case .clear:
            return "No quarantine attribute was found on the app bundle itself."
        case .unavailable:
            return "The app bundle attributes could not be read. Quarantine state is unknown."
        }
    }

    private var debuggingStatusText: String {
        switch report.debuggingStatus {
        case .pending: "Checking"
        case .debuggable: "Attach allowed"
        case .notDebuggable: "Not debuggable"
        case .notApplicable: "Not applicable"
        case .malformed: "Unknown"
        case .unavailable: "Unavailable"
        }
    }

    private var debuggingSymbol: String {
        report.debuggingStatus == .notApplicable ? "minus.circle.fill" : "ladybug.fill"
    }

    private var debuggingTone: DiagnosticTone {
        switch report.debuggingStatus {
        case .debuggable: .debug
        case .pending, .notDebuggable, .notApplicable, .malformed, .unavailable: .neutral
        }
    }

    private var debuggingMessage: String {
        switch report.debuggingStatus {
        case .pending:
            return "Entitlements are still being read."
        case .debuggable:
            return "get-task-allow is true, so debugger and memory tools can attach more easily."
        case .notDebuggable:
            return "Create an ad-hoc signed copy with get-task-allow for local debugging."
        case .notApplicable:
            return "The declared executable is not Mach-O code, so debugger-attachment entitlements do not apply."
        case .malformed:
            return "The entitlement output was malformed, so attachability could not be determined."
        case .unavailable:
            return "Entitlements could not be read. Review the technical log before creating a modified copy."
        }
    }

    private func run(_ action: RepairAction) {
        pendingAction = nil
        switch action {
        case .clearQuarantine:
            clearQuarantine()
        case .createDebuggableCopy:
            createDebuggableCopy()
        case .repairDamagedInPlace:
            repairDamagedInPlace()
        }
    }
}

private struct DiagnosticChipStack: View {
    let badges: [DiagnosticBadge]

    var body: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(badges) { badge in
                DiagnosticChip(badge: badge)
            }
        }
        .frame(maxWidth: 420, alignment: .trailing)
    }
}

private enum DiagnosticTone {
    case good
    case warning
    case debug
    case neutral

    var color: Color {
        switch self {
        case .good: MacnosisTheme.good
        case .warning: MacnosisTheme.warning
        case .debug: MacnosisTheme.debug
        case .neutral: MacnosisTheme.neutral
        }
    }
}

private struct DiagnosticPanel: View {
    let symbol: String
    var isSymbolCrossed = false
    let title: String
    let status: String
    let tone: DiagnosticTone
    let message: String
    let actionTitle: String?
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 9) {
                DiagnosticSymbol(symbol: symbol, color: tone.color, size: 15, isCrossed: isSymbolCrossed)
                    .frame(width: 28, height: 28)
                    .background(tone.color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tone.color)
                        .lineLimit(1)
                }

                Spacer()
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle {
                Button {
                    action()
                } label: {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Working")
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
                .padding(.top, 1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(MacnosisTheme.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tone.color.opacity(0.14), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ActionMessageView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isError ? MacnosisTheme.warning : MacnosisTheme.good)
                .frame(width: 18)

            Text(shortMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? MacnosisTheme.warning : MacnosisTheme.good).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var shortMessage: String {
        if message.count <= 360 {
            return message
        }

        return String(message.prefix(360)) + "..."
    }
}

private enum RepairAction: Identifiable {
    case clearQuarantine
    case createDebuggableCopy
    case repairDamagedInPlace

    var id: String {
        switch self {
        case .clearQuarantine: "clear-quarantine"
        case .createDebuggableCopy: "create-debuggable-copy"
        case .repairDamagedInPlace: "repair-damaged-in-place"
        }
    }

    var title: String {
        switch self {
        case .clearQuarantine: "Clear quarantine attributes?"
        case .createDebuggableCopy: "Create a debuggable copy?"
        case .repairDamagedInPlace: "Repair this app in place?"
        }
    }

    var message: String {
        switch self {
        case .clearQuarantine:
            return "This removes com.apple.quarantine attributes from the selected app bundle. It does not re-sign the app."
        case .createDebuggableCopy:
            return "This creates a sibling -debug.app copy, adds get-task-allow, and signs the copy ad-hoc. The original app is not modified."
        case .repairDamagedInPlace:
            return "This re-signs the selected app in place ad-hoc and clears removable launch-blocking attributes. Original Developer ID notarization and TeamIdentifier will not be preserved."
        }
    }

    var confirmTitle: String {
        switch self {
        case .clearQuarantine: "Clear Quarantine"
        case .createDebuggableCopy: "Create Debug Copy"
        case .repairDamagedInPlace: "Repair In Place"
        }
    }

    var role: ButtonRole? {
        switch self {
        case .clearQuarantine, .createDebuggableCopy:
            return nil
        case .repairDamagedInPlace:
            return .destructive
        }
    }
}

private struct ArchitecturePillStack: View {
    let badges: [ArchitectureBadge]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges) { badge in
                ArchitecturePill(badge: badge)
            }
        }
    }
}

private struct ArchitecturePill: View {
    let badge: ArchitectureBadge

    var body: some View {
        HStack(spacing: 7) {
            ArchitectureGlyph(badge: badge, size: .regular)
            Text(badge.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(badge.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .quickTip(badge.help)
    }
}

private struct ArchitectureGlyph: View {
    enum Size {
        case compact
        case regular

        var textSize: CGFloat {
            switch self {
            case .compact: 9
            case .regular: 11
            }
        }

        var width: CGFloat {
            switch self {
            case .compact: 19
            case .regular: 22
            }
        }

        var height: CGFloat {
            switch self {
            case .compact: 14
            case .regular: 18
            }
        }
    }

    let badge: ArchitectureBadge
    let size: Size

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .background(size == .compact ? Color.clear : badge.color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(badge.color)
            .quickTip(size == .compact ? badge.title : badge.help)
    }

    @ViewBuilder
    private var content: some View {
        if size == .compact {
            Text(badge.glyph)
                .font(.system(size: size.textSize, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        } else {
            Image(systemName: "cpu")
                .font(.system(size: size.textSize, weight: .semibold))
        }
    }
}

private struct DiagnosticChip: View {
    let badge: DiagnosticBadge

    var body: some View {
        HStack(spacing: 5) {
            DiagnosticSymbol(symbol: badge.symbol, color: badge.color, size: 11, isCrossed: badge.isCrossed)
            Text(badge.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(badge.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(badge.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .quickTip(badge.help)
    }
}

private struct DiagnosticBadge: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let help: String
    let color: Color
    let isCrossed: Bool

    init(id: String, symbol: String, title: String, help: String, color: Color, isCrossed: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.help = help
        self.color = color
        self.isCrossed = isCrossed
    }
}

private struct DiagnosticSymbol: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    let isCrossed: Bool

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)

            if isCrossed {
                Capsule()
                    .fill(color)
                    .frame(width: size * 1.45, height: max(1.25, size * 0.14))
                    .rotationEffect(.degrees(-42))
            }
        }
        .frame(width: size * 1.25, height: size * 1.25)
    }
}

private struct ArchitectureBadge: Identifiable {
    let id: String
    let glyph: String
    let title: String
    let help: String
    let color: Color
}

private func diagnosticBadges(for report: AppInspectionReport) -> [DiagnosticBadge] {
    var badges: [DiagnosticBadge] = []

    if report.debuggingStatus == .debuggable || report.debuggingStatus == .notDebuggable {
        badges.append(
            report.debuggingStatus == .debuggable
                ? DiagnosticBadge(
                    id: "debuggable",
                    symbol: "ladybug.fill",
                    title: "Debuggable",
                    help: "The app has com.apple.security.get-task-allow and can be attached to by debugging tools.",
                    color: MacnosisTheme.debug
                )
                : DiagnosticBadge(
                    id: "non-debuggable",
                    symbol: "ladybug.fill",
                    title: "Non-debuggable",
                    help: "get-task-allow is not present, so debugger and memory tools may not be able to attach.",
                    color: MacnosisTheme.neutral,
                    isCrossed: true
                )
        )
    }

    switch report.gatekeeperStatus {
        case .accepted:
            badges.append(
                DiagnosticBadge(
                    id: "gatekeeper-accepted",
                    symbol: "checkmark.seal.fill",
                    title: "Gatekeeper Accepted",
                    help: "Gatekeeper accepts this app for launch.",
                    color: MacnosisTheme.good
                )
            )
        case .rejected:
            badges.append(
                DiagnosticBadge(
                    id: "gatekeeper-rejected",
                    symbol: "xmark.octagon.fill",
                    title: "Gatekeeper Rejected",
                    help: "Gatekeeper does not trust this app for normal launch/distribution.",
                    color: MacnosisTheme.warning
                )
            )
        case .unknown:
            badges.append(
                DiagnosticBadge(
                    id: "gatekeeper-unknown",
                    symbol: "questionmark.circle.fill",
                    title: "Gatekeeper Unknown",
                    help: "Gatekeeper assessment did not clearly accept or reject the app.",
                    color: MacnosisTheme.neutral
                )
            )
        case .pending, .unavailable:
            break
    }

    if report.quarantineStatus == .quarantined {
        badges.append(
            DiagnosticBadge(
                id: "quarantined",
                symbol: "lock.fill",
                title: "Quarantined",
                help: "The bundle still has com.apple.quarantine attributes.",
                color: MacnosisTheme.warning
            )
        )
    }

    if report.hasSigningDetails && report.isAdHocSigned {
        badges.append(
            DiagnosticBadge(
                id: "ad-hoc",
                symbol: "signature",
                title: "Ad-hoc Signed",
                help: "The app is locally/ad-hoc signed rather than signed with a Developer ID identity.",
                color: MacnosisTheme.neutral
            )
        )
    } else if report.hasSigningDetails && report.hasDeveloperIDSignature {
        badges.append(
            DiagnosticBadge(
                id: "developer-id",
                symbol: "person.crop.circle.badge.checkmark",
                title: "Developer ID",
                help: "The app is signed with a Developer ID Application certificate.",
                color: MacnosisTheme.good
            )
        )
    }

    if report.signatureVerificationStatus == .invalid {
        badges.append(
            DiagnosticBadge(
                id: report.isUnsigned ? "unsigned" : "signature-issue",
                symbol: report.isUnsigned ? "signature" : "exclamationmark.triangle.fill",
                title: report.isUnsigned ? "Unsigned" : "Signature Issue",
                help: report.isUnsigned
                    ? "No code signature is present."
                    : "Strict code signature verification failed.",
                color: MacnosisTheme.warning
            )
        )
    }

    return badges
}

private func architectureBadges(for report: AppInspectionReport) -> [ArchitectureBadge] {
    guard report.hasExecutableFileDescription else {
        return []
    }

    return report.architectures.map { architecture in
        switch architecture {
        case .universal:
            ArchitectureBadge(
                id: "architecture-universal",
                glyph: "UNI",
                title: "Universal",
                help: "Universal binary. \(report.architectureSummary)",
                color: MacnosisTheme.accent
            )
        case .appleSilicon:
            ArchitectureBadge(
                id: "architecture-apple-silicon",
                glyph: "ARM",
                title: "Apple Silicon",
                help: "Apple Silicon binary. \(report.architectureSummary)",
                color: MacnosisTheme.good
            )
        case .intel64:
            ArchitectureBadge(
                id: "architecture-intel-64",
                glyph: "x64",
                title: "Intel 64-bit",
                help: "Intel 64-bit binary. \(report.architectureSummary)",
                color: MacnosisTheme.neutral
            )
        case .intel32:
            ArchitectureBadge(
                id: "architecture-intel-32",
                glyph: "x32",
                title: "Intel 32-bit",
                help: "Legacy Intel 32-bit binary. \(report.architectureSummary)",
                color: MacnosisTheme.warning
            )
        case .script:
            ArchitectureBadge(
                id: "architecture-script",
                glyph: "SH",
                title: "Launcher Script",
                help: "Script executable rather than a Mach-O binary. \(report.architectureSummary)",
                color: MacnosisTheme.neutral
            )
        case .nonMachO:
            ArchitectureBadge(
                id: "architecture-non-mach-o",
                glyph: "TXT",
                title: "Non-Mach-O Executable",
                help: "Executable is not a Mach-O binary. \(report.architectureSummary)",
                color: MacnosisTheme.neutral
            )
        case .unknown:
            ArchitectureBadge(
                id: "architecture-unknown",
                glyph: "?",
                title: "Unknown Architecture",
                help: "Macnosis could not determine the executable architecture. \(report.architectureSummary)",
                color: MacnosisTheme.neutral
            )
        }
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(proposal: proposal, subviews: subviews)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.maxX - row.width + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [FlowRow] = []
        var current = FlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + horizontalSpacing + size.width

            if nextWidth > maxWidth, current.items.isEmpty == false {
                rows.append(current)
                current = FlowRow(y: current.y + current.height + verticalSpacing)
            }

            let x = current.items.isEmpty ? 0 : current.width + horizontalSpacing
            current.items.append(FlowItem(index: index, x: x, size: size))
            current.width = current.items.isEmpty ? size.width : x + size.width
            current.height = max(current.height, size.height)
        }

        if current.items.isEmpty == false {
            rows.append(current)
        }

        return rows
    }
}

private struct FlowRow {
    var items: [FlowItem] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
    var y: CGFloat = 0
}

private struct FlowItem {
    let index: Int
    let x: CGFloat
    let size: CGSize
}

private extension View {
    func quickTip(_ text: String, delayMilliseconds: Int = 240) -> some View {
        modifier(QuickTipModifier(text: text, delayMilliseconds: delayMilliseconds))
    }
}

private struct QuickTipModifier: ViewModifier {
    let text: String
    let delayMilliseconds: Int

    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                updateHover(hovering)
            }
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(MacnosisTheme.panel)
            }
            .onDisappear {
                hoverTask?.cancel()
                isPresented = false
            }
    }

    private func updateHover(_ hovering: Bool) {
        hoverTask?.cancel()
        guard hovering else {
            withAnimation(.easeInOut(duration: 0.08)) {
                isPresented = false
            }
            return
        }

        hoverTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, delayMilliseconds)) * 1_000_000)
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }

            withAnimation(.easeInOut(duration: 0.10)) {
                isPresented = true
            }
        }
    }
}

private struct CommandLogSection: View {
    let title: String
    let result: CommandResult?

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let result {
                    Text(result.command.joined(separator: " "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text(fullOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Text("Still running.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: logSymbol)
                    .foregroundStyle(logColor)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(logStatus)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(logColor)
            }
        }
        .padding(10)
        .background(MacnosisTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fullOutput: String {
        guard let result else {
            return "Still running."
        }

        return result.combinedOutput.isEmpty ? "No output." : result.combinedOutput
    }

    private var logStatus: String {
        guard let result else {
            return "pending"
        }

        let status = switch result.termination {
        case .exited(let exitCode):
            "exit \(exitCode)"
        case .timedOut:
            "timed out"
        case .cancelled:
            "cancelled"
        case .failedToLaunch:
            "unavailable"
        }

        guard let duration = result.duration else {
            return status
        }
        return "\(status), \(formatted(duration: duration))"
    }

    private func formatted(duration: TimeInterval) -> String {
        if duration < 0.001 {
            return "<1 ms"
        }
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }
        return String(format: "%.1f s", duration)
    }

    private var logColor: Color {
        guard let result else {
            return MacnosisTheme.neutral
        }

        return result.succeeded ? MacnosisTheme.good : MacnosisTheme.warning
    }

    private var logSymbol: String {
        guard let result else {
            return "clock"
        }

        switch result.termination {
        case .exited(0):
            return "checkmark.circle.fill"
        case .exited:
            return "exclamationmark.triangle.fill"
        case .timedOut:
            return "clock.badge.exclamationmark"
        case .cancelled:
            return "xmark.circle"
        case .failedToLaunch:
            return "questionmark.circle.fill"
        }
    }
}
