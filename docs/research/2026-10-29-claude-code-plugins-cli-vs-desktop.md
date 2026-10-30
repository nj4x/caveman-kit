# Claude Code plugins: CLI vs desktop, status line, and relevance to caveman-kit

Date: 2026-10-29. Sources: official Claude Code docs at `code.claude.com/docs` (fetched as Markdown on this date) and the `anthropics/claude-code` CHANGELOG. Doc versions referenced in the pages: Claude Code v2.1.28x–v2.1.30x. Local files were used only to confirm what is installed, never as the authority.

## Short answers

- **Is the plugin system shared between the desktop app and the CLI?** Yes. Plugins install and load in the CLI, in the desktop app's Code tab (local and SSH sessions), and in the VS Code extension. All three read the same settings files on one machine, so a user-scope install in one shows up in the other two. Cloud sessions, the web, and WSL sessions in the desktop app do not load your locally installed plugins. ([install](https://code.claude.com/docs/en/plugins/install.md), [desktop](https://code.claude.com/docs/en/desktop.md#install-plugins))
- **Can a plugin ship a status line?** Not the `statusLine` setting. A plugin's `settings.json` honors only the `agent` and `subagentStatusLine` keys and drops every other key. ([manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference.md#settings), [components](https://code.claude.com/docs/en/plugins/components.md#default-settings))
- **What are "mods"?** Mods are plugins too, not a separate desktop-only system. A mod is a plugin whose `hooks/hooks.json` lists a JavaScript/TypeScript `modules` entry. Mods can draw UI (panes, a band above the prompt, toasts, a per-mod status line) and can redraw parts of Claude Code's own UI. Their drawing appears in the terminal, the desktop Code tab, and VS Code. The `plugin-authoring` skill seen in this session is the built-in `cc-plugin-plugin-authoring` plugin, which helps you write mods. ([mods overview](https://code.claude.com/docs/en/plugins/mods/overview.md))
- **How do you get a status indicator that shows on desktop?** Write a mod. Several mod render sites are documented as drawn on Desktop: `AbovePrompt`, `SessionMode`, `PromptHint`, `Spinner`, and `Pane`. Whether a custom `statusLine` script renders in the desktop Code tab is **unverified**, because no official page says either way. ([mods reference](https://code.claude.com/docs/en/plugins/mods/reference.md#render-sites))

## 1. What a Claude Code plugin is

### Components

A plugin can contain any of these:

- skills (`skills/<name>/SKILL.md`)
- commands (`commands/`, a legacy format; skills are preferred)
- agents (`agents/`)
- hooks (`hooks/hooks.json`)
- MCP servers (`.mcp.json`)
- LSP servers (`.lsp.json`)
- output styles (`output-styles/`)
- workflows (`workflows/`)
- themes (`themes/`, experimental)
- monitors (`monitors/monitors.json`, experimental)
- executables (`bin/`, placed on the Bash tool's PATH)
- channels
- `userConfig`
- a `settings.json` (only `agent` and `subagentStatusLine` take effect)

A `CLAUDE.md` at the plugin root is **not** loaded as context. Source: [manifest reference, Fields and Standard layout](https://code.claude.com/docs/en/plugins/manifest-reference.md#standard-layout).

### Manifest

`.claude-plugin/plugin.json` is optional. Without it, components load from the default layout. `name` is the only required field, and every component is namespaced under it (for example, `/deploy-tools:about`). Component paths must start with `./` and must stay inside the plugin root. `claude plugin validate` is the authoritative check. ([manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference.md))

### Variables

| Variable | What it points to | Notes |
| :- | :- | :- |
| `${CLAUDE_PLUGIN_ROOT}` | The installed version's directory | Changes on every update, so don't store state there |
| `${CLAUDE_PLUGIN_DATA}` | `~/.claude/plugins/data/<id>/` | Persists across updates; deleted on the last uninstall unless `--keep-data` is passed |
| `${CLAUDE_PROJECT_DIR}` | The project directory | — |

Hook processes receive all three variables, plus `CLAUDE_PLUGIN_OPTION_<KEY>` for each user-config value. ([manifest reference, Environment variables](https://code.claude.com/docs/en/plugins/manifest-reference.md#environment-variables))

### Hooks

`hooks/hooks.json` uses the same shape as `hooks` in `settings.json`, wrapped in a top-level `"hooks"` key, so existing settings hooks can be copied in unchanged. Plugin hooks register when the plugin loads and fire on their events from then on; they don't wait for a skill or command to be used. ([components, Hooks](https://code.claude.com/docs/en/plugins/components.md#hooks))

### Install and scopes

Plugins are installed with `/plugin install <name>@<marketplace>` in a session or `claude plugin install …` in the shell. Scopes:

- **user**: recorded in `enabledPlugins` in `~/.claude/settings.json`
- **project**: recorded in `.claude/settings.json` (committed). Each collaborator still has to install the plugin once.
- **local**: recorded in `.claude/settings.local.json`

Precedence is local > project > user. Anthropic's official marketplace (`claude-plugins-official`) is added automatically on the first interactive terminal session. ([install](https://code.claude.com/docs/en/plugins/install.md#choose-an-install-scope))

### Marketplaces

A marketplace is a directory or git repository with `.claude-plugin/marketplace.json` containing `name`, `owner`, and a `plugins` array. Each plugin entry has a `source`. ([create a marketplace](https://code.claude.com/docs/en/plugins/create-marketplace.md))

### Loading

Plugins from most marketplaces are copied to `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. Files outside the plugin directory aren't copied. A plugin from a marketplace added by local path loads in place. ([loading](https://code.claude.com/docs/en/plugins/loading.md))

## 2. Which surfaces load plugins

| Surface | Plugins load | Notes / source |
| :- | :- | :- |
| CLI (terminal, including JetBrains, which runs the CLI in the IDE terminal) | Yes | [install](https://code.claude.com/docs/en/plugins/install.md) |
| Desktop app, Code tab, local or SSH session | Yes, through the plugin manager UI (**+** > **Add plugins**) | Same engine as the CLI, same settings files ([desktop: Coming from the CLI](https://code.claude.com/docs/en/desktop.md#coming-from-the-cli)) |
| Desktop app, WSL session | No | "Plugins aren't available in WSL sessions" ([desktop](https://code.claude.com/docs/en/desktop.md#install-plugins)) |
| VS Code extension | Yes | Manages plugins by running the same commands as the CLI ([vs-code](https://code.claude.com/docs/en/vs-code.md)) |
| Cloud sessions and the web (claude.ai/code) | No for user- or repo-enabled plugins | No plugin browser. Plugins come only through org-managed settings ([install](https://code.claude.com/docs/en/plugins/install.md), [cloud environments](https://code.claude.com/docs/en/cloud-environments.md)) |
| claude.ai chat and Cowork | Same plugin format, different component set | [claude.com platform-support table](https://claude.com/docs/plugins/platform-support#compare-component-support-by-app). Not fetched here: **unverified** which components apply |

Other surface notes:

- **Settings hooks on desktop**: hooks and skills defined in settings apply to both the desktop app and the CLI. ([desktop: Shared configuration](https://code.claude.com/docs/en/desktop.md#shared-configuration))
- **Things missing from desktop**: `dontAsk` mode, agent teams, `--print`, and terminal-dialog commands such as `/permissions`. ([desktop: What's not available](https://code.claude.com/docs/en/desktop.md#whats-not-available-in-desktop))
- **Mod hooks** run wherever the plugin loads, including `-p`, the Agent SDK, and cloud sessions that receive the plugin. Mod drawing appears only in the terminal, the desktop app (not in WSL sessions), and the VS Code extension (v2.1.299+). Desktop mod support starts at bundled Claude Code v2.1.286; the terminal needs v2.1.287+. ([mods overview: Where mods run](https://code.claude.com/docs/en/plugins/mods/overview.md#where-mods-run))

## 3. Status line and UI customization from a plugin

### The `statusLine` setting

- **A plugin cannot set it.** Plugin settings honor only `agent` and `subagentStatusLine`. ([components: Default settings](https://code.claude.com/docs/en/plugins/components.md#default-settings))
- **Desktop rendering is undocumented.** The status line page describes "a customizable bar at the bottom of Claude Code" and talks only about terminals: `COLUMNS`/`LINES`, ANSI colors, and OSC 8 links. ([statusline](https://code.claude.com/docs/en/statusline.md)) The desktop page's shared-configuration list names CLAUDE.md, MCP, hooks, skills, and settings in general, but says nothing about the status line. **Unverified** whether the desktop Code tab renders a `statusLine` script. No official page says so, and the CHANGELOG has no entry about desktop status lines.
- **`disableAllHooks` turns it off.** When set outside managed settings, it also disables a custom status line. ([settings reference](https://code.claude.com/docs/en/settings-reference.md#statusline))

### Mods: the plugin way to customize the UI, including on desktop

- **Built-in UI calls:**
  - `$.ui.status(text)`: a persistent line under the prompt, prefixed with `⚠ <mod-name>:`
  - `$.ui.toast(text)`: a toast notification
  - `$.ui.log(text)`: a line in the transcript

  In VS Code, status lines and toasts show above the prompt box, cut at 200 characters or two rows. ([mods API: Show something without starting a turn](https://code.claude.com/docs/en/plugins/mods/api.md), [mods interface](https://code.claude.com/docs/en/plugins/mods/interface.md#draw-in-the-vs-code-extension)) The docs do not state where `$.ui.status` appears in the desktop app (**unverified**).
- **Render sites** (`ui.render` hooks):

  | Rendered on | Sites |
  | :- | :- |
  | Terminal, Desktop, VS Code | `Pane`, `Spinner`, `UserMessage`, `AssistantMessage`, `ToolUse`/`ToolResult`/`ToolGroup`, `AskUserQuestion` |
  | Terminal and Desktop only | `AbovePrompt` (the band), `SessionMode` (the mode labels in the footer), `PromptHint`, `CommandOutput` |
  | Terminal only | `ToolProgress`, `TurnDuration`, `InfoNotice` |

  `e.surface` reports `terminal`, `desktop`, or `vscode`. ([mods reference: Render sites](https://code.claude.com/docs/en/plugins/mods/reference.md#render-sites))
- **Elements by surface:**
  - `Svg`: Desktop and VS Code, not the terminal
  - `Raster`, `Image`: terminal only
  - `Client`: terminal and Desktop

  ([mods reference: Elements](https://code.claude.com/docs/en/plugins/mods/reference.md#elements))
- **Limits:** a mod cannot restyle the permission prompt. ([mods overview](https://code.claude.com/docs/en/plugins/mods/overview.md#what-a-mod-can-reach))
- **Answer to the desktop question:** the documented way to get a status-line-like indicator in the desktop Code tab is a mod drawing at `SessionMode`, `PromptHint`, or `AbovePrompt`. All three are marked as rendered on Desktop.
- **The `plugin-authoring` skill:** this is the built-in `cc-plugin-plugin-authoring` entry, which "gives Claude the `plugin-authoring` skill for writing mods. It holds a skill and no mod code." ([mods overview: Mods built into Claude Code](https://code.claude.com/docs/en/plugins/mods/overview.md#mods-built-into-claude-code)) Its SKILL.md was not found under `~/.claude/plugins` or `~/Library/Application Support/Claude`. It is not a separate desktop-only extension system.
- **Samples:** Anthropic publishes sample mods in [anthropics/claude-code-playground `claude-code/mods`](https://github.com/anthropics/claude-code-playground/tree/main/claude-code/mods) (`token-weather`, `blast-radius`, `replay-theater`) and the source of built-in mods in [anthropics/claude-code `mods/`](https://github.com/anthropics/claude-code/tree/main/mods). Neither repository was inspected for this note.

## 4. Relevance to caveman-kit

### What maps directly

- **Hooks:** the kit's SessionStart, UserPromptSubmit, and SubagentStart command hooks would move unchanged into `hooks/hooks.json`, as `"${CLAUDE_PLUGIN_ROOT}"/hooks/caveman-*.js`. Settings-hook shape is accepted as-is ([components](https://code.claude.com/docs/en/plugins/components.md#hooks)).
- **Uninstall:** `claude plugin uninstall` or disabling the plugin would replace the `settings.json` surgery and marker matching, which removes most of the ADR 0003 symmetry burden.
- **Reach:** one install covers the CLI, the desktop Code tab (local and SSH), and VS Code.

### What changes or is lost

- **Status line badge:** a plugin can't ship the `statusLine` badge. The kit would have to keep patching the user's `statusline.sh`, or move the badge into a mod (for example, a `SessionMode` or `PromptHint` render hook that reads the flag file through `$.fs.read`). A mod badge would also show in the desktop Code tab, which today's shell badge may not reach (unverified). The cost is a JS module, a minimum version of v2.1.286 (desktop) or v2.1.287 (terminal), and the mods trust model. The `$.ui.status` prefix `⚠ <name>:` is a poor fit for a mode badge.
- **`CLAUDE_PLUGIN_ROOT` changes meaning:** inside a plugin it points at the kit's own installed directory and changes on each update. Today the kit bakes that variable to point at the caveman skill's directory. Skill lookup would need another mechanism: bundle the skill in the plugin, or search `~/.claude/skills`. Mode state belongs outside the plugin root (the flag files already live in the repo or `~/.claude`, so this is fine).
- **The SKILL.md frontmatter patch:** a plugin can't patch a third-party skill it doesn't own. One option is to ship the skill inside the plugin. Whether the upstream license permits this, and whether JuliusBrussee/caveman already ships as a plugin, are both **unverified**.
- **Gaps that don't change:** cloud, web, and desktop WSL sessions get none of it, which is the same as today's settings hooks for user-level config ([cloud environments](https://code.claude.com/docs/en/cloud-environments.md)).
- **`disableAllHooks`:** it stops plugin hooks and mods as well as settings hooks and the status line, so a plugin buys no extra resilience there ([mods overview](https://code.claude.com/docs/en/plugins/mods/overview.md#turn-mods-on-or-off)).

## 5. Mod API facts for a badge mod

Sources: mods pages under `https://code.claude.com/docs/en/plugins/mods/` (fetched 2026-10-29), the sample `token-weather` mod in `anthropics/claude-code-playground`, and the built-in `agents-md` mod in `anthropics/claude-code`. Base URLs below abbreviate `https://code.claude.com/docs/en/plugins/mods/` as `mods/`.

1. **Imports and Node built-ins.**
   - Sibling files: yes, with limits. "Import only from files inside the plugin directory, by relative path. The one bare import allowed is `claude-code`." Use static `import` declarations at the top of the file; a dynamic `import()` fails, and `require` is not allowed because every file is an ES module. Passing `$` to a function you import from another of your files fails validation. A shared pure helper such as a mode whitelist is fine, but anything that touches `$` must be declared in the entry file or at the top level of the same file. ([mods/create.md](https://code.claude.com/docs/en/plugins/mods/create.md), "Check what Claude Code reads from your mod")
   - Node built-ins: no. "The hooks module itself has no Node.js APIs, no timer globals such as `setTimeout`, and no network or file access of its own." Standard web APIs (`URL`, `TextEncoder`, `AbortController`, `crypto.subtle`) are available. Files, processes and network go through `$.fs`, `$.process`, `$.http`. ([mods/api.md](https://code.claude.com/docs/en/plugins/mods/api.md), "Reach files, processes, and the network"). The existing `hooks/caveman-config.js` is CommonJS-style Node code and could not be imported as-is (unverified whether it uses `require`; this is the mods rule).
   - No build step: Claude Code loads `.js` and `.ts` directly. Entry file extensions accepted: `.js .mjs .cjs .jsx .ts .mts .cts .tsx`. ([mods/reference.md](https://code.claude.com/docs/en/plugins/mods/reference.md), Files)

2. **`$.fs`.**
   - Methods: `read(path)`, `write(path, text)`, `exists(path)`, `stat(path)`, `list(path)`. `list` returns `{ name, kind, size, isLink }` and is not recursive. Also `ancestors`, used by the built-in `agents-md` mod to walk up the tree looking for named files. ([mods/api.md](https://code.claude.com/docs/en/plugins/mods/api.md), [mods/reference.md](https://code.claude.com/docs/en/plugins/mods/reference.md) mods API methods)
   - Size cap: 4 MiB for one `read` or `write`. ([mods/reference.md#limits](https://code.claude.com/docs/en/plugins/mods/reference.md#limits)) The cap is documented only as a maximum; there is no way to ask for 16 bytes.
   - Outside the plugin root: yes. "A mod reaches the file system ... with the same permissions as the user running Claude Code." Relative paths resolve against the session cwd. So `~/.claude/.caveman-active` (via an absolute path built from `$.env.get('HOME')`) and `<repo>/.claude/.caveman-mode` are readable. ([mods/api.md](https://code.claude.com/docs/en/plugins/mods/api.md)) `agents-md/hooks/register.ts` builds the home directory exactly this way, from `$.env.get('HOME')`/`USERPROFILE`.
   - Symlinks: **unverified.** The docs only mention `isLink` in `list` output. They do not say whether `read` follows symlinks, and no `lstat` is listed. The kit's invariant that a flag file may not be a symlink could be checked with `list(dir)` on the parent and its `isLink` flag, but that is an inference, not a documented use.
   - Every `$.fs` call is itself a hookable event (`fs.read`), so another mod or an organization policy mod can observe, rewrite or refuse it. ([mods/api.md](https://code.claude.com/docs/en/plugins/mods/api.md))

3. **Session cwd and repo root.** `$.session` exposes `cwd`, `root`, `repo`, `id`, `surfaces`, `version`, among others. ([mods/reference.md](https://code.claude.com/docs/en/plugins/mods/reference.md) mods API methods) `agents-md/hooks/register.ts` calls `await $.session.root()` and `await $.session.cwd()` (both async). The docs list names only; what `root` means exactly (git root vs project root) and what `repo` returns are **unverified**. For the git root, `$.process.run(['git','rev-parse','--show-toplevel'])` is documented to work (no shell, 30 s default timeout). Relative paths for `$.fs` resolve against the cwd of the session, or of the subagent whose event is being handled. ([mods/api.md](https://code.claude.com/docs/en/plugins/mods/api.md))

4. **Re-render triggers.**
   - No file watching is documented. A `ui.render` hook reruns "when the site's props change or the terminal's width changes. It doesn't run the hook on a timer, and it can't tell when a variable in your module changes." ([mods/interface.md](https://code.claude.com/docs/en/plugins/mods/interface.md), "Redraw when something changes")
   - Documented ways to refresh:
     - Call `$.ui.invalidate('ui.render')` after your own data changes.
     - Start `$.clock.every(ms, fn)` in a `session.start` hook, with `fn` calling `$.ui.invalidate('ui.render')`. The interface page shows exactly this one-second pattern, "a value from outside the session". Timers stop when the module reloads.
     - Use `$.state` (reactive): a render hook that reads it is redrawn when it is written.
   - Hook events a mod can use: `session.start`, `prompt.submit`, `turn.complete`, and every settings-hook event as `classic.<Name>` (for example `classic.UserPromptSubmit`, `classic.SessionStart`; `e` is the settings-hook JSON). `classic.SessionStart` fires after `/clear`, `/resume`, `/branch`, with `e.source` set accordingly, and `session.start` does not fire again after those. ([mods/events.md](https://code.claude.com/docs/en/plugins/mods/events.md), [mods/interface.md](https://code.claude.com/docs/en/plugins/mods/interface.md))
   - For a flag written by a separate command hook, the practical documented route is: `$.clock.every` poll (read flag with `$.fs.read`, update `$.state` or call `invalidate`), plus an event-driven refresh on `prompt.submit` / `classic.UserPromptSubmit` (the tracker hook runs on the same event; ordering between a settings hook and a mod hook on the same event is **unverified**, so a timer is the safer choice). Redraw throttle: 10 per second, 30 per second in the terminal for the visible pane, the expanded band and the hint line. ([mods/reference.md#limits](https://code.claude.com/docs/en/plugins/mods/reference.md#limits))

5. **`SessionMode`, `PromptHint`, `AbovePrompt`.**
   - Replace or append: your choice. `next(e)` returns `{ type: 'engine', ref }`, a reference to Claude Code's own drawing. Options: pass a modified copy of `e` with changed `props` (change a detail), return your own tree without calling `next` (replace), return `next(e)` (leave alone), or place the reference inside a `Box` beside your own elements (append). ([mods/interface.md](https://code.claude.com/docs/en/plugins/mods/interface.md), "Change what Claude Code already draws")
   - What each site is: `SessionMode` is "the mode labels in the footer" (props `modes`, rendered on Terminal and Desktop). `PromptHint` is "the hint line under the prompt" (props `isDraft`, `isWorking`, `hint`; Terminal and Desktop). `AbovePrompt` is the band above the prompt (props `hasSurvey`, `isWorking`, `maxRows`, `bodyColumns`, `scroll`, `view`; Terminal and Desktop). The structure of `SessionMode`'s `modes` prop is **unverified**. ([mods/reference.md#render-sites](https://code.claude.com/docs/en/plugins/mods/reference.md#render-sites))
   - Size limits: no per-site character limit is documented for these three. General tree limits: 100,000 characters of text, 32 nesting levels, 20,000 elements. A tree that exceeds a limit is not drawn. The 200-character / two-row cut applies to status lines in the VS Code panel only. ([mods/reference.md#limits](https://code.claude.com/docs/en/plugins/mods/reference.md#limits), [mods/interface.md](https://code.claude.com/docs/en/plugins/mods/interface.md))
   - Best fit for `[CAVEMAN:ULTRA]`: `AbovePrompt` is the documented, sample-backed site (`token-weather` draws a one-line band there, and returns `next(e)` when it has nothing to show or when `e.hasSurvey` is set). `SessionMode` is the closest to the footer mode labels, but only its prop names are documented. `PromptHint` is probably unsuitable because it carries Claude Code's own hint text. This ranking is my reading of the docs, not a documented recommendation.
   - Terminal vs desktop: yes. `e.surface` is `terminal`, `desktop` or `vscode` in a `ui.render` hook, and the interface page shows `if (e.surface !== 'terminal')` branching. A hook that wants nothing on the terminal returns `next(e)` there, which leaves Claude Code's own drawing alone. Because `AbovePrompt`, `SessionMode` and `PromptHint` are not rendered in VS Code at all, a mod's hook does not fire there for those sites. ([mods/reference.md#render-sites](https://code.claude.com/docs/en/plugins/mods/reference.md#render-sites), [mods/interface.md](https://code.claude.com/docs/en/plugins/mods/interface.md))

6. **Trust and consent.**
   - There is no mod-specific approval dialog documented. A mod installs as a plugin (`/plugin install name@marketplace`), and the docs warn: "A mod is code that runs with your permissions ... Install mods only from authors and marketplaces you trust." Users can list its events and calls before install with `claude plugin validate <dir>` (the `hooks:` and `calls:` lines). ([mods/overview.md](https://code.claude.com/docs/en/plugins/mods/overview.md))
   - Enable flag: none. "Mods are on by default" from Claude Code v2.1.287 (terminal) and v2.1.286 (bundled in Desktop). They are off under `disableAllHooks: true`, `--safe-mode`, or organization policy (`allowManagedModsOnly`, `allowManagedHooksOnly`); in a directory the user hasn't trusted yet, no mod loads until the trust prompt is answered. Anthropic can also turn installed mods off remotely (the `cc-plugin-plugin-authoring` row says "Unless Anthropic has turned installed mods off remotely"). ([mods/overview.md](https://code.claude.com/docs/en/plugins/mods/overview.md), [mods/admin.md](https://code.claude.com/docs/en/plugins/mods/admin.md))
   - Side effect for the kit: `disableAllHooks: true` also turns off plugin hooks, so the kit's hooks and badge would go off together (the settings hooks do too).

7. **Mod-only plugin and marketplace layout.**
   - Mod-only: yes. A small mod "has three files": `.claude-plugin/plugin.json`, `hooks/hooks.json` with `"modules": ["./register.js"]`, and the module. Having `modules` in `hooks/hooks.json` is what makes a plugin a mod; `hooks/hooks.json` can also hold ordinary settings hooks under `hooks` alongside it. ([mods/overview.md](https://code.claude.com/docs/en/plugins/mods/overview.md), [mods/reference.md](https://code.claude.com/docs/en/plugins/mods/reference.md) Files) Settings-hook commands and a mod can therefore ship in one plugin, with no other components.
   - Marketplace at a repo root pointing to a subdirectory: yes. `.claude-plugin/marketplace.json` at the repo root; "every relative plugin source resolves from [the marketplace root]". An entry such as `{ "name": "...", "source": "./plugins/formatter" }` works; the path must start with `./` unless `metadata.pluginRoot` is used. Relative paths resolve only when the marketplace is added from a git repo or local path, not from a bare `url` source. ([marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference.md), "Relative path plugin source")
   - Read-only caveat for a repo-root layout: plugins from marketplaces are copied into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and files outside the plugin directory are not copied. Anything the plugin needs (hooks scripts, module) must live inside its subdirectory. ([loading](https://code.claude.com/docs/en/plugins/loading.md))
