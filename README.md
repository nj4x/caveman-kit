# caveman-kit

Installer kit that wires the `caveman` Claude Code skill into an existing
Claude Code configuration.

`install.sh` injects two hook entries (`SessionStart`, `UserPromptSubmit`)
into `settings.json` and a small badge block into `statusline.sh`. Everything
it touches is backed up under `~/.caveman-kit/backup/` so `uninstall.sh` can
restore the original configuration exactly.

## Prerequisites

The `caveman` skill must be present at
`$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md`. If it is missing, `install.sh`
offers to install it automatically (pinned to `JuliusBrussee/caveman@v2.2.0`,
skill only — no CLI, proxy, or binaries):

- interactively: answer `y` at the prompt
- non-interactively (CI/scripts): pass `--install-skill` or set
  `CAVEMAN_KIT_INSTALL_SKILL=1`

To install the skill manually instead:

```bash
npx skills add JuliusBrussee/caveman@v2.2.0 --skill caveman -g --copy
```

See [caveman](https://github.com/JuliusBrussee/caveman) for details.

The installer also patches the skill's frontmatter with
`disable-model-invocation: true` (original backed up and restored byte-exact
on uninstall). If the kit auto-installed the skill, `uninstall.sh` removes it
again; a pre-existing skill is only ever restored, never removed.

## Requirements

- `node` on `PATH`

## Usage

### Quick install (clone-free)

```bash
curl -fsSL https://raw.githubusercontent.com/nj4x/caveman-kit/main/bootstrap.sh | bash
```

### Manual install from checkout

```bash
./install.sh                # prompts to install the skill if missing
./install.sh --install-skill  # non-interactive skill install consent
```

To revert:

```bash
./uninstall.sh
```

### Damaged install recovery

If the install state is corrupted, remove both directories manually:

```bash
rm -rf ~/.local/share/caveman-kit ~/.caveman-kit
```

Then manually remove hook entries from `~/.claude/settings.json` that reference `caveman-activate.js` or `caveman-mode-tracker.js`.

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
