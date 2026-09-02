# caveman-kit

Installer kit that wires the `caveman` Claude Code skill into an existing
Claude Code configuration.

`install.sh` injects three hook entries (`SessionStart`, `SubagentStart`, `UserPromptSubmit`)
into `settings.json` and a small badge block into `statusline.sh`. Everything
it touches is backed up under `~/.caveman-kit/backup/` so `uninstall.sh` can
restore the original configuration exactly.

## Requirements

- `node` on `PATH`

## Usage

### Quick install (clone-free)

```bash
curl -fsSL https://raw.githubusercontent.com/nj4x/caveman-kit/master/bootstrap.sh | bash
```

This also installs the `caveman` skill itself if you don't already have it —
nothing else to do first.

To uninstall:

```bash
~/.local/share/caveman-kit/uninstall.sh
```

### Manual install from checkout

```bash
./install.sh
```

To uninstall:

```bash
./uninstall.sh
```

### Damaged install recovery

If the install state is corrupted, remove both directories manually:

```bash
rm -rf ~/.local/share/caveman-kit ~/.caveman-kit
```

Then manually remove hook entries from `~/.claude/settings.json` that reference `caveman-activate.js` or `caveman-mode-tracker.js`.

## The caveman skill

`install.sh` expects the `caveman` skill at
`$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md` and installs it for you by
default (pinned to `JuliusBrussee/caveman@v2.2.0`, skill only — no CLI,
proxy, or binaries) via:

```bash
npx skills add JuliusBrussee/caveman@v2.2.0 --skill caveman -g --copy
```

If you'd rather manage that yourself — the install runs `npx` against a
third-party GitHub repo — pass `--no-install-skill` (or set
`CAVEMAN_KIT_INSTALL_SKILL=0`) and `install.sh` will exit with the command
above instead of running it:

```bash
curl -fsSL https://raw.githubusercontent.com/nj4x/caveman-kit/master/bootstrap.sh | bash -s -- --no-install-skill
./install.sh --no-install-skill
```

See [caveman](https://github.com/JuliusBrussee/caveman) for details.

The installer also patches the skill's frontmatter with
`disable-model-invocation: true` (original backed up and restored byte-exact
on uninstall). If the kit auto-installed the skill, `uninstall.sh` removes it
again; a pre-existing skill is only ever restored, never removed.

## Per-repository mode

The mode is repo-scoped when the repository root contains a `.claude/`
directory: `/caveman <mode>` then reads and writes
`<repo>/.claude/.caveman-mode` (auto-added to `.git/info/exclude`, so it
stays local to your clone). Without a repo or `.claude/` directory, the
global `~/.claude/.caveman-active` flag is used, as before. The repo file is
also the persisted default for that repo — a new session starts in whatever
mode was last set there. Hand-editing the file works too.

## Layout

- `install.sh` / `uninstall.sh` — entry points
- `hooks/` — hook scripts injected into `settings.json`
- `lib/` — patch helpers shared by the hooks
