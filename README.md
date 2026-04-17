# mac-sync

Scripts and dotfiles to keep two Macs in sync: SSH access, `~/.ssh`, `~/.claude`
(Claude Code config + skills), `~/.config/opencode/`, shell dotfiles, and an
optional shared env-var file.

Both Macs are peers — either can be the source of truth at any time.

## The flow

Call them **Mac A** (where this repo was first set up) and **Mac B** (the other Mac).
They need to be reachable from each other — same LAN works via mDNS
(`.local` hostnames), or you can pass a LAN IP / Tailscale name anywhere you
see `andreas@<mac>.local` below.

### 0. Get the repo on both Macs

```bash
# Mac A: first push
cd ~/dev/mac-sync
git push -u origin main

# Mac B: clone
git clone git@github.com:androidand/mac-sync.git ~/dev/mac-sync
```

### 1. Enable SSH on both Macs (password auth still on)

```bash
# Mac A
./scripts/01-enable-ssh.sh

# Mac B
./scripts/01-enable-ssh.sh
```

This turns on Remote Login and prints the Mac's `.local` hostname and LAN IPs.
Password auth stays on — we need it for the next step.

### 2. Ensure each Mac has an ed25519 keypair

```bash
# Mac A
./scripts/02-generate-key.sh

# Mac B
./scripts/02-generate-key.sh
```

### 3. Exchange public keys (each Mac authorizes the other)

```bash
# On Mac A, point at Mac B:
./scripts/03-authorize-peer.sh andreas@macB.local

# On Mac B, point at Mac A:
./scripts/03-authorize-peer.sh andreas@macA.local
```

Uses `ssh-copy-id` under the hood — prompts for the *peer's* macOS password
once, then appends your public key to the peer's `authorized_keys`. After
each invocation it verifies key-based login works and refuses to proceed
otherwise.

After both runs: `ssh andreas@<other>.local` works password-free from either
side.

### 4. One-time `~/.ssh` sync (pick a source-of-truth Mac)

```bash
# On Mac A (canonical), push .ssh to Mac B:
./scripts/04-sync-ssh-folder.sh push andreas@macB.local
```

`authorized_keys` and `known_hosts` are merged (sorted + deduped). Everything
else (config, keys, etc.) is mirrored with `700/600` modes. Keys never touch
git.

### 5. Import current configs into `dotfiles/` and push (source-of-truth Mac)

```bash
# Mac A
./dotfiles/pull-from-home.sh
git add dotfiles
git commit -m "Import configs from Mac A"
git push
```

`pull-from-home.sh` respects the `.gitignore`, so ephemeral state and
credential files are left out.

### 6. Symlink dotfiles into `$HOME` on both Macs

```bash
# Mac A
./dotfiles/bootstrap.sh

# Mac B (after a git pull)
git pull
./dotfiles/bootstrap.sh
```

Existing files are backed up to `~/.dotfiles-backup/<timestamp>/`, then
replaced with symlinks pointing into the repo. From here on:

- Edits under `~/.claude/skills/foo` ARE edits in the repo.
- Commit + push on one Mac → `git pull` on the other and changes appear.
- `~/.config/opencode/*.json` (the non-auth parts) syncs the same way.

### 7. (Optional) Shared env-var file

A small script for API keys and tokens you want on both machines without
committing them to git.

```bash
# Put exports in ~/.config/mac-sync/env.sh (mode 600) on whichever Mac has them:
mkdir -p ~/.config/mac-sync
chmod 700 ~/.config/mac-sync
cat >> ~/.config/mac-sync/env.sh <<'EOF'
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
EOF
chmod 600 ~/.config/mac-sync/env.sh

# Then sync to the other Mac:
./scripts/07-sync-env.sh push andreas@macB.local   # or: pull
```

The script **never overwrites a var that is populated on the receiving side
without asking**. For each conflict it shows masked values (first 4 chars +
last 2 chars) and lets you answer `y` / `N` / `s`=show full values.

To make the vars available in every shell, add one line to `~/.zshenv`
(you can keep that in `dotfiles/shell/.zshenv` so both Macs get it):

```bash
[ -r ~/.config/mac-sync/env.sh ] && . ~/.config/mac-sync/env.sh
```

### 8. Lock sshd to key-only (BOTH Macs, once everything above works)

```bash
./scripts/06-lockdown-key-only.sh
```

This is intentionally the last step. It writes
`/etc/ssh/sshd_config.d/100-no-password.conf`, runs `sshd -t` for validation
before reload, and prints the exact revert command.

## What lives where

```
scripts/
  01-enable-ssh.sh          Enable Remote Login (sshd), keep password auth on
  02-generate-key.sh        Create ed25519 keypair if missing
  03-authorize-peer.sh      ssh-copy-id to peer, verify key login
  04-sync-ssh-folder.sh     rsync ~/.ssh peer-to-peer (merges sensitive files)
  05-init-dotfiles-repo.sh  Seed a git repo from the dotfiles folder
  06-lockdown-key-only.sh   Disable password SSH auth. Run LAST.
  07-sync-env.sh            Interactive env-var sync via ~/.config/mac-sync/env.sh
dotfiles/
  bootstrap.sh              Create symlinks from repo into $HOME
  pull-from-home.sh         Copy current $HOME configs into this repo
  .gitignore                Excludes every secret / ephemeral file
  claude/                   -> ~/.claude/
  opencode/                 -> ~/.config/opencode/  (auth.json gitignored)
  shell/                    -> ~/.zshrc, ~/.zshenv, ~/.zprofile, ...
```

## Syncing `~/.config/opencode/`

Yes — it's symlinked by `bootstrap.sh` exactly the same way `~/.claude/` is.

Two files are **excluded** from git and need separate handling:

- `auth.json` — holds API tokens. Options: (a) log in to OpenCode separately
  on each Mac; (b) rsync it:
  ```bash
  rsync -av ~/.config/opencode/auth.json andreas@macB.local:.config/opencode/
  ```
  Since `~/.config/opencode` is a symlink to the repo, the `auth.json` file
  ends up inside the repo folder on disk but stays gitignored.
- Any per-machine cache/state paths OpenCode may create — add them to
  `dotfiles/.gitignore` as they appear.

## Security notes

- `~/.ssh` private keys never go to git. Synced via rsync.
- `opencode/auth.json` and `~/.config/mac-sync/env.sh` are gitignored.
- `06-lockdown-key-only.sh` refuses to run if `~/.ssh/authorized_keys` is
  empty, and validates `sshd -t` before reloading, so you can't lock yourself
  out via a typo.
- Reverting the lockdown: `sudo rm /etc/ssh/sshd_config.d/100-no-password.conf
  && sudo launchctl kickstart -k system/com.openssh.sshd`
