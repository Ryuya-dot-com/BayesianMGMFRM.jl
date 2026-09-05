# API

The reference is split by workflow area for easier navigation.

The package-root export surface is frozen for the `0.1.x` line. Every root
binding is classified as stable, compatibility-only, or research-only, and the
documentation build rejects a stable or compatibility binding that is absent
from this manual. Classification is about support policy: an exported research
helper is not promoted to the stable package workflow merely because old code
can still call it. Maintainer-only release controls stay outside the public
manual.

- [Data and Design API](api-data-design.md)
- [Fitting and Artifact API](api-fitting-artifacts.md)
- [Workflow and Diagnostics API](api-workflow-diagnostics.md)
- [Validation and Evidence API](api-validation-evidence.md)
