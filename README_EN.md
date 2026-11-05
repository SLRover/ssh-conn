# ssh-conn

[Русская версия](README.md) | English

![ssh-conn](Assets/ssh-conn-brand/banner/svg/banner-social-dark.svg)

A command-line tool for quick SSH connections: every connection's parameters are
stored in a single file, and you connect by a short name.

```bash
$ ssh-conn list
Host name | Address       | Port | User         | Key
----------+---------------+------+--------------+------------------
prod      | 203.0.113.10  | 22   | root         | ~/.ssh/id_ed25519
stage     | 203.0.113.20  | 2222 | deploy       | ~/.ssh/stage_key

$ ssh-conn prod
# an ssh session to root@203.0.113.10 opens right away
```

## Features

- `list` — a table of all servers;
- the `ssh-conn-gui` graphical app — host groups in the sidebar, a searchable
  table, adding, editing and removing records, connecting in Terminal;
- connecting by server name;
- `add` / `edit` / `remove` — record management, including interactive mode;
- Tab completion of server names in zsh, bash and fish;
- a default port (22) for records without a `Port` field;
- comments and unknown keys are preserved in the configuration file on edits.

## Installation

Requires macOS 14+ and Swift 6.4+.

### CLI

Command Line Tools are enough to build the CLI:

```bash
swift build -c release --product ssh-conn
install -m 755 .build/release/ssh-conn /usr/local/bin/ssh-conn
```

Without installing, you can run it through SwiftPM: `swift run ssh-conn list`.
A ready-made CLI installer (`Install CLI.pkg`) is included in the DMG — see the
"Distribution (DMG)" section.

### GUI

Building the graphical app requires Xcode: starting with the macOS 26 SDK,
SwiftUI uses macros whose plugins are not included in Command Line Tools. If
Xcode is installed in a non-standard location, point to it via `DEVELOPER_DIR`.

```bash
# run from sources
swift run ssh-conn-gui

# build the build/ssh-conn.app bundle
Scripts/build-app.sh
open build/ssh-conn.app
```

### Distribution (DMG)

```bash
Scripts/build-dmg.sh          # build/ssh-conn-1.0.dmg
open build/ssh-conn-1.0.dmg
```

The script builds the app and the CLI installer, verifies the signature and
creates a compressed image with `ssh-conn.app`, an `Applications` shortcut and
an `Install CLI.pkg` package; the checksum and the image contents are verified
automatically. The `debug`/`release` argument selects the configuration
(`release` by default).

To install, drag `ssh-conn.app` to `Applications` and run `Install CLI.pkg` —
it installs the `ssh-conn` command-line tool into `/usr/local/bin` (admin
rights are required). The `ssh-conn` command is then available in the terminal.

By default the app is signed ad-hoc and the CLI package is unsigned, so on
another Mac Gatekeeper will warn about an unidentified developer. For
distribution, sign the app with a Developer ID Application certificate, the
package with a Developer ID Installer certificate, and notarize the image
(requires Xcode with `notarytool`):

```bash
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
INSTALLER_IDENTITY="Developer ID Installer: Name (TEAMID)" \
NOTARIZE=1 APPLE_ID="you@example.com" TEAM_ID="TEAMID" \
NOTARY_PASSWORD="app-specific-password" \
Scripts/build-dmg.sh
```

## Configuration

`~/.ssh-conn.config` is used by default. The path can be overridden with the
`SSH_CONN_CONFIG` environment variable — handy for multiple profiles or for
testing against a copy:

```bash
SSH_CONN_CONFIG=~/tmp/test.config ssh-conn list
```

The file consists of "`Key value`" blocks. Blocks are separated by a blank line,
and lines starting with `#` are treated as comments.

```
# groups that have no hosts yet
Group qa
Group databases

# production
Name prod
Host 203.0.113.10
Port 22
User root
Key ~/.ssh/id_ed25519

Name stage
Group staging
Host 203.0.113.20
Port 2222
User deploy
Key ~/.ssh/stage_key
```

| Field | Required | Description |
|---|---|---|
| `Name` | yes | server name for the command line; starts the block |
| `Host` | yes | host address or IP |
| `Port` | no | SSH port, `22` by default |
| `User` | yes | user name |
| `Key` | yes | path to the private key |
| `Group` | no | logical group; a `Group` line before the first block declares a group without hosts, inside a block it assigns the host to a group |

Parsing details:

- records missing required fields are silently skipped and never show up in `list`;
- field order within a block is arbitrary, unknown keys are ignored but preserved
  by `edit`;
- `Group` is optional and may contain spaces; inside a host block the field is
  preserved on edits, and an empty value in the GUI removes it from the record;
- group declarations (a `Group` line before the first host block) keep a group in
  the GUI even when it has no hosts; the GUI can add such groups and delete them
  once they are empty;
- `~` in a key path expands to the home directory, a relative path is resolved
  from the home directory;
- if the file does not exist, `list`, `edit` and `remove` report an error, while
  `add` creates it along with any missing directories.

## Commands

```
ssh-conn <server>                — connect to the server
ssh-conn list                    — list servers
ssh-conn add <name> [options]    — add a server
ssh-conn remove <name> [--force] — remove a server
ssh-conn edit <name> [options]   — edit a server
ssh-conn completion [shell]      — completion script (zsh, bash, fish)
ssh-conn completion install      — enable shell completion
ssh-conn help                    — show help
```

`add` and `edit` options:

