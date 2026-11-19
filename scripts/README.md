# Script roles

Application code should use the package's [common workflow](../docs/src/first-analysis.md)
and [API reference](../docs/src/api.md). Scripts are developer tools and study
entry points; their names are not additional public model APIs.

- `local_json.jl` supplies the canonical writer used by existing evidence hashes.
  `review_json.jl` shares JSON3-backed field readers for research review scripts.
  These files are helpers, not commands.
- `platform_smoke.jl` and `distribution_archive_smoke.jl` execute small fits;
  the distribution check also installs dependencies and builds documentation.
  `check_release.jl` runs the full local release checks, including temporary
  dependency installation, examples, tests and documentation. Its `--help`
  describes which work each skip flag omits; skipping tests still runs examples.
- `print_registration_handoff.jl` prints a draft of manual instructions using
  installed dependencies. It checks version/citation metadata and the existing
  manual-only release boundary; it activates no project, installs no dependencies and performs no
  publication. A nested snapshot never reports its ancestor's Git commit.
  `--strict` requires this source tree's own clean `main` checkout.
- `generate_` and `review` names do not imply read-only work. Recovery generators
  run samplers, and guarded-fit scope/exposure reviews exercise successful fits.
  Use the original protocol, source, environment and execution controls when
  reproducing a historical study.

| Current command | Compatibility entry point |
| --- | --- |
| `check_release.jl` | `pre_registration_gate.jl` |
| `print_registration_handoff.jl` | `registration_handoff.jl` |

Current and compatibility entries support `--help` and reject unknown or
invalid version arguments before project activation or dependency loading.
Old entry points delegate to the same implementation. Historical regeneration
commands keep their original source/environment binding.

The platform/distribution smoke scripts, source/runtime language gates and
`release_metadata.jl` also support lightweight `--help` and reject unknown
arguments before their checks. Runtime language checks include short fits;
source-language and metadata checks do not. `--rendered` additionally scans
built HTML in the source-language gate.

The retired `prediction_observation_adapter.jl` prototype is preserved in its
original snapshots. Current code uses:

```julia
using BayesianMGMFRM.PredictionObservationAdapter
```

Current prediction records use `.v1` schemas. Re-extract `.prototype.v1` records
from their original fits; changing a schema string does not establish
compatibility. See [prediction comparison](../docs/src/common_prediction_comparison.md).

Focused deterministic checks are `test/review_json.jl` and
`test/prediction_criteria_adapter.jl`. They are assigned to the ordinary `core`
and `fitting_reports` shards respectively. The latter preserves independent
unit-logit checks and synthetic save/reopen tests without fitting.
