import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ISOFix").font(.title2.bold())
                        Text("macOS often swaps § and < on third-party ISO keyboards. ISOFix catches it the first time you press one, and fixes that keyboard from then on.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            if !model.monitoring {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input Monitoring needed").bold()
                            Text(model.permissionGranted
                                 ? "Permission granted. Quit and reopen ISOFix to start monitoring."
                                 : "Needed to notice wrong keys. Turn on ISOFix in Privacy & Security → Input Monitoring.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    // Once granted, macOS offers "Quit & Reopen" itself.
                    if !model.permissionGranted {
                        Button("Open Privacy Settings…") { model.requestPermission() }
                    }
                }
            }

            Section {
                if model.rows.isEmpty {
                    Text("No external keyboards connected.").foregroundStyle(.secondary)
                }
                ForEach(model.rows) { row in
                    Picker(selection: Binding(get: { row.mode }, set: { model.setMode($0, for: row.id) })) {
                        Text("Automatic").tag(AppModel.Mode.auto)
                        Divider()
                        Text("Always swap").tag(AppModel.Mode.swap)
                        Text("Don't swap").tag(AppModel.Mode.leave)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Text(details(row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Keyboards")
            } footer: {
                footnote("ISOFix checks a keyboard when you press § or < on it. If you're running Karabiner-Elements, quit it. It takes over your keyboards, so ISOFix can't fix them.")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                if let err = model.loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                footnote("ISOFix runs in the background without an icon. Open it again to get back here.")
            }

            Section {
                HStack {
                    Link("ISOFix on GitHub", destination: AppInfo.repoURL)
                    Spacer()
                    Button("Quit ISOFix") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Keychron · USB · Fixed at 20:41"
    private func details(_ row: AppModel.Row) -> String {
        [row.info.manufacturer ?? row.id.description, row.info.transport, row.status]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
