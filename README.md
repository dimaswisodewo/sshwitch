# sshwitch

A command-line tool for managing SSH keys across multiple Git identities on a single machine.

If you work with more than one GitHub/GitLab account (e.g., work and personal), `sshwitch` removes the pain of configuring `~/.ssh/config` host aliases or changing remote URLs. It uses Git's built-in `core.sshCommand` local config to bind a specific SSH key to a specific repository — no global side effects.

---

## The Problem

Using multiple Git accounts on one machine typically forces you to:

- Write complex `~/.ssh/config` `Host` blocks
- Change remote URLs from `github.com` to `github.com-work`
- Remember which key goes with which account

One mistake and your `git push` authenticates as the wrong identity, or fails entirely.

## The Solution

`sshwitch` handles key generation, permission management, and repository binding in a few short commands. The key insight is Git's `core.sshCommand`, a per-repository setting that tells Git exactly which SSH key to use — without touching global config or remote URLs.

```
git config core.sshCommand "ssh -i ~/.ssh/work -o IdentitiesOnly=yes"
```

`sshwitch link` sets this for you automatically.

---

## Installation

### Homebrew (recommended)

```bash
brew install dimaswisodewo/tools/sshwitch
```

### Build from source

Requires Swift 6.0+ and macOS 14+.

```bash
git clone https://github.com/dimaswisodewo/sshwitch.git
cd sshwitch
swift build -c release
cp .build/release/sshwitch /usr/local/bin/sshwitch
```

---

## Quick Start

```bash
# 1. Generate a new SSH key
sshwitch gen --name work --email you@company.com

# 2. Add the printed public key to GitHub/GitLab (Settings → SSH Keys)

# 3. Add the key to the SSH agent
sshwitch add --key work

# 4. Link the key to a repository
cd ~/code/work-project
sshwitch link --key work

# 5. Verify everything is working
sshwitch doctor
```

That's it. All `git push`, `git pull`, and `git fetch` operations in `~/code/work-project` will now use the `work` key automatically.

---

## Commands

### `sshwitch gen` — Generate an SSH key

Creates a new ed25519 SSH key pair in `~/.ssh/`.

```
USAGE: sshwitch gen --name <name> --email <email> [--add-to-agent] [--dry-run]

OPTIONS:
  --name <name>     Name for the key file (stored as ~/.ssh/<name>)
  --email <email>   Email address to embed as the key comment
  --add-to-agent    Add the key to the SSH agent immediately
  --dry-run         Print what would happen without doing it
```

**Examples:**

```bash
# Generate a key for your work account
sshwitch gen --name work --email you@company.com

# Generate a key and add it to the agent in one step
sshwitch gen --name personal --email you@gmail.com --add-to-agent

# Preview what would happen without making changes
sshwitch gen --name test --email test@test.com --dry-run
```

**What it does:**
1. Runs `ssh-keygen -t ed25519` to generate the key pair
2. Sets file permissions to `600` (required by SSH)
3. Optionally adds the key to `ssh-agent` via `ssh-add`
4. Prints the public key so you can copy it to GitHub/GitLab

The generated files:
- `~/.ssh/<name>` — private key (keep this secret)
- `~/.ssh/<name>.pub` — public key (add this to GitHub/GitLab)

---

### `sshwitch add` — Add a key to the SSH agent

Loads an existing SSH private key into the running SSH agent so it is available for Git operations and SSH connections.

```
USAGE: sshwitch add --key <key>

OPTIONS:
  --key <key>       Key name (e.g., work) or absolute path to private key
```

**Examples:**

```bash
# Add by key name
sshwitch add --key work

# Add by path
sshwitch add --key ~/.ssh/personal
```

**What it does:**

Runs `ssh-add <key-path>` to load the key into the agent. If the agent is not running, the command exits with an error.

---

### `sshwitch link` — Link a key to a repository

Configures a specific Git repository to use a given SSH key for all remote operations.

```
USAGE: sshwitch link --key <key> [--path <path>] [--dry-run]

OPTIONS:
  --key <key>       Key name (e.g., work) or absolute path to private key
  --path <path>     Path to the git repository (defaults to current directory)
  --dry-run         Print what would happen without doing it
```

**Examples:**

```bash
# Link from inside the repository directory
cd ~/code/work-project
sshwitch link --key work

# Link by specifying the repo path explicitly
sshwitch link --key personal --path ~/code/my-blog

# Preview the git config command without running it
sshwitch link --key work --dry-run
```

**What it does:**

Runs the following inside the target repository:

```bash
git config core.sshCommand "ssh -i ~/.ssh/work -o IdentitiesOnly=yes"
```

This is a **local** repository setting — it only affects that one repo and leaves all other repos and your global SSH config untouched. Remote URLs are never modified.

**Verify the link was set:**

```bash
git config core.sshCommand
# → ssh -i /Users/you/.ssh/work -o IdentitiesOnly=yes
```

---

### `sshwitch unlink` — Unlink a key from a repository

