# caveman-kit

Installer kit that wires the `caveman` Claude Code skill into an existing
Claude Code configuration.

`install.sh` injects two hook entries (`SessionStart`, `UserPromptSubmit`)
into `settings.json` and a small badge block into `statusline.sh`. Everything
it touches is backed up under `~/.caveman-kit/backup/` so `uninstall.sh` can
restore the original configuration exactly.

## Requirements

- `node` on `PATH`
- The `caveman` skill already installed at
  `$CLAUDE_CONFIG_DIR/skills/caveman/SKILL.md` (this kit does not ship the
  skill itself — see https://github.com/JuliusBrussee/caveman)

## Usage

```bash
./install.sh
```

To revert:

```bash
./uninstall.sh
```

## Layout

- `install.sh` / `uninstall.sh` — entry points
- `hooks/` — hook scripts injected into `settings.json`
- `lib/` — patch helpers shared by the hooks
