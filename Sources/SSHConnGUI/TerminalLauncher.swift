import AppKit
import Foundation
import SSHConnCore

/// Открывает SSH-сессию в Terminal.app.
enum TerminalLauncher {
    /// Команда подключения в виде, готовом для вставки в оболочку.
    static func sshCommand(for config: ServerConfig) -> String {
        let arguments = [
            "ssh",
            "-i", expandPath(config.keyPath),
            "-p", String(config.port),
            "\(config.user)@\(config.host)"
        ]
        return arguments.map(shellQuoted).joined(separator: " ")
    }

    static func connect(to config: ServerConfig) throws {
        let command = sshCommand(for: config)

        do {
            try runAppleScript(command)
        } catch {
            do {
                try openCommandFile(for: config, command: command)
            } catch {
                throw SSHConnError(
                    "Не удалось открыть Terminal. Скопируйте команду и выполните её вручную:\n\(command)"
                )
            }
        }
    }

    private static func runAppleScript(_ command: String) throws {
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscaped(command))"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SSHConnError(message.isEmpty ? "osascript завершился с ошибкой" : message)
        }
    }

    /// Резервный вариант: `.command`-файл открывается в Terminal без запроса прав автоматизации.
    private static func openCommandFile(for config: ServerConfig, command: String) throws {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ssh-conn", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeName = config.name.replacingOccurrences(of: "/", with: "_")
        let file = directory.appendingPathComponent("connect-\(safeName).command")
        try "#!/bin/sh\nexec \(command)\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", file.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SSHConnError("open завершился с ошибкой")
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