Removes the SSH key binding from a Git repository, reverting to Git's default key resolution.

```
USAGE: sshwitch unlink [--path <path>] [--dry-run]

OPTIONS:
  --path <path>     Path to the git repository (defaults to current directory)
  --dry-run         Print what would happen without doing it
```

**Examples:**

```bash
# Unlink from inside the repository directory
cd ~/code/work-project
sshwitch unlink

# Unlink by specifying the repo path explicitly
sshwitch unlink --path ~/code/my-blog

# Preview what would happen without making changes
sshwitch unlink --dry-run
```

**What it does:**

1. Confirms the target is a valid Git repository
2. Shows the currently linked SSH key
3. Runs `git config --unset core.sshCommand` to remove the binding

If no key is linked to the repo, it reports that and exits cleanly.

---

### `sshwitch list` — List SSH keys

Shows all SSH key pairs found in `~/.ssh/`.

```
USAGE: sshwitch list
```

**Example output:**

```
NAME                           TYPE         CREATED
------------------------------------------------------------
personal                       ed25519      4/1/26
work                           ed25519      4/3/26
```

Only files that have both a private key and a matching `.pub` file are shown.

---

### `sshwitch doctor` — Run diagnostics

Checks your SSH setup for common configuration problems and connectivity issues.

```
USAGE: sshwitch doctor
```

**Example output:**

```
sshwitch doctor — running checks...

[sshwitch] Checking ~/.ssh directory permissions (must be 700)...
[PASS] ~/.ssh permissions: 700 ✓

[sshwitch] Checking private key file permissions (must be 600)...
[PASS]   work permissions: 600 ✓
[PASS]   personal permissions: 600 ✓

[sshwitch] Checking SSH connectivity to remote Git hosts...
[PASS] GitHub SSH connectivity: reachable ✓
[PASS] GitLab SSH connectivity: reachable ✓

✓ All checks passed.
```

**What it checks:**

| Check | Why it matters |
|---|---|
| `~/.ssh` permissions (`700`) | Prevents other users on the system from reading your keys |
| Private key permissions (`600`) | SSH refuses to use keys that are too permissive |
| GitHub/GitLab connectivity | Confirms your network can reach the Git host over SSH |

**If a check fails**, the output includes a fix command:

```
[FAIL] ~/.ssh permissions: Expected 700, got 755. Fix: chmod 700 ~/.ssh
[FAIL]   work permissions: Expected 600, got 644. Fix: chmod 600 ~/.ssh/work
```

---

## Common Workflows

### Work and personal accounts on the same machine

```bash
# Set up work identity
sshwitch gen --name work --email alice@company.com
sshwitch add --key work
# Add ~/.ssh/work.pub to your work GitHub account

# Set up personal identity
sshwitch gen --name personal --email alice@gmail.com
sshwitch add --key personal
# Add ~/.ssh/personal.pub to your personal GitHub account

# Link each repo to the correct key
sshwitch link --key work --path ~/code/work-project
sshwitch link --key personal --path ~/code/side-project

# Confirm setup
sshwitch doctor
```

### Switching a repository to a different key

Just run `sshwitch link` again — it overwrites the existing `core.sshCommand` setting:

```bash
cd ~/code/some-repo
sshwitch link --key personal
```

### Using the `--dry-run` flag

Append `--dry-run` to any write command to see what `sshwitch` would do without making changes:

```bash
sshwitch gen --name test --email test@test.com --dry-run
# [dry-run] Would run: ssh-keygen -t ed25519 -C "test@test.com" -f /Users/you/.ssh/test -N ""
# [dry-run] Would set permissions 600 on /Users/you/.ssh/test and /Users/you/.ssh/test.pub

sshwitch link --key work --dry-run
# [dry-run] Would run in /Users/you/code/work-project:
# [dry-run]   git config core.sshCommand "ssh -i /Users/you/.ssh/work -o IdentitiesOnly=yes"
```

### Removing a key link from a repository

```bash
cd ~/code/some-repo
sshwitch unlink
```

Git will fall back to its default SSH behavior. Use `--dry-run` to preview first.

---

## How It Works

`sshwitch link` sets a **local** Git config value for each repository:

```
core.sshCommand = ssh -i ~/.ssh/<key-name> -o IdentitiesOnly=yes
```

- `-i ~/.ssh/<key-name>` — tells SSH which private key to use
- `-o IdentitiesOnly=yes` — prevents SSH from trying other keys loaded in the agent

This value lives in `.git/config` inside the repository and overrides both `~/.gitconfig` and `~/.ssh/config` for that repo only.

---

## Requirements

- macOS 14 or later
- Git
- `ssh-keygen` (included with macOS)
- `ssh-add` (included with macOS, needed for `sshwitch add` and `gen --add-to-agent`)

---

## Building from Source

```bash
git clone https://github.com/dimaswisodewo/sshwitch.git
cd sshwitch

# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run sshwitch --help
```

---

## License

MIT
