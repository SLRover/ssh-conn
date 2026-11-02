import AppKit
import Foundation
import SSHConnCore
import SwiftUI

/// Форма создания и редактирования записи.
struct HostEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HostDraft
    @State private var errorMessage: String?

    private let hosts: [ServerConfig]
    private let groups: [String]
    private let onSave: (HostDraft) throws -> Void

    init(
        draft: HostDraft,
        hosts: [ServerConfig],
        groups: [String],
        onSave: @escaping (HostDraft) throws -> Void
    ) {
        _draft = State(initialValue: draft)
        self.hosts = hosts
        self.groups = groups
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.originalName == nil ? "Новый хост" : "Изменить хост")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Form {
                TextField("Имя", text: $draft.name, prompt: Text("prod"))
                TextField("Группа", text: $draft.group, prompt: Text("Без группы"))
                if !groups.isEmpty {
                    HStack {
                        Spacer()
                        Menu("Выбрать группу…") {
                            Button("Без группы") { draft.group = "" }
                            Divider()
                            ForEach(groups, id: \.self) { name in
                                Button(name) { draft.group = name }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                TextField("Адрес хоста", text: $draft.host, prompt: Text("203.0.113.10"))
                TextField("Порт", text: $draft.port, prompt: Text("\(ServerConfig.defaultPort)"))
                TextField("Пользователь", text: $draft.user, prompt: Text("root"))
                TextField("Приватный ключ", text: $draft.keyPath, prompt: Text("~/.ssh/id_ed25519"))
                HStack {
                    Spacer()
                    Button("Выбрать файл…") { chooseKeyFile() }
                }
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 6) {
                if let keyWarning {
                    Label(keyWarning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
    }

    private var keyWarning: String? {
        let path = draft.keyPath.trimmed
        guard !path.isEmpty else { return nil }
        guard !FileManager.default.fileExists(atPath: expandPath(path)) else { return nil }
        return "Файл ключа не найден, но запись можно сохранить."
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "Выберите приватный ключ"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.keyPath = (url.path as NSString).abbreviatingWithTildeInPath
    }
}
