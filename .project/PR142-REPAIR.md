# PR142 repair — 2026-10-17 Australia/Sydney

Owner: Integration/Auto-Fix (current session). Branch: feature/iom02-asset-provenance-20261016. Source head e6b5f254eca2f8823bd8ddc7bb24fbbc9e0557a1; integrated main 43e61a8896213cda604c5568d06c51d41a8460ae.

Root causes: diverged Godot smoke workflow; historical importer fixtures outside approved root; importer omitted checking the asset root itself for symlinks; CLI naming and validator complexity findings. Keep main's mandatory island smoke and exact-head checkout, import main changes without reverting gameplay fixes, rename Python modules and workflow references, extract metadata/path validation, and reject symlinked importer roots.

Regression: symlinked-root test failed before the fix, passed after it. Local 9 importer + 11 validator tests PASS; empty-manifest validation PASS; Python compile PASS; Pylint 10/10, pycodestyle (100 columns) PASS; validator McCabe functions all below 10. These checks verify candidate source; exact-final-commit CI/security/performance/Godot and distinct AI review remain pending. No device/runtime or asset admission claim. No thresholds weakened.

Notion checkpoint pending; retained here. Next: verify final HEAD checks, address actionable failures, review before any merge.
