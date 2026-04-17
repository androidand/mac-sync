# mac-sync

Scripts and dotfiles to keep two Macs in sync: SSH access, `~/.ssh`, `~/.claude`
(Claude Code config + skills), OpenCode config, and shell dotfiles.

Both Macs are treated as peers — either can be the "source of truth" at any time.

## Order of operations

| # | Step | Where | Script |
|---|------|-------|--------|
| 1 | Enable Remote Login (password auth stays on during bootstrap) | Both Macs | `scripts/01-enable-ssh.sh` |
| 2 | Generate `ed25519` keypair if missing | Both Macs | `scripts/02-generate-key.sh` |
| 3 | Push this Mac's public key to the peer via `ssh-copy-id` | Both Macs, each pointing at the other | `scripts/03-authorize-peer.sh user@peer.local` |
| 4 | Rsync `~/.ssh` between Macs (keys never go to git) | Pick one Mac | `scripts/04-sync-ssh-folder.sh (push\|pull) user@peer.local` |
| 5 | Init the `dotfiles/` subfolder as a git repo | Source-of-truth Mac | `scripts/05-init-dotfiles-repo.sh` |
| 6 | **Only after key login works both ways:** lock sshd to key-only | Both Macs | `scripts/06-lockdown-key-only.sh` |
| 7 | Symlink dotfiles into `$HOME` | Both Macs | `dotfiles/bootstrap.sh` |

Step 3 uses `ssh-copy-id`, which prompts for the peer's macOS login password
once. `.local` resolution works via mDNS/Bonjour on the local network; you can
also pass a LAN IP or a Tailscale/100.x name.

Step 6 is intentionally last and reversible. Do NOT run it until you've
confirmed `ssh -o PreferredAuthentications=publickey user@peer.local` succeeds
from both Macs.

## What lives where

- `scripts/` — setup scripts. Idempotent where possible.
- `dotfiles/` — the actual config files, committed to git and symlinked into `$HOME`.
  - `dotfiles/claude/` → `~/.claude/` (ephemeral state and credentials excluded)
  - `dotfiles/opencode/` → `~/.config/opencode/` (`auth.json` excluded)
  - `dotfiles/shell/` → `~/.zshrc`, `~/.zprofile`, …
- `dotfiles/.gitignore` — excludes every secret-bearing / ephemeral file.

## Security notes

- `~/.ssh` is synced with rsync, **not git**. Private keys never go to a remote repo.
- `opencode/auth.json` holds API tokens — also rsync, not git.
- Key-only SSH is enforced by `/etc/ssh/sshd_config.d/100-no-password.conf`.
  To revert: delete that file and reload sshd.
- Step 6 validates `sshd -t` before reloading so you can't lock yourself out via
  a typo in the drop-in.

## Getting this on the other Mac

Once this folder is pushed to `git@github.com:androidand/mac-sync.git`:

```bash
git clone git@github.com:androidand/mac-sync.git ~/dev/mac-sync
cd ~/dev/mac-sync
./scripts/01-enable-ssh.sh
./scripts/02-generate-key.sh
./scripts/03-authorize-peer.sh andreas@<other-mac>.local
# …etc
```
