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

// Agentic arms (ADR 0008 decision 3, ADR 0009). Run against a kit checkout
// that contains Context Diet. The `full` arm opts out with
// CAVEMAN_CONTEXT_DIET=0; `full-diet` leaves the variable unset.
const AGENTIC_ARMS = [
  { name: 'bare', mode: 'off' },
  { name: 'full', mode: 'full', env: { CAVEMAN_CONTEXT_DIET: '0' } },
  { name: 'full-diet', mode: 'full' },
];

module.exports = { SINGLE_TURN_ARMS, AGENTIC_ARMS };
