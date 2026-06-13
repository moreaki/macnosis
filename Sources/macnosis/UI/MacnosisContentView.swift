import MacnosisCore
import SwiftUI

struct MacnosisContentView: View {
    @ObservedObject var model: MacnosisAppModel
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspace
        }
        .background(MacnosisTheme.background)
        .dropDestination(for: URL.self) { urls, _ in
            model.inspect(urls)
            return urls.contains { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame }
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

            ToolbarIconButton(
                symbol: "folder.badge.plus",
                label: "Inspect Apps",
                action: model.chooseApp
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
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
            if app.isInspecting {
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
            } else if let report = app.report {
                InspectionReportView(report: report)
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
        .help(label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct InspectedAppRow: View {
    let app: InspectedApp
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
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

            Spacer(minLength: 4)

            if app.isInspecting {
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

    private var statusImage: String {
        if app.isInspecting {
            return "clock"
        }

        return app.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if app.isInspecting {
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
            HStack(spacing: 6) {
                ForEach(Array(architectureBadges(for: report).prefix(1))) { badge in
                    ArchitectureGlyph(badge: badge, size: .compact)
                }

                ForEach(Array(diagnosticBadges(for: report).prefix(3))) { badge in
                    RowStatusIcon(badge: badge)
                }
            }
            .lineLimit(1)
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
        Image(systemName: badge.symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(badge.color)
            .frame(width: 13, height: 13)
            .quickTip(badge.title)
    }
}

private struct InspectionReportView: View {
    let report: AppInspectionReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                detailGrid
                CommandSection(title: "Code Signing", result: report.signingDetails)
                    .id(report.bundleURL.path + "-signing")
                CommandSection(title: "Entitlements", result: report.entitlements)
                    .id(report.bundleURL.path + "-entitlements")
                CommandSection(title: "Strict Verification", result: report.signatureVerification)
                    .id(report.bundleURL.path + "-verification")
                CommandSection(title: "Gatekeeper", result: report.gatekeeperAssessment)
                    .id(report.bundleURL.path + "-gatekeeper")
                CommandSection(title: "Extended Attributes", result: report.extendedAttributes)
                    .id(report.bundleURL.path + "-attributes")
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .leading)
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
            if report.bundleName != packageName {
                detailRow("Bundle Name", report.bundleName)
            }
            detailRow("Version", report.version ?? "Unknown")
            detailRow("Executable", report.executableName ?? "Unknown")
            architectureRow
        }
        .font(.system(size: 13))
    }

    private var architectureRow: some View {
        GridRow {
            Text("Architecture")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ArchitecturePillStack(badges: architectureBadges(for: report))
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
        .padding(.vertical, 7)
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
            Image(systemName: badge.symbol)
                .font(.system(size: 11, weight: .semibold))
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

    if report.isDebuggable {
        badges.append(
            DiagnosticBadge(
                id: "debuggable",
                symbol: "ladybug.fill",
                title: "Debuggable",
                help: "The app has com.apple.security.get-task-allow and can be attached to by debugging tools.",
                color: MacnosisTheme.debug
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
    }

    if report.isQuarantined {
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

    if report.isAdHocSigned {
        badges.append(
            DiagnosticBadge(
                id: "ad-hoc",
                symbol: "signature",
                title: "Ad-hoc Signed",
                help: "The app is locally/ad-hoc signed rather than signed with a Developer ID identity.",
                color: MacnosisTheme.neutral
            )
        )
    } else if report.hasDeveloperIDSignature {
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

    if report.isSignatureValid == false {
        badges.append(
            DiagnosticBadge(
                id: "signature-issue",
                symbol: "exclamationmark.triangle.fill",
                title: "Signature Issue",
                help: "Strict code signature verification failed.",
                color: MacnosisTheme.warning
            )
        )
    }

    return badges
}

private func architectureBadges(for report: AppInspectionReport) -> [ArchitectureBadge] {
    report.architectures.map { architecture in
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

private struct CommandSection: View {
    let title: String
    let result: CommandResult

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("exit \(result.exitCode)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(result.exitCode == 0 ? MacnosisTheme.good : MacnosisTheme.warning)
            }

            Text(visibleOutput)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 8)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacnosisTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if canExpand {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "Show Less" : "Show Full Output", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Collapse command output." : "Expand the complete command output.")
            }
        }
    }

    private var visibleOutput: String {
        let output = fullOutput
        guard isExpanded == false else {
            return output
        }

        return outputPreview(output)
    }

    private var fullOutput: String {
        result.combinedOutput.isEmpty ? "No output." : result.combinedOutput
    }

    private var canExpand: Bool {
        fullOutput.count > maxPreviewCharacters
    }

    private func outputPreview(_ output: String) -> String {
        guard output.count > maxPreviewCharacters else {
            return output
        }

        let preview = String(output.prefix(maxPreviewCharacters))
        return preview + "\n..."
    }

    private var maxPreviewCharacters: Int {
        1600
    }
}
