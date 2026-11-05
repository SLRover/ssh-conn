import Foundation
import SSHConnCore

// MARK: - Кандидаты для оболочки

/// Скрытая команда для скриптов автодополнения: печатает по одному имени
/// в строке. `--groups` переключает вывод на названия групп.
/// Ошибки чтения конфига намеренно игнорируются: дополнение не должно шуметь.
func completeCandidates(arguments: [String]) {
    var wantGroups = false
    var prefix = ""

    for argument in arguments {
        if argument == "--groups" {
            wantGroups = true
        } else {
            prefix = argument
        }
    }

    let store = ConfigStore()
    let candidates: [String]

    if wantGroups {
        var seen = Set<String>()
        let declared = (try? store.declaredGroups()) ?? []
        let assigned = ((try? store.servers()) ?? []).compactMap(\.group)
        candidates = (declared + assigned).filter { seen.insert($0).inserted }
    } else {
        candidates = ((try? store.servers()) ?? []).map(\.name)
    }

    for name in candidates where name.hasPrefix(prefix) {
        print(name)
    }
}

// MARK: - Оболочки

enum CompletionShell: String, CaseIterable {
    case zsh
    case bash
    case fish

    static func detected() -> CompletionShell {
        let shell = ProcessInfo.processInfo.environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shell, !shell.isEmpty else { return .zsh }
        return CompletionShell(rawValue: (shell as NSString).lastPathComponent) ?? .zsh
    }
}

// MARK: - Команда completion

