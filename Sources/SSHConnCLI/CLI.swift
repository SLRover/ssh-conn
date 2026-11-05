import Foundation
import SSHConnCore
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Справка

func usage(_ progName: String) -> String {
    """
    Использование:
      \(progName) <сервер>                — подключиться к серверу
      \(progName) list                    — показать список серверов
      \(progName) add <имя> [опции]       — добавить сервер
      \(progName) remove <имя> [--force]  — удалить сервер
      \(progName) edit <имя> [опции]      — изменить сервер
      \(progName) completion [оболочка]   — скрипт автодополнения (zsh, bash, fish)
      \(progName) completion install      — включить автодополнение в конфиге оболочки
      \(progName) help                    — показать эту справку

    Опции add и edit:
      --host <адрес>   адрес сервера
      --port <порт>    порт SSH (по умолчанию \(ServerConfig.defaultPort))
      --user <имя>     имя пользователя
      --key <путь>     путь к приватному ключу
      --group <имя>    группа сервера; пустое значение убирает группу (edit)
      --rename <имя>   новое имя сервера (только edit)
      --force          перезаписать существующую запись (add),
                       удалить без подтверждения (remove)

    Без опций add и edit запрашивают значения интерактивно (если есть терминал).

    Конфигурация: ~/.ssh-conn.config (переопределяется через SSH_CONN_CONFIG).
    """
}

// MARK: - Разбор аргументов

struct CLIArguments {
    static let valueOptions: Set<String> = ["host", "port", "user", "key", "group", "rename"]
    static let booleanFlags: Set<String> = ["force"]

    var positionals: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    static func parse(_ arguments: [String]) throws -> CLIArguments {
        var result = CLIArguments()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            guard argument.hasPrefix("-") else {
                result.positionals.append(argument)
                continue
            }
            guard argument.hasPrefix("--") else {
                throw SSHConnError("Неизвестная опция '\(argument)'. Справка: --help")
            }

            let body = String(argument.dropFirst(2))
            let name: String
            let inlineValue: String?
            if let separator = body.firstIndex(of: "=") {
                name = String(body[..<separator])
                inlineValue = String(body[body.index(after: separator)...])
            } else {
                name = body
                inlineValue = nil
            }

            if booleanFlags.contains(name) {
                guard inlineValue == nil else {
                    throw SSHConnError("Опция '--\(name)' не принимает значения")
                }
                result.flags.insert(name)
            } else if valueOptions.contains(name) {
                if let inlineValue {
                    result.options[name] = inlineValue
                } else {
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw SSHConnError("Опция '--\(name)' требует значения")
                    }
                    result.options[name] = arguments[index]
                    index += 1
                }
            } else {
                throw SSHConnError("Неизвестная опция '--\(name)'. Справка: --help")
            }
        }

        return result
    }
}

// MARK: - Ввод и вывод

var stdinIsTerminal: Bool {
    isatty(STDIN_FILENO) != 0
}

/// Печатает приглашение и читает строку; nil — если ввода нет.
func prompt(_ label: String) -> String? {
    FileHandle.standardOutput.write(Data("\(label): ".utf8))
    guard let line = readLine() else {
        FileHandle.standardOutput.write(Data("\n".utf8))
        return nil
    }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("Предупреждение: \(message)\n".utf8))
}

func warnIfKeyMissing(_ keyPath: String) {
    if !FileManager.default.fileExists(atPath: expandPath(keyPath)) {
        warn("файл ключа '\(keyPath)' не найден")
    }
}

/// Возвращает порт из аргумента или nil; проверяет диапазон.
func validatedPort(_ raw: String?) throws -> Int? {
    guard let raw, !raw.isEmpty else { return nil }
    guard let port = Int(raw), (1...65535).contains(port) else {
        throw SSHConnError("Некорректный порт '\(raw)': ожидается число от 1 до 65535")
    }
    return port
}

