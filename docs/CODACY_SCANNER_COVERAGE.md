# Codacy scanner coverage for PR #213

The pinned Codacy CLI 7.10.0 attempted 26 distinct tools in failed run
40573465556. Twenty-three completed successfully and remain selected by name
in `.github/workflows/codacy.yml`: agentlinter, bandit, biome, checkov,
csslint, eslint-9, hadolint, jacksonlinter, jshint, lizard, markdownlint,
opengrep, oxlint, pmd, pmd-7, prospector, pylint, pylintpython3, remark-lint,
ruff, spectral, stylelint, and tslint. Every selected invocation retains
`fail-if-incomplete: true` and uploads its complete SARIF with a distinct
category. The required aggregate check fails if any selected scanner fails.

The three failed CLI tools are replaced as follows:

| Failed tool | Failure in run 40573465556 | Maintained coverage |
| --- | --- | --- |
| eslint | Legacy analyzer output could not be parsed | Codacy eslint-9 and repository ESLint CI for JavaScript/TypeScript |
| eslint-8 | Legacy analyzer output could not be parsed | Codacy eslint-9 and repository ESLint CI for JavaScript/TypeScript |
| trivy | Codacy wrapper had no configured patterns | Pinned native Trivy 0.74.0 filesystem scan for vulnerabilities, secrets, and misconfigurations, with SARIF upload |

PMD and PMD-7 stay in the explicit matrix. Both returned zero results in the
failed run; the repository currently has no Java, Apex, Visualforce, or XML
source for those analyzers. Their continued execution detects future changes
to source applicability. The `metric` path exclusions in `.codacy.yml` apply
only to Godot formats unsupported by the analyzer; Lizard still runs for
supported source. No result threshold or incomplete-scan failure is relaxed.

This inventory is a coverage contract, not a passing result. Verify the
final commit's matrix, Trivy scan, SARIF uploads, and aggregate check before
merging.
