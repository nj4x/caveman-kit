// caveman-badge — pure chip drawing (ADR 0023). The level is the number of
// solid bones out of three: lite 1, full 2, ultra 3. The bones stack in one
// column and fill from the bottom up, like a level meter. Unused bones stay in
// place at 35% opacity so the chip keeps a fixed size. No `$`, no Node
// built-ins. Every function returns null for anything but lite/full/ultra
// (resolveMode already maps off, missing and invalid flags to null).

const LEVELS = { lite: 1, full: 2, ultra: 3 };
const FILL = '#B07A4B';
const FADED_OPACITY = '0.35';

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

export function chipSvg(mode) {
  const level = Object.hasOwn(LEVELS, mode) ? LEVELS[mode] : 0;
  if (!level) return null;
  // Slots top to bottom at y 0, 10, 20; the bottom `level` slots are solid.
  const bones = [0, 10, 20].map((y, i) => bone(y, i >= 3 - level)).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 28" width="${CHIP_WIDTH}" height="${CHIP_HEIGHT}">${bones}</svg>`;
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