/// Название группы без пробелов по краям; nil для пустого значения (нет группы).
func normalizedGroup(_ raw: String?) throws -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: \.isNewline) else {
        throw SSHConnError("Название группы не должно содержать переводов строки")
    }
    return trimmed.isEmpty ? nil : trimmed
}

func serverName(from arguments: CLIArguments, hint: String) throws -> String {
    guard let name = arguments.positionals.first else {
        throw SSHConnError("Не указано имя сервера. \(hint)")
    }
    guard arguments.positionals.count == 1 else {
        throw SSHConnError("Лишние аргументы: \(arguments.positionals.dropFirst().joined(separator: " "))")
    }
    return name
}

// MARK: - Команды

func listServers(arguments: [String]) throws {
    let args = try CLIArguments.parse(arguments)
    guard args.positionals.isEmpty, args.options.isEmpty, args.flags.isEmpty else {
        throw SSHConnError("Команда list не принимает аргументов. Справка: --help")
    }

    let configs = try ConfigStore().servers()
    guard !configs.isEmpty else {
        print("В конфиге нет ни одного корректного сервера.")
        return
    }
    printTable(configs)
}

func addServer(arguments: [String]) throws {
    let args = try CLIArguments.parse(arguments)
    let name = try serverName(
        from: args,
        hint: "Пример: ssh-conn add prod --host 1.2.3.4 --user root --key ~/.ssh/id_ed25519"
    )

    let store = ConfigStore()
    let servers = store.exists ? try store.servers() : []
    let alreadyExists = servers.contains { $0.name == name }
    if alreadyExists && !args.flags.contains("force") {
        throw SSHConnError("Сервер '\(name)' уже есть в конфиге. Используйте --force для перезаписи или команду edit")
    }

    var host = args.options["host"]
    var user = args.options["user"]
    var key = args.options["key"]
    var rawPort = args.options["port"]

    if stdinIsTerminal {
        host = host ?? prompt("Адрес хоста")
        rawPort = rawPort ?? prompt("Порт (Enter — \(ServerConfig.defaultPort))")
        user = user ?? prompt("Пользователь")
        key = key ?? prompt("Путь к приватному ключу")
    }

    guard let host, !host.isEmpty else { throw SSHConnError("Не указан адрес хоста (--host)") }
    guard let user, !user.isEmpty else { throw SSHConnError("Не указан пользователь (--user)") }
    guard let key, !key.isEmpty else { throw SSHConnError("Не указан путь к ключу (--key)") }
    let port = try validatedPort(rawPort) ?? ServerConfig.defaultPort

    let group = try normalizedGroup(args.options["group"])
    warnIfKeyMissing(key)

    if alreadyExists {
        var changes: [(key: String, value: String)] = [
            ("Host", host), ("Port", String(port)), ("User", user), ("Key", key)
        ]
        var removals: [String] = []
        if let group {
            changes.append(("Group", group))
        } else if args.options["group"] != nil {
            removals.append("Group")
        }
        try store.update(named: name, changes: changes, removingKeys: removals)
        print("Сервер '\(name)' перезаписан.")
    } else {
        try store.append(
            ServerConfig(name: name, host: host, port: port, user: user, keyPath: key, group: group)
        )
        print("Сервер '\(name)' добавлен: \(store.url.path)")
    }
}

func removeServer(arguments: [String]) throws {
    let args = try CLIArguments.parse(arguments)
    let name = try serverName(from: args, hint: "Пример: ssh-conn remove prod")
    let store = ConfigStore()

    _ = try store.server(named: name)

    if stdinIsTerminal && !args.flags.contains("force") {
        let answer = prompt("Удалить сервер '\(name)'? [y/N]")?.lowercased() ?? ""
        guard ["y", "yes", "д", "да"].contains(answer) else {
            print("Отменено.")
            return
        }
    }

    try store.remove(named: name)
    print("Сервер '\(name)' удалён.")
}

