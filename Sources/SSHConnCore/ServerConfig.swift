import Foundation

// MARK: - Ошибки

public struct SSHConnError: LocalizedError {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

// MARK: - Модель конфигурации

public struct ServerConfig: Identifiable, Sendable, Hashable {
    public static let defaultPort = 22

    public var name: String
    public var host: String
    public var port: Int
    public var user: String
    public var keyPath: String
    /// Логическая группа; nil — запись без группы.
    public var group: String?

    public var id: String { name }

    public init(name: String, host: String, port: Int, user: String, keyPath: String, group: String? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.keyPath = keyPath
        self.group = group
    }

    /// Строки записи в формате файла конфигурации.
    public var blockLines: [String] {
        var lines = ["Name \(name)"]
        if let group, !group.isEmpty {
            lines.append("Group \(group)")
        }
        lines.append(contentsOf: ["Host \(host)", "Port \(port)", "User \(user)", "Key \(keyPath)"])
        return lines
    }
}

// MARK: - Разбор файла

/// Запись конфига вместе с диапазоном занимаемых ею строк файла.
struct ConfigBlock {
    let range: Range<Int>
    let fields: [(key: String, value: String)]

    func value(_ key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    /// Готовая конфигурация или nil, если в блоке нет обязательных полей.
    /// Отсутствующий или некорректный `Port` заменяется портом по умолчанию.
    var serverConfig: ServerConfig? {
        guard let name = value("Name"),
              let host = value("Host"),
              let user = value("User"),
              let key = value("Key") else {
            return nil
        }
        let port = value("Port").flatMap(Int.init) ?? ServerConfig.defaultPort
        let group = value("Group").flatMap { $0.isEmpty ? nil : $0 }
        return ServerConfig(name: name, host: host, port: port, user: user, keyPath: key, group: group)
    }
}

/// Разбирает строку «Ключ значение»; nil для пустых строк, комментариев и мусора.
func parseEntry(_ line: String) -> (key: String, value: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2 else { return nil }
    return (String(parts[0]), parts[1].trimmingCharacters(in: .whitespaces))
}

/// Находит все блоки конфигурации. Диапазон блока охватывает только значимые
/// строки, поэтому комментарии и пустые строки вне блоков не теряются при правках.
func parseBlocks(_ lines: [String]) -> [ConfigBlock] {
    var blocks: [ConfigBlock] = []
    var start: Int?
    var lastSignificant = 0
    var fields: [(key: String, value: String)] = []

    func flush(_ endExclusive: Int) {
        if let start {
            blocks.append(ConfigBlock(range: start..<max(endExclusive, start + 1), fields: fields))
        }
        start = nil
        fields = []
    }

    for (index, line) in lines.enumerated() {
        guard let entry = parseEntry(line) else { continue }

        if entry.key == "Name" {
            flush(lastSignificant + 1)
            start = index
        }
        guard start != nil else { continue }

        fields.append(entry)
        lastSignificant = index
    }
    flush(lastSignificant + 1)

    return blocks
}

// MARK: - Путь к конфигурации

/// Путь к файлу конфигурации; переопределяется переменной окружения `SSH_CONN_CONFIG`.
public func configFileURL() -> URL {
    let override = ProcessInfo.processInfo.environment["SSH_CONN_CONFIG"]?
        .trimmingCharacters(in: .whitespaces)

    if let override, !override.isEmpty {
        return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh-conn.config")
}
