# sshwitch

`sshwitch` makes SSH key selection explicit when you use multiple Git or SSH identities on one Mac. It can choose a default key for selected hosts or override the key for one Git repository.

## Install

```bash
brew install dimaswisodewo/tools/sshwitch
```

Building from source requires Swift 6 and macOS 13 or later:

```bash
swift build -c release
cp .build/release/sshwitch /usr/local/bin/sshwitch
```

## The two selection modes

### Global default

Use one key by default for selected SSH hosts. This is convenient when most repositories for a provider use the same account.

```bash
sshwitch switch --key work --host github.com --host gitlab.com
```

The hosts are remembered. Switching keys later is shorter:

```bash
sshwitch switch --key personal
```

Disable the global default without forgetting the hosts:

```bash
sshwitch switch --off
```

### Repository override

Force one repository to use a particular key, regardless of the global default:

```bash
cd ~/code/work-project
sshwitch link --key work
```

Remove the override and return to global SSH behavior:

```bash
sshwitch unlink
```

A repository override always takes precedence over the global default. `sshwitch status` explains which key will win.

## First-time workflow

```bash
# Generate a key pair and load it into ssh-agent.
sshwitch gen --name work --email you@company.com --add-to-agent

# Add ~/.ssh/work.pub to your GitHub or GitLab account, then choose its hosts.
sshwitch switch --key work --host github.com --host gitlab.com

# Inspect the effective selection and test the setup.
sshwitch status
sshwitch doctor
```

## Commands

### Generate and load keys

```bash
sshwitch gen --name work --email you@company.com
sshwitch gen --name work --email you@company.com --add-to-agent
sshwitch add --key work
sshwitch list
```

`gen` creates an ed25519 private/public key pair under `~/.ssh`. `add` loads an existing private key into the current SSH agent. `list` finds files that have a matching `.pub` file and marks keys active globally or in the current repository.

### Choose a global default

```bash
sshwitch switch --key work --host github.com
sshwitch switch --key personal       # reuses remembered hosts
sshwitch switch --off
sshwitch status
```

Hosts must be literal hostnames or IP addresses. Wildcards are intentionally not accepted because `sshwitch` validates and reports the effective configuration for every host.

### Override one repository

```bash
sshwitch link --key work
sshwitch link --key personal --path ~/code/blog
sshwitch unlink
sshwitch unlink --path ~/code/blog
```

Neither command changes the repository remote URL.

### Preview and troubleshoot

Write commands support `--dry-run`, which reports the intended result without changing files:

```bash
sshwitch switch --key work --host github.com --dry-run
sshwitch link --key work --dry-run
sshwitch unlink --dry-run
sshwitch gen --name test --email test@example.com --dry-run
```

Add `--verbose` to any command to show paths, underlying commands, configuration precedence, validation details, or captured diagnostic output:

```bash
sshwitch status --verbose
sshwitch doctor --verbose
```

`NO_COLOR=1` disables ANSI colors. Output remains understandable without colors.

## How it works

For the global default, `sshwitch` adds this top-level line to `~/.ssh/config` once:

```sshconfig
Include ~/.ssh/sshwitch.conf
```

It then owns and atomically updates `~/.ssh/sshwitch.conf`:

```sshconfig
Host github.com gitlab.com
  IdentityFile "/Users/you/.ssh/work"
  IdentitiesOnly yes
```

Before integrating with an existing config, `sshwitch` creates a timestamped backup. It validates the complete proposed configuration with `ssh -G` before committing it and uses permissions `0600`. Existing SSH rules remain untouched. Because OpenSSH accumulates multiple `IdentityFile` directives, `status` and `doctor` warn if another matching rule adds fallback identities.

For a repository override, `sshwitch link` writes a local Git setting in `.git/config`:

```ini
core.sshCommand = ssh -i /Users/you/.ssh/work -o IdentitiesOnly=yes
```

Git passes that command directly to SSH, so it takes precedence over the user-level default for that repository. `unlink` removes only this local value.

## Diagnostics

`sshwitch doctor` checks:

- `~/.ssh` directory permissions (`0700`)
- private key permissions (`0600`)
- the managed include and selected global identities
- `IdentitiesOnly` and additional fallback identities
- SSH connectivity for the current repository's effective key

Failed checks return a nonzero exit status and include an actionable fix. Connectivity checks may add a previously unseen host to `known_hosts`, matching OpenSSH's `accept-new` behavior.

## Safety guarantees

- The system-wide `/etc/ssh/ssh_config` is never modified.
- Existing user SSH rules are preserved rather than rewritten.
- An unrelated pre-existing `~/.ssh/sshwitch.conf` is never overwritten.
- Symlinked `~/.ssh/config` files keep their symlink.
- Candidate configuration is validated before installation.
- Private-key contents are never printed.

## License

MIT
