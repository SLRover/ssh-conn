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

func loadConfig(for targetName: String) throws -> ServerConfig {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let configURL = homeDir.appendingPathComponent(".ssh-conn.config")

    guard FileManager.default.fileExists(atPath: configURL.path) else {
        throw NSError(domain: "ssh-conn", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Файл ~/.ssh-conn.config не найден"])
    }

    let content = try String(contentsOf: configURL, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)

    var currentBlock: [String: String] = [:]
    var foundConfig: ServerConfig?

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { continue }

        let key = String(parts[0])
        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

        if key == "Name" {
            // Если предыдущий блок был нужным сервером — сохраняем его
            if currentBlock["Name"] == targetName {
                foundConfig = makeConfig(from: currentBlock)
                break
            }
            // Начинаем новый блок
            currentBlock = [key: value]
        } else {
            currentBlock[key] = value
        }
    }

    // Проверка последнего блока
    if foundConfig == nil, currentBlock["Name"] == targetName {
        foundConfig = makeConfig(from: currentBlock)
    }

    guard let config = foundConfig else {
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

// MARK: - Запуск SSH

func execSSH(config: ServerConfig) throws -> Never {
    // Разворачиваем ~ и относительные пути в абсолютный путь к ключу
    let expandedKeyPath = expandPath(config.keyPath)

    // Формируем аргументы для ssh
    let destination = "\(config.user)@\(config.host)"
    let args: [String] = [
        "ssh",
        "-i", expandedKeyPath,
        "-p", String(config.port),
        destination
    ]

    // Преобразуем в C-массив строк
    let cArgs = args.map { strdup($0) } + [nil]

    // execv заменяет текущий процесс на ssh
    execv("/usr/bin/ssh", cArgs)

    // Если execv вернулся — произошла ошибка
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
    // Относительный путь (например, ./ssh/id_rsa) — считаем относительно домашнего каталога
    return (homeDir as NSString).appendingPathComponent(expandedTilde)
}

// MARK: - Точка входа

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    let progName = (arguments.first as NSString?)?.lastPathComponent ?? "ssh-conn"
    print("Использование: \(progName) <имя_сервера>")
    print("Пример: \(progName) server1")
    exit(1)
}

let serverName = arguments[1]

do {
    let config = try loadConfig(for: serverName)
    try execSSH(config: config)
} catch {
    print("Ошибка: \(error.localizedDescription)")
    exit(1)
}
