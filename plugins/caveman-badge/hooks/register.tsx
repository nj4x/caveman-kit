import type { EngineInterface, Register } from 'claude-code'

import { formatBadge, resolveMode } from './badge.mjs'

// ADR 0022: read-only caveman mode badge, desktop only, drawn at AbovePrompt
// (the prototype showed SessionMode is not drawn in the desktop Code tab).
// Polls the flag every 2 s; redraws only when the mode changed.

const POLL_MS = 2000

let mode: string | null | undefined
let isPolling = false

async function refresh($: EngineInterface): Promise<void> {
  let next: string | null = null
  try {
    next = await resolveMode({
      home: await $.env.get('HOME'),
      configDir: await $.env.get('CLAUDE_CONFIG_DIR'),
      cwd: await $.session.cwd(),
      fs: {
        stat: (path: string) => $.fs.stat(path).catch(() => null),
        read: (path: string) => $.fs.read(path),
      },
    })
  } catch {
    next = null
  }
  if (next !== mode) {
    const isFirst = mode === undefined
    mode = next
    if (!isFirst) $.ui.invalidate('ui.render')
  }
}

// Started by the desktop render hook only, so other surfaces never poll.
// Timers die when the module reloads (module variables reset with it); the
// next desktop render starts one again.
function startPolling($: EngineInterface): void {
  if (isPolling) return
  isPolling = true
  $.clock.every(POLL_MS, () => {
    refresh($).catch(() => {})
  })
}

export const register: Register = on => {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'desktop' || e.props.hasSurvey) {
      return next(e)
    }
    startPolling($)
    if (mode === undefined) await refresh($)
    const badge = formatBadge(mode)
    if (!badge) {
      return next(e)
    }
    const { Text } = $.ui.resolve(e)
    return <Text>{badge}</Text>
  })
}
