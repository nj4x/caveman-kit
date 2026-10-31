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