| Option | Description |
|---|---|
| `--host <address>` | host address |
| `--port <port>` | SSH port (1–65535, `22` by default) |
| `--user <name>` | user name |
| `--key <path>` | path to the private key |
| `--group <name>` | server group; an empty value (`--group=`) removes the group |
| `--rename <name>` | new server name (`edit` only) |
| `--force` | overwrite an existing record (`add`) or remove without confirmation (`remove`) |

If at least one record has a `Group` field, the `list` command adds a "Group"
column (configs without groups are printed as before).

Values can also be passed as `--port=2222`. If a terminal is available, missing
`add` and `edit` values are prompted for interactively; without a terminal, a
missing required field is an error (convenient for scripts). If the key file
does not exist, a warning is printed but the record is still saved.

## Shell completion

Tab completes server names, commands, options and group names:

```
$ ssh-conn produ<Tab>
$ ssh-conn production
```

Enable completion for the current shell (detected from `$SHELL`):

```bash
ssh-conn completion install
```

Or set it up manually for a specific shell:

```bash
# zsh: the eval line is added to ~/.zshrc
echo 'eval "$(ssh-conn completion zsh)"' >> ~/.zshrc

# bash: the eval line is added to ~/.bash_profile
echo 'eval "$(ssh-conn completion bash)"' >> ~/.bash_profile

# fish: the completion file is picked up automatically
ssh-conn completion fish > ~/.config/fish/completions/ssh-conn.fish
```

The `completion install [zsh|bash|fish]` command adds a managed block between
`# >>> ssh-conn completion >>>` and `# <<< ssh-conn completion <<<` markers to
`~/.zshrc` or `~/.bash_profile`; running it again updates the block instead of
duplicating it. For fish it writes
`~/.config/fish/completions/ssh-conn.fish`. After installing, open a new
terminal or `source` the modified file.

Without installing, `ssh-conn completion zsh|bash|fish` prints the script, and
the hidden `ssh-conn __complete [prefix]` command prints the candidates for the
shell.

## Graphical interface

`ssh-conn-gui` is a SwiftUI app that works with the same configuration file (the
`SSH_CONN_CONFIG` variable is honored):

- a sidebar with groups and counters, plus a separate "No group" item;
- an "Add group" link at the bottom of the sidebar for creating a group that is
  kept in the config even before it has hosts, with removal of empty groups via
  the context menu;
- a host table with search by name, address, group and user;
- drag-and-drop of a host into a group: grab the handle in the "Name" column and
  drop the host onto a sidebar group or onto "No group" to ungroup it; that item
  stays visible while the config has groups, so it is always a drop target;
- adding, editing and removing records with field and name-uniqueness validation;
  the editor lets you type a new group or pick an existing one, and a new record
  pre-fills the group selected in the sidebar;
- connecting via a double-click on a row or a toolbar button — the SSH session
  opens in Terminal;
- refreshing the list after external file edits (manually and when returning to
  the window), the config path and a "Show in Finder" button in the status bar;
- a warning when the private key file is missing, and choosing a key through the
  standard dialog.

On the first connection macOS may ask for permission to control Terminal (the app
uses AppleScript). If permission is not granted, a temporary `.command` file is
opened in Terminal; if that fails too, the `ssh` command is shown in the error
message.

## Examples

```bash
# add a server without interactive prompts
ssh-conn add prod --host 203.0.113.10 --user root --key ~/.ssh/id_ed25519

# add interactively (asks for missing fields)
ssh-conn add stage

# change the port and user
ssh-conn edit prod --port 2200 --user deploy

# add a server to a group and then remove it
ssh-conn add db --host 203.0.113.30 --user postgres --key ~/.ssh/db_key --group "Databases"
ssh-conn edit db --group=

# rename a record
ssh-conn edit stage --rename staging

# overwrite an existing record completely
ssh-conn add prod --host 203.0.113.11 --user root --key ~/.ssh/id_ed25519 --force

# remove without confirmation
ssh-conn remove staging --force
```

## How it works

To connect, the tool builds the arguments `ssh -i <key> -p <port> user@host` and
replaces its own process with the `ssh` client (`execvp`), so passwords,
passphrase-protected keys, `~/.ssh/config`, the agent and interactive input work
exactly as with a direct `ssh` call. The `ssh` binary is looked up via `PATH`.

## Project layout

```
Sources/
├── SSHConnCore/        # shared library
│   ├── ServerConfig.swift  # record model, block parsing, config path
│   ├── ConfigStore.swift   # reading and editing the configuration file
│   └── SSH.swift           # launching ssh from the CLI
├── SSHConnCLI/         # command-line tool
│   ├── main.swift          # entry point and command parsing
│   ├── CLI.swift           # help, option parsing, commands, table output
│   └── Completion.swift    # completion for zsh, bash and fish
└── SSHConnGUI/         # SwiftUI app
    ├── SSHConnGUIApp.swift # app entry point
    ├── HostListModel.swift # list state and record validation
    ├── HostListView.swift  # host list window
    ├── HostEditorView.swift # add and edit form
    └── TerminalLauncher.swift # connecting through Terminal

Scripts/
├── build-app.sh        # builds build/ssh-conn.app
├── build-cli-pkg.sh    # CLI installer build/ssh-conn-cli-<version>.pkg
└── build-dmg.sh        # packages the app and CLI into build/ssh-conn-<version>.dmg
```

Build: `swift build --product ssh-conn` for the CLI and `Scripts/build-app.sh`
for the app. The CLI installer is built by `Scripts/build-cli-pkg.sh`, and the
ready image by `Scripts/build-dmg.sh`. Running from VS Code is described in
`.vscode/launch.json` (Debug and Release configurations for the CLI and GUI).
There are no automated tests yet.
