# Core test bodies

`../runtests.jl` selects these bodies under the existing `@static` shard gates:

- `core.jl`: data, validation, specification/design and supporting contracts.
- `fitting_core.jl`: fitting/reporting checks and scalar density/gradient parity.

Tests that share local variables remain in the same testset and execution order.
The fitting suite retains its compilation-and-execution timing wrapper. Relative
includes and fixture paths resolve back to `test/`.

The six shard names and the `fitting` / `local_dependence` aggregate selectors
are unchanged. For example, in an environment containing the package and its
test dependencies, run from the repository root:

```sh
BAYESIANMGMFRM_TEST_GROUP=core julia --project=/path/to/test-environment test/runtests.jl
```

The other shard dispatches remain visible in `runtests.jl`. Selecting a different
shard does not execute either of these core bodies.
