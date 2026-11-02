import Foundation

// MARK: - Файл конфигурации

public struct ConfigStore {
    public let url: URL

    public init(url: URL = configFileURL()) {
        self.url = url
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func readLines() throws -> [String] {
        guard exists else {
            throw SSHConnError("Файл \(url.path) не найден")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.components(separatedBy: "\n")
    }

    func blocks() throws -> [ConfigBlock] {
        parseBlocks(try readLines())
    }

    public func servers() throws -> [ServerConfig] {
        try blocks().compactMap { $0.serverConfig }
    }

    public func server(named name: String) throws -> ServerConfig {
        guard let config = try servers().first(where: { $0.name == name }) else {
            throw SSHConnError("Сервер с именем '\(name)' не найден в конфиге")
        }
        return config
    }

    /// Дописывает запись в конец файла, создавая файл при необходимости.
    public func append(_ config: ServerConfig) throws {
        if !exists {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        var lines = exists ? try readLines() : []

        if let last = lines.last, !last.isEmpty {
            lines.append("")
        }
        lines.append(contentsOf: config.blockLines)
        if lines.last?.isEmpty != true {
            lines.append("")
        }
        try write(lines)
    }

    /// Меняет отдельные поля записи, сохраняя остальные строки файла без изменений.
    /// Ключи из `removingKeys` удаляются из блока (например, чтобы убрать группу).
    public func update(
        named name: String,
        changes: [(key: String, value: String)],
        removingKeys: [String] = []
    ) throws {
        var lines = try readLines()
        let target = try block(named: name, in: lines)
        var blockLines = Array(lines[target.range])

        for key in removingKeys {
            blockLines.removeAll { parseEntry($0)?.key == key }
        }

        for (key, value) in changes {
            if let index = blockLines.firstIndex(where: { parseEntry($0)?.key == key }) {
                blockLines[index] = "\(key) \(value)"
            } else {
                blockLines.append("\(key) \(value)")
            }
        }

        lines.replaceSubrange(target.range, with: blockLines)
        try write(lines)
    }

    /// Удаляет запись вместе с занимаемыми ею строками.
    public func remove(named name: String) throws {
        var lines = try readLines()
        let target = try block(named: name, in: lines)
        lines.removeSubrange(target.range)

        // после удаления не оставляем двойную пустую строку на месте записи
        let cut = target.range.lowerBound
        if cut > 0, cut < lines.count,
           lines[cut - 1].trimmingCharacters(in: .whitespaces).isEmpty,
           lines[cut].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: cut)
        }

        try write(lines)
    }

    private func block(named name: String, in lines: [String]) throws -> ConfigBlock {
        guard let block = parseBlocks(lines).first(where: { $0.value("Name") == name }) else {
            throw SSHConnError("Сервер с именем '\(name)' не найден в конфиге")
        }
        return block
    }

    private func write(_ lines: [String]) throws {
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