func runCompletion(progName: String, arguments: [String]) throws {
    let install = arguments.first == "install"
    let shellArguments = install ? Array(arguments.dropFirst()) : arguments

    guard shellArguments.count <= 1 else {
        throw SSHConnError("Лишние аргументы: \(shellArguments.dropFirst().joined(separator: " "))")
    }

    let shell: CompletionShell
    if let raw = shellArguments.first {
        guard let parsed = CompletionShell(rawValue: raw) else {
            throw SSHConnError(
                "Неизвестная оболочка '\(raw)'. Поддерживаются: \(CompletionShell.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        shell = parsed
    } else {
        shell = CompletionShell.detected()
    }

    let command = resolvedProgramPath(basename: progName)

    if install {
        let destination = try installCompletion(for: shell, progName: progName, command: command)
        print("Автодополнение для \(shell.rawValue) установлено: \(destination)")
        print("Откройте новый терминал или выполните: source \(destination)")
    } else {
        print(completionScript(for: shell, progName: progName, command: command))
    }
}

/// Путь для вызова самого себя из скриптов. Если утилита запущена по пути
/// (`/usr/local/bin/ssh-conn`, `swift run`), запоминаем его, иначе полагаемся на `PATH`.
private func resolvedProgramPath(basename: String) -> String {
    let invoked = CommandLine.arguments.first ?? basename
    guard invoked.contains("/") else { return basename }
    return URL(fileURLWithPath: invoked).standardizedFileURL.path
}

/// Домашний каталог для конфигов оболочки; `HOME` учитывается, как в самих оболочках.
private func homeDirectory() -> URL {
    if let home = ProcessInfo.processInfo.environment["HOME"]?
        .trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
        return URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

// MARK: - Установка

/// Добавляет в конфиг оболочки управляемый блок (или файл автодополнения fish)
/// и возвращает путь к изменённому файлу.
private func installCompletion(for shell: CompletionShell, progName: String, command: String) throws -> String {
    let home = homeDirectory()

    switch shell {
    case .fish:
        let file = home.appendingPathComponent(".config/fish/completions/ssh-conn.fish")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try completionScript(for: shell, progName: progName, command: command)
            .write(to: file, atomically: true, encoding: .utf8)
        return file.path

    case .zsh:
        let rc = home.appendingPathComponent(".zshrc")
        try upsertCompletionBlock(
            in: rc,
            command: "eval \"$(\(shellQuote(command)) completion zsh)\""
        )
        return rc.path

    case .bash:
        // Terminal.app запускает bash как login shell, поэтому читается .bash_profile.
        let rc = home.appendingPathComponent(".bash_profile")
        try upsertCompletionBlock(
            in: rc,
            command: "eval \"$(\(shellQuote(command)) completion bash)\""
        )
        return rc.path
    }
}

private let completionBlockBegin = "# >>> ssh-conn completion >>>"
private let completionBlockEnd = "# <<< ssh-conn completion <<<"

private func upsertCompletionBlock(in url: URL, command: String) throws {
    let block = """
    \(completionBlockBegin)
    \(command)
    \(completionBlockEnd)
    """

    var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

    if let begin = content.range(of: completionBlockBegin) {
        let tail = content[begin.lowerBound...]
        if let end = tail.range(of: completionBlockEnd) {
            content.replaceSubrange(begin.lowerBound..<end.upperBound, with: block)
        } else {
            content.replaceSubrange(begin.lowerBound..., with: block)
        }
    } else {
        if !content.isEmpty, !content.hasSuffix("\n") {
            content += "\n"
        }
        if !content.isEmpty {
            content += "\n"
        }
        content += block
    }

    if !content.hasSuffix("\n") {
        content += "\n"
    }
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func shellQuote(_ value: String) -> String {
    guard value.contains(where: { $0.isWhitespace || "'\"$\\`".contains($0) }) else {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Скрипты автодополнения

private func completionScript(for shell: CompletionShell, progName: String, command: String) -> String {
    switch shell {
    case .zsh: return zshCompletionScript(progName: progName, command: command)
    case .bash: return bashCompletionScript(progName: progName, command: command)
    case .fish: return fishCompletionScript(progName: progName, command: command)
    }
}

private func zshCompletionScript(progName: String, command: String) -> String {
    """
    #compdef \(progName)
    # Автодополнение \(progName); сгенерировано командой `\(progName) completion zsh`.

    __ssh_conn_candidates() {
        local -a names
        local prefix=${1:-}
        local kind=${2:-servers}
        if [[ $kind == groups ]]; then
            names=("${(@f)$(command \(shellQuote(command)) __complete --groups "$prefix" 2>/dev/null)}")
        else
            names=("${(@f)$(command \(shellQuote(command)) __complete "$prefix" 2>/dev/null)}")
        fi
        names=(${names:#})
        (( ${#names} )) && compadd -- "${names[@]}"
    }

    _\(progName.replacingOccurrences(of: "-", with: "_"))() {
        local cur=${words[CURRENT]}
        local prev=${words[CURRENT-1]}
        local command=${words[2]}

        if (( CURRENT == 2 )); then
            if [[ $cur == -* ]]; then
                compadd -- --help -h
                return
            fi
            compadd -- list add remove edit completion help
            __ssh_conn_candidates "$cur"
            return
        fi

        if [[ $command == completion ]]; then
            if [[ $cur == -* ]]; then
                compadd -- --help -h
            else
                compadd -- install zsh bash fish
            fi
            return
        fi

        local -a options
        case $command in
            add) options=(--host --port --user --key --group --force --help) ;;
            edit) options=(--host --port --user --key --group --rename --help) ;;
            remove|rm) options=(--force --help) ;;
        esac

        if [[ $cur == -* ]]; then
            (( ${#options} )) && compadd -- "${options[@]}"
            return
        fi

        case $prev in
            --group) __ssh_conn_candidates "$cur" groups ;;
            --host|--port|--user|--key|--rename) ;;
            *)
                case $command in
                    remove|rm|edit) __ssh_conn_candidates "$cur" ;;
                esac
                ;;
        esac
    }

    if (( $+functions[compdef] )); then
        compdef _\(progName.replacingOccurrences(of: "-", with: "_")) \(progName)
    else
        autoload -Uz compinit && compinit -i
        compdef _\(progName.replacingOccurrences(of: "-", with: "_")) \(progName)
    fi
    """
}

private func bashCompletionScript(progName: String, command: String) -> String {
    """
    # Автодополнение \(progName); сгенерировано командой `\(progName) completion bash`.

    __ssh_conn_candidates() {
        local prefix=${1:-}
        local kind=${2:-servers}
        local item escaped
        if [[ $kind == groups ]]; then
            while IFS= read -r item; do
                [[ -n $item && $item == "$prefix"* ]] || continue
                printf -v escaped '%q' "$item"
                COMPREPLY+=("$escaped")
            done < <(command \(shellQuote(command)) __complete --groups "$prefix" 2>/dev/null)
        else
            while IFS= read -r item; do
                [[ -n $item && $item == "$prefix"* ]] || continue
                printf -v escaped '%q' "$item"
                COMPREPLY+=("$escaped")
            done < <(command \(shellQuote(command)) __complete "$prefix" 2>/dev/null)
        fi
    }

    _\(progName.replacingOccurrences(of: "-", with: "_"))() {
        local cur=${COMP_WORDS[COMP_CWORD]}
        local prev=${COMP_WORDS[COMP_CWORD-1]}
        local command options=""
        COMPREPLY=()

        if (( COMP_CWORD == 1 )); then
            if [[ $cur == -* ]]; then
                COMPREPLY=($(compgen -W "--help -h" -- "$cur"))
                return
            fi
            COMPREPLY=($(compgen -W "list add remove edit completion help" -- "$cur"))
            __ssh_conn_candidates "$cur"
            return
        fi

        command=${COMP_WORDS[1]}

        if [[ $command == completion ]]; then
            COMPREPLY=($(compgen -W "install zsh bash fish --help -h" -- "$cur"))
            return
        fi

        case $command in
            add) options="--host --port --user --key --group --force --help" ;;
            edit) options="--host --port --user --key --group --rename --help" ;;
            remove|rm) options="--force --help" ;;
        esac

        if [[ $cur == -* ]]; then
            COMPREPLY=($(compgen -W "$options" -- "$cur"))
            return
        fi

        case $prev in
            --group) __ssh_conn_candidates "$cur" groups ;;
            --host|--port|--user|--key|--rename) ;;
            *)
                case $command in
                    remove|rm|edit) __ssh_conn_candidates "$cur" ;;
                esac
                ;;
        esac
    }

    complete -F _\(progName.replacingOccurrences(of: "-", with: "_")) \(progName)
    """
}

private func fishCompletionScript(progName: String, command: String) -> String {
    let command = shellQuote(command)
    return """
    # Автодополнение \(progName); сгенерировано командой `\(progName) completion fish`.

    complete -c \(progName) -f
    complete -c \(progName) -n 'not __fish_seen_subcommand_from list add remove rm edit completion help' -a 'list add remove edit completion help'
    complete -c \(progName) -n 'not __fish_seen_subcommand_from list add remove rm edit completion help' -a '(command \(command) __complete (commandline -ct) 2>/dev/null)'

    complete -c \(progName) -n '__fish_seen_subcommand_from add' -l host -r
    complete -c \(progName) -n '__fish_seen_subcommand_from add' -l port -r
    complete -c \(progName) -n '__fish_seen_subcommand_from add' -l user -r
    complete -c \(progName) -n '__fish_seen_subcommand_from add' -l key -r
    complete -c \(progName) -n '__fish_seen_subcommand_from add' -l group -r -a '(command \(command) __complete --groups (commandline -ct) 2>/dev/null)'
    complete -c \(progName) -n '__fish_seen_subcommand_from add' -l force

    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l host -r
    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l port -r
    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l user -r
    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l key -r
    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l group -r -a '(command \(command) __complete --groups (commandline -ct) 2>/dev/null)'
    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l rename -r
    complete -c \(progName) -n '__fish_seen_subcommand_from edit' -l force

    complete -c \(progName) -n '__fish_seen_subcommand_from remove rm' -l force

    complete -c \(progName) -n '__fish_seen_subcommand_from remove rm edit' -a '(command \(command) __complete (commandline -ct) 2>/dev/null)'
    complete -c \(progName) -n '__fish_seen_subcommand_from completion' -a 'install zsh bash fish'
    """
}
