# Development Roadmap

The aim is a useful, reproducible Julia workflow for rating analysis: check a
rating design, specify a model and prior, estimate it, interpret uncertainty and
fit, compare eligible analyses, plan data collection and reopen saved results.
Ordinary one-dimensional 1PL/MFRM and generalized scalar models remain primary
routes. Additional dimensions or rater mechanisms need a substantive question.

## Next outcomes and dependencies

The next outcome is a bounded foundation ready for independent review: the
existing scalar and selected fixed-Q workflows tied to one source, matching
instructions and explicit environment and saved-result requirements. Reuse
completed analysis checks and identify only missing or affected operations.
This preparation does not itself establish acceptance or change support status.

1. **Complete the selected foundation's acceptance.** Resolve the remaining
   operation and compatibility gaps for the declared model/prior/backend roster.
   Independent scientific review and an unfamiliar user's reproduction then
   inform the final API, scope and instructions; blocking findings need resolution.
2. **Deliver that accepted source and manual together.** Verify the advertised
   installation, analysis and save/reopen paths, version and migration information,
   and the actual distributed artifacts. Broader model extensions are not
   prerequisites for this bounded delivery.
3. **Complete the planned capability branches.** Design planning, a declared
   composition of five or more fitted facets, a bounded 3D correlation workflow,
   and the selected applications retain their own completion conditions.
   Criterion-collapse and temporal-severity models have separate statistical
   and user-operation requirements. These branches depend on the model needed
   for their question, not on every other branch being finished.

Capability branches can advance alongside foundation preparation when their
own prerequisites are met; they do not have to wait for foundation delivery.
A demonstrated mathematical, data-preservation or required-operation defect
takes priority in the affected route. Performance work supports a selected
operation at useful precision. Existing software comparisons are evidence for
their stated targets; completing a comparison does not select another experiment.

See the [manual roadmap](docs/src/roadmap.md) for available scope, remaining
outcomes and comparison limits. [Scope and Releases](docs/src/scope.md) defines
supported combinations; [the model guide](docs/src/rating-model-theory.md)
explains their meaning. These outcomes do not promise release dates or a
completion percentage. A completed implementation check is not general
calibration, mechanism identification or proof of a unique capability.

## Documentation and contributions

- [Learning and help](docs/src/learning-guide.md)
- [Mathematical model definitions](docs/src/model-equations.md)
- [Evidence for model extensions](docs/src/mgmfrm-research-roadmap.md)
- [Contributing and reproduction](docs/src/contributing.md)
- [Versioning and saved-result migration](docs/src/registration.md)

## Multi-criterion, additive-facet, and three-trait experimental workflows

The unified `Experimental.joint_rating_spec(...; association = :none | :uniform | :star)`
and `Experimental.fit` entry points connect three multi-criterion rating workflows:
shared-response joint ratings ([guide](docs/src/joint-ratings.md)), paired ordinal
association (`JointRatings.OrdinalAssociation`, [guide](docs/src/ordinal-association.md)),
and general `D >= 2` mixed-support star-factorized association
(`Experimental.StarAssociation`, [guide](docs/src/star-association.md)).
For additional main-effect facets, see [User-Named Additive Facets](docs/src/additive-facets.md);
for two-study two-ordinal + one-binary (9/9/2) rating workflows, see [Concurrent Three-Outcome Study](docs/src/concurrent-three-outcome.md).
For three pure-Q traits, `Experimental.Correlated3D`
([guide](docs/src/correlated-3d.md)) connects generation, retained-chain Julia
NUTS, named marginal/partial correlations, conditional row probabilities, and
source-bound native save/reopen. Implementation and saved-result checks do not
close application-specific misfit, prior sensitivity, calibration, or
independent scientific acceptance.
