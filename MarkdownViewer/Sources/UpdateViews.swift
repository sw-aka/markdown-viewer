import SwiftUI

struct UpdateToolbarItem: View {
    @State private var updates = UpdateController.shared
    @State private var isPresented = false

    var body: some View {
        if updates.showsToolbarStatus || isPresented {
            Button { isPresented.toggle() } label: {
                HStack(spacing: 7) {
                    ZStack {
                        if updates.phase == .downloading || updates.phase == .extracting {
                            Circle().stroke(.secondary.opacity(0.25), lineWidth: 1.5)
                            if let progress = updates.progress {
                                Circle().trim(from: 0, to: progress)
                                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            } else {
                                ProgressView().controlSize(.mini)
                            }
                        } else {
                            Image(systemName: "arrow.up.circle").font(.system(size: 16))
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(status).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel(status)
            .help("Application updates")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { UpdatePopover(updates: updates) }
        }
    }

    private var status: String {
        switch updates.phase {
        case .readyToInstall: "Ready to install"
        case .downloading:
            if let progress = updates.progress { "Downloading \(Int(progress * 100))%" }
            else { "Downloading…" }
        case .extracting: "Preparing update…"
        case .installing: "Installing…"
        case .failed: "Update failed"
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .idle: "Software Update"
        case .available: "Update available"
        }
    }
}

struct UpdatePopover: View {
    @Bindable var updates: UpdateController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Software Update").font(.headline)
                Spacer()
                Text(updates.channel.title).font(.caption).foregroundStyle(.secondary)
            }
            switch updates.phase {
            case .idle, .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking for updates…") }
            case .available:
                if let release = updates.release {
                    Text("Markdown Viewer \(release.version)").font(.title3.bold())
                    Text("\(release.channel.title) update available").foregroundStyle(.secondary)
                    if !release.notes.isEmpty {
                        ScrollView { Text(release.notes).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 130)
                    }
                    Button("Download Update", action: updates.download).buttonStyle(.borderedProminent)
                    Text("Download now and install when you’re ready.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .upToDate:
                Label("No updates available", systemImage: "checkmark.circle")
                Text("You’re using Markdown Viewer \(updates.currentVersion).").foregroundStyle(.secondary)
            case .downloading, .extracting:
                Text(updates.message)
                if let progress = updates.progress { ProgressView(value: progress) }
                else { ProgressView() }
                if updates.phase == .downloading {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: updates.downloaded), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", action: updates.cancelDownload)
                    }
                }
                Text("You can keep writing while the update downloads.").font(.caption).foregroundStyle(.secondary)
            case .readyToInstall:
                Text("Ready to install").font(.title3.bold())
                if let release = updates.release {
                    Text("Version \(release.version) has been downloaded.").foregroundStyle(.secondary)
                }
                Text("Installing restarts Markdown Viewer. Your windows and unsaved work will be restored.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Install and Restart", action: updates.installAndRestart)
                    .buttonStyle(.borderedProminent)
            case .installing:
                ProgressView().controlSize(.small)
                Text(updates.message)
            case .failed:
                Label("Couldn’t update", systemImage: "exclamationmark.circle")
                Text(updates.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: updates.check)
            }
            Divider()
            HStack {
                Text("Current version: \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Update settings")
            }
        }
        .padding(20)
        .frame(width: 330)
    }
}

struct UpdateSettingsView: View {
    @State private var updates = UpdateController.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Form {
            Section("Updates") {
                Picker("Release channel", selection: $updates.channel) {
                    ForEach(UpdateChannel.allCases) { channel in Text(channel.title).tag(channel) }
                }
                .disabled(updates.isBusy || updates.hasPendingDownload)
                Toggle("Check for updates on launch", isOn: $updates.automaticChecks)
                Text(updates.channel == .stable
                     ? "Stable checks for newer Stable releases. Switching channels never installs an older version."
                     : "Development includes preview builds and newer Stable releases.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Check for Updates…") {
                    openWindow(id: "software-update")
                    updates.checkFromMenu()
                }
            }
            Section {
                LabeledContent("Version", value: updates.currentVersion)
                LabeledContent("Build", value: updates.buildChannel.capitalized)
                if let date = updates.lastChecked { LabeledContent("Last checked", value: date.formatted()) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 320)
        .padding()
    }
}
