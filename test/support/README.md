# Shared test definitions

These files are included, in their original definition order, by `../runtests.jl`.
They define shared checks and do not execute research studies on inclusion.
`common.jl` supplies table, differentiation, fixture and path helpers;
`scalar_validation.jl` supplies fixed-value scalar checks. The remaining files
group GMFRM/MGMFRM saved-evidence checks by recovery, comparison, API, Q,
held-out prediction, reproduction and reporting purpose.

Keep optional research-fixture checks behind the existing
`BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS` gate. Missing optional evidence is not
an instruction to regenerate it. Paths refer to the parent `test/` directory.

Use the package test runner, rather than including these definition files on
their own; the runner owns imports, shared fixtures and shard selection.
