# dotfiles

Synced config for Claude Code, OpenCode, and shell, tracked in git. Symlinked
into `$HOME` by `bootstrap.sh`.

## Layout

```
dotfiles/
├── bootstrap.sh        # idempotent symlink installer
├── pull-from-home.sh   # copy current $HOME configs INTO this repo
├── claude/             # -> ~/.claude/ (excluding ephemeral state)
├── opencode/           # -> ~/.config/opencode/ (auth.json excluded)
└── shell/              # -> ~/.zshrc, ~/.zprofile, etc.
```

## First time on a new Mac

```bash
git clone git@github.com:<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

Existing files at each target are backed up to `~/.dotfiles-backup/<timestamp>/`
before being replaced with a symlink.

## Importing configs from the current Mac

Run `./pull-from-home.sh` on the Mac that holds your current configs. It copies
(does not symlink) `~/.claude`, `~/.config/opencode`, and listed shell files
into this repo, respecting `.gitignore`. Then review the diff and commit.

## Updating after config changes

Because `bootstrap.sh` uses symlinks, any edit you make at `~/.claude/...` is
already an edit in the repo. Just `git add -p && git commit && git push`.

## Secrets policy

- SSH private keys → **never in this repo**, synced via `scripts/04-sync-ssh-folder.sh`.
- `opencode/auth.json` → gitignored, synced via rsync.
- Claude Code credentials → gitignored.
