import Foundation
import SSHConnCore

/// Разбирает аргументы командной строки и выполняет команду.
func runCLI(progName: String, arguments: [String]) throws {
    guard let command = arguments.first else {
        print(usage(progName))
        exit(1)
    }
    let rest = Array(arguments.dropFirst())

    if rest.contains(where: { $0 == "--help" || $0 == "-h" }) {
        print(usage(progName))
        return
    }

    switch command {
    case "-h", "--help", "help":
        print(usage(progName))
    case "list":
        try listServers(arguments: rest)
    case "add":
        try addServer(arguments: rest)
    case "remove", "rm":
        try removeServer(arguments: rest)
    case "edit":
        try editServer(arguments: rest)
    case "completion":
        try runCompletion(progName: progName, arguments: rest)
    case "__complete":
        completeCandidates(arguments: rest)
    default:
        guard !command.hasPrefix("-") else {
            throw SSHConnError("Неизвестная опция '\(command)'. Справка: \(progName) --help")
        }
        try execSSH(config: try ConfigStore().server(named: command))
    }
}

let progName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ssh-conn"

do {
    try runCLI(progName: progName, arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("Ошибка: \(error.localizedDescription)\n".utf8))
    exit(1)
}
