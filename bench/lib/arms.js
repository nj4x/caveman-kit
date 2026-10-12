// caveman-kit bench — arm definitions (ADR 0008 decisions 2 and 3).
//
// Every arm registers the same three kit hooks. Bare and bare-control seed
// the flag to 'off' (buildArmConfig also sets CAVEMAN_DEFAULT_MODE=off), so
// the hooks run and inject nothing; bare-control is the noise baseline.
'use strict';

const SINGLE_TURN_ARMS = [
  { name: 'bare', mode: 'off' },
  { name: 'bare-control', mode: 'off' },
  { name: 'lite', mode: 'lite' },
  { name: 'full', mode: 'full' },
  { name: 'ultra', mode: 'ultra' },
];

module.exports = { SINGLE_TURN_ARMS };
