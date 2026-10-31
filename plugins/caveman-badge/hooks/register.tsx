import type { EngineInterface, Register } from 'claude-code'

import { resolveMode } from './badge.mjs'
import {
  CHIP_HEIGHT,
  CHIP_WIDTH,
  chipLabel,
  chipSvg,
  currentFrame,
  initialAnimation,
  stepAnimation,
} from './chip.mjs'

// ADR 0022: read-only caveman mode badge, desktop only, drawn at AbovePrompt
// (the prototype showed SessionMode is not drawn in the desktop Code tab).
// Polls the flag every 2 s; redraws only when the mode changed. ADR 0023: the
// badge is a chip of three bones (solid count = level) with a hover label.
// ADR 0024: the solid bones fall and re-stack every 20-60 s, driven by the
// pure stepAnimation and one on-demand $.clock.after timer; switched off with
// `/caveman-badge animation off`, kept in $.store for every session.

const POLL_MS = 2000
const COMMAND = 'caveman-badge'
const ANIMATION_KEY = 'animation'

let mode: string | null | undefined
let isPolling = false
let isAnimationEnabled = true
let anim = initialAnimation()
let isDrawn = false
let timer: { cancel: () => void } | null = null

// Every animation transition goes through here (ADR 0024 decision 10): any
// error turns the animation off until the module reloads, and the static
// chip stays. The flag poll is not touched.
function send($: EngineInterface, event: Record<string, unknown>): void {
  let result
  try {
    result = stepAnimation(anim, event, Math.random)
  } catch {
    result = stepAnimation(anim, { type: 'error' }, Math.random)
  }
  anim = result.state
  timer?.cancel()
  timer = null
  if (result.wakeInMs !== null) {
    timer = $.clock.after(Math.max(0, result.wakeInMs), () => {
      tick($).catch(() => send($, { type: 'error' }))
    })
  }
  if (result.redraw) $.ui.invalidate('ui.render')
}

async function tick($: EngineInterface): Promise<void> {
  send($, { type: 'tick', now: await $.clock.now(), mode, drawn: isDrawn })
}

async function readAnimationEnabled($: EngineInterface): Promise<boolean> {
  try {
    return (await $.store.get(ANIMATION_KEY)) !== false
  } catch {
    return true
  }
}

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
  // Another session may have run /caveman-badge animation on|off.
  const isEnabled = await readAnimationEnabled($)
  if (isEnabled !== isAnimationEnabled) {
    isAnimationEnabled = isEnabled
    send($, { type: 'setEnabled', isEnabled, now: await $.clock.now(), mode: next, drawn: isDrawn })
  }
  if (next !== mode) {
    const isFirst = mode === undefined
    mode = next
    if (!isFirst) {
      send($, { type: 'modeChanged', now: await $.clock.now(), mode, drawn: isDrawn })
      $.ui.invalidate('ui.render')
    }
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

function drawSvg($: EngineInterface, current: string): string | null {
  try {
    return chipSvg(current, currentFrame(anim))
  } catch {
    send($, { type: 'error' })
    return chipSvg(current)
  }
}

async function runCommand($: EngineInterface, args: string): Promise<string> {
  const [what, value] = args.trim().toLowerCase().split(/\s+/)
  if (what === 'animation' && (value === 'on' || value === 'off')) {
    const isEnabled = value === 'on'
    try {
      await $.store.set(ANIMATION_KEY, isEnabled)
    } catch {
      return 'Could not save the setting.'
    }
    isAnimationEnabled = isEnabled
    send($, { type: 'setEnabled', isEnabled, now: await $.clock.now(), mode, drawn: isDrawn })
    return `Caveman badge animation ${value} (all sessions).`
  }
  if (!what || what === 'status') {
    const isEnabled = await readAnimationEnabled($)
    return `Caveman badge animation: ${isEnabled ? 'on' : 'off'}.`
  }
  return 'Usage: /caveman-badge animation on|off, or /caveman-badge status'
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: 'Caveman desktop badge: turn the bone animation on or off',
      argumentHint: 'animation on|off | status',
    })
    return next(e)
  })

  on('command.run', { command: COMMAND }, async ($, e) => ({ text: await runCommand($, e.args) }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'desktop' || e.props.hasSurvey) {
      isDrawn = false
      return next(e)
    }
    startPolling($)
    if (mode === undefined) {
      isAnimationEnabled = await readAnimationEnabled($)
      anim = { ...anim, isDisabled: !isAnimationEnabled }
      await refresh($)
    }
    const label = chipLabel(mode)
    const svg = label ? drawSvg($, mode as string) : null
    const { Box, Svg, Text } = $.ui.resolve(e)
    // Svg is missing on a build that cannot draw it: yield to the engine.
    if (!svg || !label || !Svg) {
      isDrawn = false
      return next(e)
    }
    isDrawn = true
    // A drawn chip with nothing armed starts the countdown: the first render,
    // or the first one after the band was hidden (ADR 0024 decision 5).
    if (!timer && !anim.plan && anim.nextFallAt === null && !anim.isDisabled && !anim.off) {
      tick($).catch(() => {})
    }
    // hover can only reveal a hidden Box, so the label is a sibling drawn
    // display: none inside the keyed chip Box.
    return (
      <Box key="caveman-chip" flexDirection="row" alignItems="center">
        <Box flexShrink={0}>
          <Svg source={svg} alt={label.alt} width={CHIP_WIDTH} height={CHIP_HEIGHT} />
        </Box>
        <Box display="none" hover={{ display: 'flex' }} marginLeft={1}>
          <Text>{label.hover}</Text>
        </Box>
      </Box>
    )
  })
}
