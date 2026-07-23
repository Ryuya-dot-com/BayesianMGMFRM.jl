# Fitting and Artifact API

## Stable fitting and shared artifacts

```@docs
MFRMPrior
MFRMLogDensity
MFRMFit
fit
fit_metadata
fit_artifact
fit_archive_manifest
artifact_content_hash
cached_fit
fit_cache_key
save_fit_cache
load_fit_cache
fit_report
fit_report_public
fit_report_markdown
fit_report_dossier
fit_report_dossier_markdown
fit_reproduction_manifest
fit_report_section
fit_report_sections
fit_report_rows
load_fit_report
load_fit_report_dossier
load_fit_report_bundle
load_fit_report_tables
save_fit_report
save_fit_report_dossier
save_fit_report_dossier_markdown
save_fit_report_bundle
save_fit_report_markdown
save_fit_report_tables
related_software_capability_matrix
```

## Experimental compatibility types

`GMFRMFit` and `MGMFRMFit` remain root-level compatibility bindings so that
existing serialized fit caches retain their Julia type identity. New
generalized workflows should access them through
`BayesianMGMFRM.Experimental`; see
[Experimental Generalized Models](experimental.md).

```@docs
GMFRMFit
MGMFRMFit
```
