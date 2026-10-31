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

To update:

```bash
~/.local/share/caveman-kit/update.sh
```

To uninstall:

```bash
~/.local/share/caveman-kit/uninstall.sh
```

### Manual install from checkout

```bash
./install.sh
```

To update:

```bash
./update.sh
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

## The caveman and ultracave skills

`install.sh` expects the `caveman` skill at
`$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md` and installs it for you by
default, at the newest upstream release tag (skill only — no CLI, proxy, or
binaries), one `npx` call per skill:

```bash
npx skills add JuliusBrussee/caveman@<tag> --skill caveman -a claude-code -g --copy
```

`ultra` mode uses upstream's separate `ultracave` skill, so the installer adds
it the same way when it is missing (`--skill ultracave`). Without it, `ultra`
falls back to the caveman rules. Set `CAVEMAN_KIT_SKILL_REF=vX.Y.Z` (at least
`v3.1.0`) to hold a release tag; the hold is kept in the manifest until
`CAVEMAN_KIT_SKILL_REF=latest` clears it.

If you'd rather manage that yourself — the install runs `npx` against a
third-party GitHub repo — pass `--no-install-skill` (or set
`CAVEMAN_KIT_INSTALL_SKILL=0`) and `install.sh` will exit with the command
above instead of running it:

```bash
curl -fsSL https://raw.githubusercontent.com/nj4x/caveman-kit/master/bootstrap.sh | bash -s -- --no-install-skill
./install.sh --no-install-skill
```

See [caveman](https://github.com/JuliusBrussee/caveman) for details.

`update.sh` checks upstream for a newer release on every run and upgrades the
skills the kit installed. A skill you installed yourself is never touched;
upgrade it with the command above. If you installed with
`--no-install-skill`, or an older kit install left `caveman` under your
management, `update.sh` will not install `ultracave`; run `npx skills add JuliusBrussee/caveman@<tag> --skill ultracave -a
claude-code -g --copy` with `<tag>` set to the newest release on the
[releases page](https://github.com/JuliusBrussee/caveman/releases). Existing
installs need two `update.sh` runs to migrate: the first run executes the old
script. `update.sh` also re-resolves where the hooks read `SKILL.md` from, so
moving or replacing the skill directory does not leave the hooks pointing at a
stale copy.

The installer also patches the `caveman` skill's frontmatter with
`disable-model-invocation: true` (original backed up and restored byte-exact
on uninstall). If the kit auto-installed a skill, `uninstall.sh` removes it
again; a pre-existing skill is only ever restored, never removed.

## Per-repository mode

The mode is repo-scoped when the repository root contains a `.claude/`
directory: `/caveman <mode>` then reads and writes
`<repo>/.claude/.caveman-mode` (auto-added to `.git/info/exclude`, so it
stays local to your clone). Without a repo or `.claude/` directory, the
global `~/.claude/.caveman-active` flag is used, as before. The repo file is
also the persisted default for that repo — a new session starts in whatever
mode was last set there. Hand-editing the file works too.

## Desktop badge

The Claude desktop app's Code tab may not render `statusline.sh`, so it shows
no mode badge. The optional `caveman-badge` mod draws one above the prompt: a
chip of three bones, where the number of solid bones is the mode (one for
`lite`, two for `full`, three for `ultra`; unused bones are faded). Hover the
chip to see the mode name. Version 0.1.0 drew text (`[CAVEMAN:ULTRA]`); update
the plugin to get the chip. It is read-only, desktop
only (the terminal keeps the `statusline.sh` badge), and needs Claude Code
v2.1.286 or later; older desktop builds show nothing.

```
/plugin marketplace add nj4x/caveman-kit
/plugin install caveman-badge@caveman-kit
```

The badge polls the mode flag every 2 seconds and draws nothing once
`~/.caveman-kit/hooks/caveman-activate.js` is gone, so it goes blank after
`./uninstall.sh`. `uninstall.sh` does not remove the mod: run
`/plugin uninstall caveman-badge@caveman-kit`. If you moved your config with
`CLAUDE_CONFIG_DIR` and the desktop app does not pass it to mods, the badge
reads the global flag from `~/.claude`. Terminal, VS Code, WSL, cloud
sessions and claude.ai/code show no badge from the mod.

## Layout

- `install.sh` / `uninstall.sh` — entry points
- `hooks/` — hook scripts injected into `settings.json`
- `lib/` — patch helpers shared by the hooks
- `plugins/caveman-badge/` — optional desktop badge mod (`.claude-plugin/marketplace.json` lists it)