func editServer(arguments: [String]) throws {
    let args = try CLIArguments.parse(arguments)
    let name = try serverName(from: args, hint: "Пример: ssh-conn edit prod --port 2222")
    let store = ConfigStore()
    let current = try store.server(named: name)

    var changes: [(key: String, value: String)] = []
    var removals: [String] = []
    var newName = args.options["rename"]

    if let host = args.options["host"] { changes.append(("Host", host)) }
    if let port = try validatedPort(args.options["port"]) { changes.append(("Port", String(port))) }
    if let user = args.options["user"] { changes.append(("User", user)) }
    if let key = args.options["key"] { changes.append(("Key", key)) }
    if let rawGroup = args.options["group"] {
        if let group = try normalizedGroup(rawGroup) {
            changes.append(("Group", group))
        } else {
            removals.append("Group")
        }
    }

    if changes.isEmpty && newName == nil && removals.isEmpty {
        guard stdinIsTerminal else {
            throw SSHConnError(
                "Не указаны изменения: используйте --host/--port/--user/--key/--rename или запустите в терминале"
            )
        }
        let edited = interactiveEdit(for: current)
        changes = edited.changes
        newName = edited.newName
    }

    for (key, value) in changes where value.trimmingCharacters(in: .whitespaces).isEmpty {
        throw SSHConnError("Пустое значение для поля \(key)")
    }

    if let newName, newName != name {
        if try store.servers().contains(where: { $0.name == newName }) {
            throw SSHConnError("Сервер с именем '\(newName)' уже существует")
        }
        changes.append(("Name", newName))
    }

    guard !changes.isEmpty || !removals.isEmpty else {
        print("Изменений нет.")
        return
    }

    try store.update(named: name, changes: changes, removingKeys: removals)

    if let key = changes.first(where: { $0.key == "Key" })?.value {
        warnIfKeyMissing(key)
    }
    print("Сервер '\(newName ?? name)' обновлён.")
}

/// Спрашивает значения всех полей, подставляя текущие как значения по умолчанию.
func interactiveEdit(for config: ServerConfig) -> (changes: [(key: String, value: String)], newName: String?) {
    var changes: [(key: String, value: String)] = []
    var newName: String?

    if let value = prompt("Имя сервера (Enter — \(config.name))"), value != config.name {
        newName = value
    }
    if let value = prompt("Группа (Enter — \(config.group ?? "без группы"))"), value != config.group {
        changes.append(("Group", value))
    }
    if let value = prompt("Адрес хоста (Enter — \(config.host))"), value != config.host {
        changes.append(("Host", value))
    }
    if let value = prompt("Порт (Enter — \(config.port))") {
        do {
            if let port = try validatedPort(value), port != config.port {
                changes.append(("Port", String(port)))
            }
        } catch {
            warn(error.localizedDescription)
        }
    }
    if let value = prompt("Пользователь (Enter — \(config.user))"), value != config.user {
        changes.append(("User", value))
    }
    if let value = prompt("Путь к ключу (Enter — \(config.keyPath))"), value != config.keyPath {
        changes.append(("Key", value))
    }

    return (changes, newName)
}

// MARK: - Вывод таблицы

func printTable(_ configs: [ServerConfig]) {
    let showGroups = configs.contains { $0.group != nil }
    var headers = ["Имя хоста", "Адрес", "Порт", "Пользователь", "Ключ"]
    if showGroups {
        headers.append("Группа")
    }
    let rows: [[String]] = configs.map { config in
        var row = [config.name, config.host, String(config.port), config.user, config.keyPath]
        if showGroups {
            row.append(config.group ?? "")
        }
        return row
    }

    var widths = headers.map { $0.count }
    for row in rows {
        for (index, cell) in row.enumerated() {
            widths[index] = max(widths[index], cell.count)
        }
    }

    func formatRow(_ cells: [String]) -> String {
        cells.enumerated().map { index, cell in
            cell + String(repeating: " ", count: widths[index] - cell.count)
        }.joined(separator: " | ")
    }

    print(formatRow(headers))
    print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-"))
    for row in rows {
        print(formatRow(row))
    }
}
