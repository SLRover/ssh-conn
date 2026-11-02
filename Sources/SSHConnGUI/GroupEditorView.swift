import SwiftUI

/// Форма создания группы, для которой пока нет хостов.
struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var errorMessage: String?

    private let onSave: (String) throws -> Void

    init(onSave: @escaping (String) throws -> Void) {
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Новая группа")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Form {
                TextField("Название", text: $name, prompt: Text("production"))
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
        .frame(width: 380)
    }

    private func save() {
        do {
            try onSave(name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
