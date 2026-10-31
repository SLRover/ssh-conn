import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Запуск SSH

/// Заменяет текущий процесс клиентом `ssh` (бинарник ищется по `PATH`).
func execSSH(config: ServerConfig) throws -> Never {
    let args = [
        "ssh",
        "-i", expandPath(config.keyPath),
        "-p", String(config.port),
        "\(config.user)@\(config.host)"
    ]

    let cArgs = args.map { strdup($0) } + [nil]
    execvp("ssh", cArgs)

    throw SSHConnError("Не удалось запустить ssh: \(String(cString: strerror(errno)))")
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
