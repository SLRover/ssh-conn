import Foundation
import Observation
import SSHConnCore

/// Фильтр хостов в боковой панели.
enum GroupFilter: Hashable, Identifiable {
    case all
    case ungrouped
    case group(String)

    var id: String {
        switch self {
        case .all: "all"
        case .ungrouped: "ungrouped"
        case .group(let name): "group:\(name)"
        }
    }

    var title: String {
        switch self {
        case .all: "Все хосты"
        case .ungrouped: "Без группы"
        case .group(let name): name
        }
    }

    var groupName: String? {
        if case .group(let name) = self {
            return name
        }
        return nil
    }
}

/// Черновик записи в форме редактирования.
struct HostDraft: Identifiable {
    let id = UUID()
    var originalName: String?
    var name: String
    var host: String
    var port: String
    var user: String
    var keyPath: String
    var group: String

    init(config: ServerConfig? = nil, preselectedGroup: String = "") {
        originalName = config?.name
        name = config?.name ?? ""
        host = config?.host ?? ""
        port = config.map { String($0.port) } ?? ""
        user = config?.user ?? ""
        keyPath = config?.keyPath ?? ""
        group = config?.group ?? preselectedGroup
    }

    /// Проверяет поля и превращает черновик в запись конфигурации.
    func validated(against hosts: [ServerConfig]) throws -> ServerConfig {
        let name = name.trimmed
        let host = host.trimmed
        let user = user.trimmed
        let keyPath = keyPath.trimmed
        let group = group.trimmed
        let rawPort = port.trimmed

        guard !name.isEmpty else {
            throw SSHConnError("Укажите имя хоста.")
        }
        guard !name.contains(where: \.isWhitespace) else {
            throw SSHConnError("Имя хоста не должно содержать пробелов.")
        }
        if hosts.contains(where: { $0.name == name && $0.name != originalName }) {
            throw SSHConnError("Хост с именем '\(name)' уже есть в конфиге.")
        }
        guard !group.contains(where: \.isNewline) else {
            throw SSHConnError("Название группы не должно содержать переводов строки.")
        }
        guard !host.isEmpty else {
            throw SSHConnError("Укажите адрес хоста.")
        }
        guard !user.isEmpty else {
            throw SSHConnError("Укажите имя пользователя.")
        }
        guard !keyPath.isEmpty else {
            throw SSHConnError("Укажите путь к приватному ключу.")
        }

        let portNumber: Int
        if rawPort.isEmpty {
            portNumber = ServerConfig.defaultPort
        } else if let value = Int(rawPort), (1...65535).contains(value) {
            portNumber = value
        } else {
            throw SSHConnError("Некорректный порт '\(rawPort)': ожидается число от 1 до 65535.")
        }

        return ServerConfig(
            name: name,
            host: host,
            port: portNumber,
            user: user,
            keyPath: keyPath,
            group: group.isEmpty ? nil : group
        )
    }
}

@MainActor
@Observable
final class HostListModel {
    private(set) var hosts: [ServerConfig] = []
    var searchText = ""
    private(set) var loadError: String?

    private let store = ConfigStore()

    var configURL: URL { store.url }
    var configExists: Bool { store.exists }

    /// Имена групп в порядке сортировки; группы существуют, пока в них есть хосты.
    var groupNames: [String] {
        Set(hosts.compactMap(\.group))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var hasUngroupedHosts: Bool { hosts.contains { $0.group == nil } }

    func count(in filter: GroupFilter) -> Int {
        hosts.count { matches($0, filter) }
    }

    func hosts(in filter: GroupFilter) -> [ServerConfig] {
        let scoped = hosts.filter { matches($0, filter) }
        let query = searchText.trimmed.lowercased()
        guard !query.isEmpty else { return scoped }
        return scoped.filter { server in
            [server.name, server.host, server.user, server.keyPath, server.group ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    func reload() {
        loadError = nil
        guard store.exists else {
            hosts = []
            return
        }
        do {
            hosts = try store.servers()
        } catch {
            hosts = []
            loadError = error.localizedDescription
        }
    }

    func save(_ draft: HostDraft) throws {
        let config = try draft.validated(against: hosts)

        if let originalName = draft.originalName {
            var changes: [(key: String, value: String)] = [
                ("Host", config.host),
                ("Port", String(config.port)),
                ("User", config.user),
                ("Key", config.keyPath)
            ]
            var removals: [String] = []
            if let group = config.group {
                changes.append(("Group", group))
            } else {
                removals.append("Group")
            }
            if config.name != originalName {
                changes.append(("Name", config.name))
            }
            try store.update(named: originalName, changes: changes, removingKeys: removals)
        } else {
            try store.append(config)
        }

        reload()
    }

    func delete(_ config: ServerConfig) throws {
        try store.remove(named: config.name)
        reload()
    }

    private func matches(_ server: ServerConfig, _ filter: GroupFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .ungrouped:
            server.group == nil
        case .group(let name):
            server.group == name
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
