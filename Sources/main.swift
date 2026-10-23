import Foundation

// MARK: - Модель конфигурации

struct ServerConfig {
    let name: String
    let host: String
    let port: Int
    let user: String
    let keyPath: String
}

// MARK: - Парсер конфигурации

/// Читает все блоки из файла конфигурации.
func loadAllConfigs() throws -> [ServerConfig] {
    let configURL = configFileURL()

    guard FileManager.default.fileExists(atPath: configURL.path) else {
        throw NSError(domain: "ssh-conn", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Файл ~/.ssh-conn.config не найден"])
    }

    let content = try String(contentsOf: configURL, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)

    var blocks: [[String: String]] = []
    var currentBlock: [String: String] = [:]

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { continue }

        let key = String(parts[0])
        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

        if key == "Name" {
            // Начинаем новый блок — сохраняем предыдущий, если он не пуст
            if !currentBlock.isEmpty {
                blocks.append(currentBlock)
            }
            currentBlock = [key: value]
        } else {
            currentBlock[key] = value
        }
    }

    if !currentBlock.isEmpty {
        blocks.append(currentBlock)
    }

    return blocks.compactMap { makeConfig(from: $0) }
}

/// Ищет конфигурацию конкретного сервера по имени.
func loadConfig(for targetName: String) throws -> ServerConfig {
    let all = try loadAllConfigs()
    guard let config = all.first(where: { $0.name == targetName }) else {
        throw NSError(domain: "ssh-conn", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Сервер с именем '\(targetName)' не найден в конфиге"])
    }
    return config
}

func makeConfig(from dict: [String: String]) -> ServerConfig? {
    guard let name = dict["Name"],
          let host = dict["Host"],
          let portStr = dict["Port"],
          let port = Int(portStr),
          let user = dict["User"],
          let key = dict["Key"] else {
        return nil
    }
    return ServerConfig(name: name, host: host, port: port, user: user, keyPath: key)
}

func configFileURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh-conn.config")
}

// MARK: - Вывод таблицы

func printTable(_ configs: [ServerConfig]) {
    let headers = ["Имя хоста", "Адрес", "Пользователь", "Ключ"]

    // Для каждой строки формируем массив ячеек
    let rows: [[String]] = configs.map { config in
        [config.name, config.host, config.user, config.keyPath]
    }

    // Вычисляем ширину каждого столбца (с учётом заголовка)
    var widths = headers.map { $0.count }
    for row in rows {
        for (i, cell) in row.enumerated() {
            widths[i] = max(widths[i], cell.count)
        }
    }

    // Функция для форматирования строки с паддингом
    func formatRow(_ cells: [String]) -> String {
        cells.enumerated().map { (i, cell) in
            let pad = widths[i] - cell.count
            return cell + String(repeating: " ", count: pad)
        }.joined(separator: " | ")
    }

    print(formatRow(headers))
    // Разделитель
    print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-"))
    for row in rows {
        print(formatRow(row))
    }
}

// MARK: - Запуск SSH

func execSSH(config: ServerConfig) throws -> Never {
    let expandedKeyPath = expandPath(config.keyPath)
    let destination = "\(config.user)@\(config.host)"
    let args: [String] = [
        "ssh",
        "-i", expandedKeyPath,
        "-p", String(config.port),
        destination
    ]

    let cArgs = args.map { strdup($0) } + [nil]
    execv("/usr/bin/ssh", cArgs)

    let error = String(cString: strerror(errno))
    throw NSError(domain: "ssh-conn", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить ssh: \(error)"])
}

/// Разворачивает `~` в домашний каталог, а относительный путь — относительно домашнего каталога.
func expandPath(_ path: String) -> String {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let expandedTilde = NSString(string: path).expandingTildeInPath

    if expandedTilde.hasPrefix("/") {
        return expandedTilde
    }
    return (homeDir as NSString).appendingPathComponent(expandedTilde)
}

// MARK: - Точка входа

let progName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ssh-conn"
let arguments = CommandLine.arguments

guard arguments.count >= 2 else {
    print("""
    Использование:
      \(progName) <имя_сервера>   — подключиться к серверу
      \(progName) list            — показать список серверов
    """)
    exit(1)
}

let command = arguments[1]

switch command {
case "list":
    do {
        let configs = try loadAllConfigs()
        if configs.isEmpty {
            print("В конфиге нет ни одного корректного сервера.")
        } else {
            printTable(configs)
        }
    } catch {
        print("Ошибка: \(error.localizedDescription)")
        exit(1)
    }

default:
    do {
        let config = try loadConfig(for: command)
        try execSSH(config: config)
    } catch {
        print("Ошибка: \(error.localizedDescription)")
        exit(1)
    }
}
