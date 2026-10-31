// caveman-badge — pure chip drawing (ADR 0023). The level is the number of
// solid bones out of three: lite 1, full 2, ultra 3. The bones stack in one
// column and fill from the bottom up, like a level meter. Unused bones stay in
// place at 35% opacity so the chip keeps a fixed size. No `$`, no Node
// built-ins, no timers. The drawing functions return null for anything but
// lite/full/ultra (resolveMode already maps off, missing and invalid flags to
// null). ADR 0024 adds the fall animation: frames, palette and the step
// function that register.tsx wires to `$.clock`; randomness is injected.

const LEVELS = { lite: 1, full: 2, ultra: 3 };
const FILL = '#B07A4B';
const FADED_OPACITY = '0.35';

// ADR 0024: solid bones take a palette color when they land; faded slots
// never do. Color is decoration only, the level is still the solid count.
export const PALETTE = ['#B07A4B', '#C79A2E', '#6F9A6B', '#5F86B0', '#BF6F86'];
export const FRAME_MS = 125;
export const MAX_FRAMES = 16;
const FALL_DELAY_MIN_MS = 20000;
const FALL_DELAY_MAX_MS = 60000;

// Drawn size, passed as Svg props: an interactive Svg ignores the markup's own
// width/height (ADR 0023 prototype result).
export const CHIP_WIDTH = 14;
export const CHIP_HEIGHT = 28;

// One bone in a 14x8 cell at vertical offset y: a bar with two knobs at each end.
function bone(y, isSolid) {
  const opacity = isSolid ? '' : ` fill-opacity="${FADED_OPACITY}"`;
  return (
    `<g data-bone="${isSolid ? 'solid' : 'faded'}" fill="${FILL}"${opacity}>` +
    `<rect x="2" y="${y + 3}" width="10" height="2"/>` +
    `<circle cx="2" cy="${y + 2}" r="2"/><circle cx="2" cy="${y + 6}" r="2"/>` +
    `<circle cx="12" cy="${y + 2}" r="2"/><circle cx="12" cy="${y + 6}" r="2"/>` +
    `</g>`
  );
}

// A solid bone drawn from a frame entry (ADR 0024): moved, turned, recolored.
// Opacity 0 means the bone is away (fallen out, not yet back): nothing drawn.
function movedBone(y, entry) {
  if (entry.opacity <= 0) return '';
  const n = v => String(Math.round(v * 100) / 100);
  const isMoved = entry.dx || entry.dy || entry.rotate;
  const transform = isMoved
    ? ` transform="translate(${n(entry.dx)} ${n(entry.dy)}) rotate(${n(entry.rotate)} 7 ${y + 4})"`
    : '';
  const opacity = entry.opacity < 1 ? ` fill-opacity="${n(entry.opacity)}"` : '';
  return (
    `<g data-bone="solid"${transform} fill="${entry.color}"${opacity}>` +
    `<rect x="2" y="${y + 3}" width="10" height="2"/>` +
    `<circle cx="2" cy="${y + 2}" r="2"/><circle cx="2" cy="${y + 6}" r="2"/>` +
    `<circle cx="12" cy="${y + 2}" r="2"/><circle cx="12" cy="${y + 6}" r="2"/>` +
    `</g>`
  );
}

// chipSvg(mode) is the static 0.2.0 chip. With a frame (an array holding one
// entry per solid slot, bottom slot first) the solid bones are drawn from it.
export function chipSvg(mode, frame) {
  const level = Object.hasOwn(LEVELS, mode) ? LEVELS[mode] : 0;
  if (!level) return null;
  // Slots top to bottom at y 0, 10, 20; the bottom `level` slots are solid.
  const ys = [0, 10, 20];
  const bones = Array.isArray(frame)
    ? ys.map((y, i) => (i >= 3 - level ? movedBone(y, frame[2 - i]) : bone(y, false))).join('')
    : ys.map((y, i) => bone(y, i >= 3 - level)).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 28" width="${CHIP_WIDTH}" height="${CHIP_HEIGHT}">${bones}</svg>`;
}

export function nextFallDelayMs(rng) {
  return FALL_DELAY_MIN_MS + Math.floor(rng() * (FALL_DELAY_MAX_MS - FALL_DELAY_MIN_MS + 1));
}

