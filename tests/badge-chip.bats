#!/usr/bin/env bats
# The desktop badge chip (ADR 0023): three bones, solid count = level, plus
# the alt/hover labels and the Text fallback. Runs plugins/caveman-badge/
# hooks/chip.mjs directly through node.

setup() {
  export CHIP="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/plugins/caveman-badge/hooks/chip.mjs"
}

# chip <expr>: evaluate <expr> with chip.mjs imported as `c`, print the result.
chip() {
  node --input-type=module -e "
    const c = await import(process.argv[1]);
    const v = ($1);
    process.stdout.write(v === null ? 'null' : String(v));
  " "$CHIP"
}

count() { chip "(c.chipSvg('$1') ?? '').split('data-bone=\"$2\"').length - 1"; }

@test "solid bones count the level, three bones in all" {
  [ "$(count lite solid)" = 1 ];  [ "$(count lite faded)" = 2 ]
  [ "$(count full solid)" = 2 ];  [ "$(count full faded)" = 1 ]
  [ "$(count ultra solid)" = 3 ]; [ "$(count ultra faded)" = 0 ]
}

@test "bones fill from the bottom up" {
  [ "$(chip "[...c.chipSvg('lite').matchAll(/data-bone=\"(\\w+)\"/g)].map(m => m[1]).join(',')")" = "faded,faded,solid" ]
  [ "$(chip "[...c.chipSvg('full').matchAll(/data-bone=\"(\\w+)\"/g)].map(m => m[1]).join(',')")" = "faded,solid,solid" ]
  [ "$(chip "[...c.chipSvg('ultra').matchAll(/data-bone=\"(\\w+)\"/g)].map(m => m[1]).join(',')")" = "solid,solid,solid" ]
}

@test "unused bones are drawn at 35% opacity, solid ones are not" {
  [ "$(chip "c.chipSvg('lite').split('fill-opacity=\"0.35\"').length - 1")" = 2 ]
  [ "$(chip "c.chipSvg('ultra').split('fill-opacity').length - 1")" = 0 ]
}

@test "svg size matches the exported chip size" {
  [ "$(chip "c.chipSvg('full').includes('width=\"' + c.CHIP_WIDTH + '\" height=\"' + c.CHIP_HEIGHT + '\"')")" = true ]
}

@test "one distinct svg per mode" {
  [ "$(chip "new Set(['lite','full','ultra'].map(c.chipSvg)).size")" = 3 ]
  [[ "$(chip "c.chipSvg('ultra')")" == '<svg '* ]]
}

@test "alt and hover labels, every mode" {
  for m in lite full ultra; do
    M="$(printf '%s' "$m" | tr a-z A-Z)"
    [ "$(chip "c.chipLabel('$m').alt")" = "Caveman mode: $m" ]
    [ "$(chip "c.chipLabel('$m').hover")" = "CAVEMAN · $M" ]
  done
}

@test "text fallback repeats the bone per level" {
  [ "$(chip "c.chipText('lite')")" = "🦴" ]
  [ "$(chip "c.chipText('full')")" = "🦴🦴" ]
  [ "$(chip "c.chipText('ultra')")" = "🦴🦴🦴" ]
}

@test "off and unknown input draw nothing" {
  for m in off bogus constructor __proto__ ''; do
    [ "$(chip "c.chipSvg('$m')")" = null ]
    [ "$(chip "c.chipLabel('$m')")" = null ]
    [ "$(chip "c.chipText('$m')")" = null ]
  done
  [ "$(chip "c.chipSvg(null)")" = null ]
}

# ADR 0024: the fall animation. anim <expr>: evaluate <expr> with chip.mjs as
# `c` and a seeded random source factory as `seeded`, print the result.
anim() {
  node --input-type=module -e "
    const c = await import(process.argv[1]);
    const { seeded } = await import(process.argv[2]);
    const v = await (async () => { $1 })();
    process.stdout.write(v === null ? 'null' : String(v));
  " "$CHIP" "$(dirname "$CHIP")/../../../tests/helpers/seeded-rng.mjs"
}

@test "static chip is unchanged from 0.2.0, with or without an empty frame" {
  for m in lite full ultra; do
    [ "$(anim "return c.chipSvg('$m') === c.chipSvg('$m', null) && c.chipSvg('$m') === c.chipSvg('$m', undefined)")" = true ]
  done
  [ "$(anim "const h = (await import('node:crypto')).createHash('sha256'); return h.update(c.chipSvg('ultra')).digest('hex')")" = f2f5b8a5778d20c2fc5f6d139c647a2754bc653fe6c1d48d50e787e0aab8d06e ]
  [ "$(anim "const h = (await import('node:crypto')).createHash('sha256'); return h.update(c.chipSvg('lite')).digest('hex')")" = f750ab1271389f5f01786b4a152c812f1847e4c50517e2ebc16e04a7e3ef363e ]
}

@test "a fall has at most 16 frames, one entry per solid bone" {
  for m in lite full ultra; do
    [ "$(anim "
      const lvl = { lite: 1, full: 2, ultra: 3 }['$m'];
      const plan = c.planFall('$m', null, seeded(7));
      return plan.length <= c.MAX_FRAMES && plan.every(f => f.length === lvl);
    ")" = true ]
  done
}

@test "every color is a palette color or the landed color" {
  [ "$(anim "
    const landed = [{ color: '#123456' }, { color: '#654321' }, { color: '#abcdef' }];
    const plan = c.planFall('ultra', landed, seeded(3));
    return plan.every(f => f.every((e, i) => c.PALETTE.includes(e.color) || e.color === landed[i].color));
  ")" = true ]
}

@test "a bone keeps its landed color until it lands, then takes a palette color" {
  [ "$(anim "
    const landed = [{ color: '#111111' }, { color: '#222222' }, { color: '#333333' }];
    const plan = c.planFall('ultra', landed, seeded(11));
    return [0, 1, 2].every(i => {
      const first = plan.findIndex(f => c.PALETTE.includes(f[i].color));
      return first > 0 && plan.slice(0, first).every(f => f[i].color === landed[i].color)
        && plan.slice(first).every(f => c.PALETTE.includes(f[i].color));
    });
  ")" = true ]
  [ "$(anim "return c.planFall('full', null, seeded(1))[0].every(e => e.color === '#B07A4B')")" = true ]
}

@test "the last frame is the resting stack" {
  [ "$(anim "
    const last = c.planFall('ultra', null, seeded(5)).at(-1);
    return last.every(e => e.dx === 0 && e.dy === 0 && e.rotate === 0 && e.opacity === 1);
  ")" = true ]
}

@test "a bone that is away draws nothing" {
  [ "$(anim "
    const plan = c.planFall('ultra', null, seeded(9));
    const f = plan.find(fr => fr.some(e => e.opacity === 0));
    const away = f.filter(e => e.opacity === 0).length;
    return c.chipSvg('ultra', f).split('data-bone=\"solid\"').length - 1 === 3 - away;
  ")" = true ]
}

@test "same seed, same plan; planFall is null for off and unknown input" {
  [ "$(anim "return JSON.stringify(c.planFall('full', null, seeded(42))) === JSON.stringify(c.planFall('full', null, seeded(42)))")" = true ]
  for m in off bogus __proto__ ''; do
    [ "$(anim "return c.planFall('$m', null, seeded(1))")" = null ]
  done
}

@test "fall delay stays within 20 to 60 seconds" {
  [ "$(anim "
    const r = seeded(123);
    const ds = Array.from({ length: 5000 }, () => c.nextFallDelayMs(r));
    return ds.every(d => d >= 20000 && d <= 60000);
  ")" = true ]
}

@test "stepAnimation: first drawn tick schedules a fall and starts none" {
  [ "$(anim "
    const r = c.stepAnimation(c.initialAnimation(), { type: 'tick', now: 1000, mode: 'full', drawn: true }, seeded(1));
    return [r.state.plan === null, r.redraw, r.wakeInMs >= 20000 && r.wakeInMs <= 60000, r.state.nextFallAt === 1000 + r.wakeInMs].join(',');
  ")" = "true,false,true,true" ]
}

@test "stepAnimation: a tick before the fall time waits, at the fall time starts a plan" {
  [ "$(anim "
    const s = { ...c.initialAnimation(), nextFallAt: 5000 };
    const early = c.stepAnimation(s, { type: 'tick', now: 4000, mode: 'ultra', drawn: true }, seeded(1));
    const due = c.stepAnimation(s, { type: 'tick', now: 5000, mode: 'ultra', drawn: true }, seeded(1));
    return [early.redraw, early.wakeInMs, due.state.plan !== null, due.redraw, due.wakeInMs].join(',');
  ")" = "false,1000,true,true,125" ]
}

@test "stepAnimation: the last frame lands the colors and schedules the next fall" {
  [ "$(anim "
    const rng = seeded(2);
    let s = { ...c.initialAnimation(), nextFallAt: 0 };
    let r = c.stepAnimation(s, { type: 'tick', now: 0, mode: 'ultra', drawn: true }, rng);
    const plan = r.state.plan;
    let now = 0;
    while (r.state.plan) { now += 125; r = c.stepAnimation(r.state, { type: 'tick', now, mode: 'ultra', drawn: true }, rng); }
    return [r.state.landed === plan.at(-1), r.state.nextFallAt > now, r.wakeInMs === r.state.nextFallAt - now].join(',');
  ")" = "true,true,true" ]
}

@test "stepAnimation: a mode change clears the landed colors and reschedules" {
  [ "$(anim "
    const s = { ...c.initialAnimation(), plan: [ [] ], frame: 3, landed: [ { color: '#C79A2E' } ], nextFallAt: null };
    const r = c.stepAnimation(s, { type: 'modeChanged', now: 100, mode: 'lite', drawn: true }, seeded(1));
    return [r.state.plan, r.state.landed, r.redraw, r.state.nextFallAt > 100].join(',');
  ")" = ",,true,true" ]
}

@test "stepAnimation: a hidden band cancels the fall and keeps the landed colors" {
  [ "$(anim "
    const landed = [{ color: '#6F9A6B' }];
    const s = { ...c.initialAnimation(), plan: [[], []], frame: 0, landed, nextFallAt: null };
    const hid = c.stepAnimation(s, { type: 'tick', now: 100, mode: 'lite', drawn: false }, seeded(1));
    const back = c.stepAnimation(hid.state, { type: 'tick', now: 200, mode: 'lite', drawn: true }, seeded(1));
    return [hid.state.plan, hid.state.landed === landed, hid.redraw, hid.wakeInMs, hid.state.nextFallAt, back.state.plan, back.state.nextFallAt > 200].join(',');
  ")" = ",true,false,,,,true" ]
}

@test "stepAnimation: animation off stops and clears, on reschedules" {
  [ "$(anim "
    const s = { ...c.initialAnimation(), plan: [ [] ], landed: [ { color: '#5F86B0' } ] };
    const off = c.stepAnimation(s, { type: 'setEnabled', isEnabled: false, now: 0, mode: 'lite', drawn: true }, seeded(1));
    const tick = c.stepAnimation(off.state, { type: 'tick', now: 999999, mode: 'lite', drawn: true }, seeded(1));
    const on = c.stepAnimation(off.state, { type: 'setEnabled', isEnabled: true, now: 0, mode: 'lite', drawn: true }, seeded(1));
    return [off.state.plan, off.state.landed, off.wakeInMs, tick.state.plan, on.state.nextFallAt > 0].join(',');
  ")" = ",,,,true" ]
}

@test "stepAnimation: an error turns the animation off for good" {
  [ "$(anim "
    const start = Object.assign(c.initialAnimation(), { plan: [[]] });
    const r = c.stepAnimation(start, { type: 'error' }, seeded(1));
    const later = c.stepAnimation(r.state, { type: 'tick', now: 0, mode: 'ultra', drawn: true }, seeded(1));
    return [r.state.off, r.state.plan, r.redraw, later.state === r.state, later.wakeInMs].join(',');
  ")" = "true,,true,true," ]
}
