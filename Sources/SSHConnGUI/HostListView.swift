import AppKit
import Combine
import SSHConnCore
import SwiftUI

/// Окно со списком хостов, сгруппированных по логическим группам.
struct HostListView: View {
    @Bindable var model: HostListModel

    @State private var groupFilter: GroupFilter? = .all
    @State private var selection: ServerConfig.ID?
    @State private var editorDraft: HostDraft?
    @State private var pendingDeletion: ServerConfig?
    @State private var isAddingGroup = false
    @State private var pendingGroupDeletion: String?
    @State private var dropTarget: GroupFilter?
    @State private var errorState: ErrorState?

    /// Ошибка, которую нужно показать в отдельном окне.
    private struct ErrorState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var activeFilter: GroupFilter { groupFilter ?? .all }
    private var displayedHosts: [ServerConfig] { model.hosts(in: activeFilter) }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if let loadError = model.loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                }

                if !model.hosts.isEmpty {
                    searchBar
                }

                content

                Divider()
                footer
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Без подложки у тулбара материал сайдбара идёт от самого верха окна,
        // и вертикальная граница остаётся одной линией без ступеньки у заголовка.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 800, minHeight: 400)
        .toolbar { toolbarContent }
        .sheet(item: $editorDraft) { draft in
            HostEditorView(draft: draft, hosts: model.hosts, groups: model.groupNames) { edited in
                try model.save(edited)
                selection = edited.name.trimmed
            }
        }
        .alert(
            errorState?.title ?? "Ошибка",
            isPresented: Binding(
                get: { errorState != nil },
                set: { if !$0 { errorState = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorState?.message ?? "")
        }
        .confirmationDialog(
            "Удалить хост '\(pendingDeletion?.name ?? "")'?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { deletePending() }
            Button("Отмена", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Запись будет удалена из \(model.configURL.path). Действие нельзя отменить.")
        }
        .confirmationDialog(
            "Удалить группу '\(pendingGroupDeletion ?? "")'?",
            isPresented: Binding(
                get: { pendingGroupDeletion != nil },
                set: { if !$0 { pendingGroupDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { deletePendingGroup() }
            Button("Отмена", role: .cancel) { pendingGroupDeletion = nil }
        } message: {
            Text("Объявление группы будет удалено из \(model.configURL.path).")
        }
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
        .onChange(of: groupFilter) { _, _ in
            selection = nil
        }
        .onChange(of: model.groupNames) { _, _ in
            normalizeGroupFilter()
        }
        .onChange(of: model.hasUngroupedHosts) { _, _ in
            normalizeGroupFilter()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $groupFilter) {
                row(GroupFilter.all.title, systemImage: "tray.full", count: model.count(in: .all), filter: .all)
                    .tag(GroupFilter.all)

                Section("Группы") {
                    ForEach(model.groupNames, id: \.self) { name in
                        row(
                            name,
                            systemImage: "folder",
                            count: model.count(in: .group(name)),
                            filter: .group(name),
                            acceptsDrop: true
                        )
                        .tag(GroupFilter.group(name))
                        .contextMenu {
                            Button("Удалить группу…", role: .destructive) {
                                pendingGroupDeletion = name
                            }
                            .disabled(model.count(in: .group(name)) > 0)
                        }
                    }
                }

                if showsUngroupedRow {
                    Section {
                        row(
                            GroupFilter.ungrouped.title,
                            systemImage: "tray",
                            count: model.count(in: .ungrouped),
                            filter: .ungrouped,
                            acceptsDrop: true
                        )
                        .tag(GroupFilter.ungrouped)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                isAddingGroup = true
            } label: {
                Label("Добавить группу", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 210)
        .sheet(isPresented: $isAddingGroup) {
            GroupEditorView { name in
                let added = try model.addGroup(name)
                groupFilter = .group(added)
            }
        }
    }

    @ViewBuilder
    private func row(
        _ title: String,
        systemImage: String,
        count: Int,
        filter: GroupFilter,
        acceptsDrop: Bool = false
    ) -> some View {
        let label = Label(title, systemImage: systemImage)
            .badge(count)

        if acceptsDrop {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .modifier(
                    GroupDropTarget(filter: filter, dropTarget: $dropTarget) { items in
                        moveHosts(items, to: filter)
                    }
                )
        } else {
            label
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Поиск по имени, адресу, группе или пользователю", text: $model.searchText)
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.hosts.isEmpty {
            emptyState
        } else if displayedHosts.isEmpty {
            if model.searchText.trimmed.isEmpty {
                groupEmptyState
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            hostTable
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет хостов", systemImage: "server.rack")
        } description: {
            if model.configExists {
                Text("В файле \(model.configURL.path) нет ни одной корректной записи.")
            } else {
                Text("Файл \(model.configURL.path) ещё не создан. Добавьте первый хост — файл появится автоматически.")
            }
        } actions: {
            Button("Добавить хост") { editorDraft = newDraft() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupEmptyState: some View {
        ContentUnavailableView {
            Label("В группе «\(activeFilter.title)» нет хостов", systemImage: "folder")
        } description: {
            Text("Добавьте хост в эту группу или выберите другую группу в боковой панели.")
        } actions: {
            Button("Добавить хост") { editorDraft = newDraft() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hostTable: some View {
        Table(displayedHosts, selection: $selection) {
            TableColumn("Имя") { server in
                HStack(spacing: 6) {
                    dragHandle(for: server)
                    Text(server.name)
                }
            }
            .width(min: 90, ideal: 120)
            TableColumn("Адрес", value: \.host)
                .width(min: 110, ideal: 170)
            TableColumn("Порт") { server in
                Text(String(server.port))
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            TableColumn("Пользователь", value: \.user)
                .width(min: 90, ideal: 110)
            TableColumn("Ключ", value: \.keyPath)
                .width(min: 120, ideal: 200)
        }
        .contextMenu(forSelectionType: ServerConfig.ID.self) { ids in
            if let server = server(in: ids) {
                Button("Подключиться") { connect(server) }
                Button("Изменить…") { editorDraft = HostDraft(config: server) }
                Divider()
                Button("Удалить…", role: .destructive) { pendingDeletion = server }
            }
        } primaryAction: { ids in
            if let server = server(in: ids) {
                connect(server)
            }
        }
    }

    /// Ручка, за которую хост перетаскивается в группу в боковой панели.
    /// Остальная часть строки остаётся обычной, чтобы клик выделял хост.
    private func dragHandle(for server: ServerConfig) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(width: 14, height: 16)
            .contentShape(Rectangle())
            .draggable(HostDragItem(name: server.name))
            .help("Перетащите хост в группу в боковой панели")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(hostCountLabel)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([model.configURL])
            } label: {
                Label("Показать в Finder", systemImage: "folder")
            }
            .buttonStyle(.link)
            .disabled(!model.configExists)

            Text(model.configURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(model.configURL.path)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                connectSelected()
            } label: {
                Label("Подключиться", systemImage: "terminal")
            }
            .disabled(selectedHost == nil)
            .help("Открыть SSH-сессию в Terminal (двойной клик по строке)")
        }

        ToolbarItem {
            Button {
                if let server = selectedHost {
                    editorDraft = HostDraft(config: server)
                }
            } label: {
                Label("Изменить", systemImage: "pencil")
            }
            .disabled(selectedHost == nil)
        }

        ToolbarItem {
            Button {
                editorDraft = newDraft()
            } label: {
                Label("Добавить", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Добавить хост")
        }

        ToolbarItem {
            Button {
                pendingDeletion = selectedHost
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .disabled(selectedHost == nil)
        }

        ToolbarItem {
            Button {
                model.reload()
            } label: {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
            .help("Перечитать файл конфигурации")
        }
    }

    private var selectedHost: ServerConfig? {
        guard let selection else { return nil }
        return displayedHosts.first { $0.id == selection }
    }

    /// Пункт «Без группы» служит и целью для перетаскивания, поэтому он виден,
    /// пока в конфиге есть хоть одна группа.
    private var showsUngroupedRow: Bool {
        model.hasUngroupedHosts || model.hasGroupedHosts
    }

    private var hostCountLabel: String {
        let count = displayedHosts.count
        if model.searchText.trimmed.isEmpty {
            return "Хостов: \(count)"
        }
        return "Найдено: \(count) из \(model.count(in: activeFilter))"
    }

    private func newDraft() -> HostDraft {
        HostDraft(preselectedGroup: activeFilter.groupName ?? "")
    }

    private func normalizeGroupFilter() {
        guard let filter = groupFilter else { return }
        switch filter {
        case .all:
            break
        case .ungrouped:
            if !model.hasUngroupedHosts {
                groupFilter = .all
            }
        case .group(let name):
            if !model.groupNames.contains(name) {
                groupFilter = .all
            }
        }
    }

    private func server(in ids: Set<ServerConfig.ID>) -> ServerConfig? {
        guard let id = ids.first else { return nil }
        return displayedHosts.first { $0.id == id }
    }

    private func connectSelected() {
        if let server = selectedHost {
            connect(server)
        }
    }

    private func connect(_ server: ServerConfig) {
        do {
            try TerminalLauncher.connect(to: server)
        } catch {
            errorState = ErrorState(title: "Не удалось подключиться", message: error.localizedDescription)
        }
    }

    /// Переносит перетащенные хосты в выбранную группу.
    private func moveHosts(_ items: [HostDragItem], to filter: GroupFilter) -> Bool {
        guard filter != .all else { return false }

        let snapshot = model.hosts
        var moved = false
        for item in items {
            guard let server = snapshot.first(where: { $0.name == item.name }) else { continue }
            do {
                if try model.move(server, to: filter.groupName) {
                    moved = true
                }
            } catch {
                errorState = ErrorState(
                    title: "Не удалось переместить хост",
                    message: error.localizedDescription
                )
                break
            }
        }
        return moved
    }

    private func deletePending() {
        guard let server = pendingDeletion else { return }
        do {
            try model.delete(server)
            if selection == server.id {
                selection = nil
            }
        } catch {
            errorState = ErrorState(title: "Не удалось удалить хост", message: error.localizedDescription)
        }
        pendingDeletion = nil
    }

    private func deletePendingGroup() {
        guard let name = pendingGroupDeletion else { return }
        do {
            try model.deleteGroup(name)
        } catch {
            errorState = ErrorState(title: "Не удалось удалить группу", message: error.localizedDescription)
        }
        pendingGroupDeletion = nil
    }
}

/// Приём перетаскиваемых хостов строкой группы с подсветкой цели.
private struct GroupDropTarget: ViewModifier {
    let filter: GroupFilter
    @Binding var dropTarget: GroupFilter?
    let perform: ([HostDragItem]) -> Bool

    func body(content: Content) -> some View {
        content
            .dropDestination(for: HostDragItem.self) { items, _ in
                perform(items)
            } isTargeted: { isTargeted in
                if isTargeted {
                    dropTarget = filter
                } else if dropTarget == filter {
                    dropTarget = nil
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(dropTarget == filter ? Color.accentColor.opacity(0.2) : Color.clear)
            }
            .animation(.easeOut(duration: 0.12), value: dropTarget)
    }
}