// One fall (ADR 0024 decisions 2-4): the solid bones drop out through the
// bottom edge, bottom bone first, then rain back in from the top into their
// own slots, bottom slot first. Entry i is slot i counted from the bottom.
// A bone keeps its landed color until its landing frame, then takes a new
// palette color. The last frame is the resting stack.
export function planFall(mode, landed, rng) {
  const level = Object.hasOwn(LEVELS, mode) ? LEVELS[mode] : 0;
  if (!level) return null;
  const bones = Array.from({ length: level }, (_, i) => ({
    slotY: 20 - i * 10,
    fromColor: landed?.[i]?.color ?? FILL,
    toColor: PALETTE[Math.floor(rng() * PALETTE.length)],
    dx: (rng() * 2 - 1) * 4,
    rotate: (rng() * 2 - 1) * 40,
    outStart: i,
    inStart: 8 + i,
  }));
  const frames = [];
  for (let f = 0; f < MAX_FRAMES; f++) {
    frames.push(
      bones.map(b => {
        if (f < b.inStart) {
          const q = Math.min(1, Math.max(0, (f - b.outStart) / 6));
          if (q >= 1) return { dx: 0, dy: 0, rotate: 0, opacity: 0, color: b.fromColor };
          return { dx: b.dx * q, dy: (36 - b.slotY) * q * q, rotate: b.rotate * q, opacity: 1, color: b.fromColor };
        }
        const p = Math.min(1, (f - b.inStart) / 4);
        if (p >= 1) return { dx: 0, dy: 0, rotate: 0, opacity: 1, color: b.toColor };
        return {
          dx: b.dx * (1 - p),
          dy: -(b.slotY + 12) * (1 - p * p),
          rotate: b.rotate * (1 - p),
          opacity: 1,
          color: b.fromColor,
        };
      }),
    );
  }
  return frames;
}

export function initialAnimation() {
  return { off: false, isDisabled: false, nextFallAt: null, plan: null, frame: 0, landed: null };
}

// The animation state machine (ADR 0024 decisions 5, 6, 9, 10). Pure: the
// caller holds the state, arms one timer for `wakeInMs` (null: none) and
// redraws when `redraw` is true. Events:
//   { type: 'tick', now, mode, drawn }        timer fired, or a drawn render with nothing armed
//   { type: 'modeChanged', now, mode, drawn } the flag poll saw a new mode
//   { type: 'setEnabled', isEnabled, now, mode, drawn }  /caveman-badge animation on|off
//   { type: 'error' }                         the animation threw: off until reload
export function stepAnimation(state, event, rng) {
  if (state.off) return { state, redraw: false, wakeInMs: null };
  const level = Object.hasOwn(LEVELS, event.mode) ? LEVELS[event.mode] : 0;
  const schedule = s => ({ ...s, nextFallAt: event.now + nextFallDelayMs(rng) });

  if (event.type === 'error') {
    return { state: { ...state, off: true, plan: null, frame: 0, landed: null, nextFallAt: null }, redraw: true, wakeInMs: null };
  }
  if (event.type === 'modeChanged' || event.type === 'setEnabled') {
    const isDisabled = event.type === 'setEnabled' ? !event.isEnabled : state.isDisabled;
    let next = { ...state, isDisabled, plan: null, frame: 0, landed: null, nextFallAt: null };
    if (event.drawn && level && !isDisabled) next = schedule(next);
    return { state: next, redraw: true, wakeInMs: next.nextFallAt === null ? null : next.nextFallAt - event.now };
  }

  // tick
  if (state.isDisabled || !event.drawn || !level) {
    // Band hidden (or nothing to animate): cancel a fall, keep the landed
    // colors, schedule nothing. No redraw while the band is not drawn.
    return { state: { ...state, plan: null, frame: 0, nextFallAt: null }, redraw: false, wakeInMs: null };
  }
  if (state.plan) {
    if (state.frame + 1 < state.plan.length) {
      return { state: { ...state, frame: state.frame + 1 }, redraw: true, wakeInMs: FRAME_MS };
    }
    const next = schedule({ ...state, landed: state.plan[state.plan.length - 1], plan: null, frame: 0 });
    return { state: next, redraw: false, wakeInMs: next.nextFallAt - event.now };
  }
  if (state.nextFallAt === null) {
    const next = schedule(state);
    return { state: next, redraw: false, wakeInMs: next.nextFallAt - event.now };
  }
  if (event.now >= state.nextFallAt) {
    const plan = planFall(event.mode, state.landed, rng);
    return { state: { ...state, plan, frame: 0, nextFallAt: null }, redraw: true, wakeInMs: FRAME_MS };
  }
  return { state, redraw: false, wakeInMs: state.nextFallAt - event.now };
}

// The frame the render hook draws: the fall in progress, else the resting
// stack with its landed colors (null before the first fall: the 0.2.0 chip).
export function currentFrame(state) {
  return state.plan ? state.plan[state.frame] : state.landed;
}

export function chipLabel(mode) {
  if (!Object.hasOwn(LEVELS, mode)) return null;
  return { alt: `Caveman mode: ${mode}`, hover: `CAVEMAN · ${mode.toUpperCase()}` };
}

// Text fallback (ADR 0023 decision 7): solid bones only, no faded state.
// Not shipped while the Svg path works; kept so it has a producer and a test.
export function chipText(mode) {
  const level = Object.hasOwn(LEVELS, mode) ? LEVELS[mode] : 0;
  if (!level) return null;
  return '🦴'.repeat(level);
}
