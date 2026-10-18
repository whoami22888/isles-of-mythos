# Automated review/repair bootstrap — NOT ACTIVATED

This PR installs only `.github/workflows/automated-repair-dispatch.yml` on a
repository branch. Until this PR is merged, the manual `workflow_dispatch`
entrypoint is not registered on the default branch. Even after registration,
the job deliberately refuses credentialed repair before checkout or running an
agent. It uses read-only GitHub permissions and does not push or merge changes.

**Not yet present in this bootstrap:** an event classifier, persistent event
deduplication, bounded automated repair, an authenticated Codex execution
boundary, or automatic merging. Those controller components are proposed
separately in PR #187. The exact-SHA review/check and visual-acceptance
policies are activation requirements, not capabilities delivered by this
bootstrap alone.

## Requirements before activating a repair worker

- Prove a separately credentialed host broker and unprivileged, resource-limited
  container: no OpenAI key, Codex authentication file, GitHub write token, or
  host secrets can be read from a PR-controlled worktree.
- Validate the repository and PR identity, final head SHA, trusted actors and
  branch at dispatch and again immediately before any push.
- Lock the API proxy destination, cap time/requests/repair attempts, prevent
  bot-triggered recursion, and allow only reviewed changed paths.
- Keep git push credentials in a separate trusted process and test that a
  hostile PR cannot read the credentials or influence executable host hooks.
- Exercise an authenticated disposable same-repository PR end-to-end:
  diagnosis, smallest correction, targeted tests, validated commit and push.
  Verify fork, stale SHA, duplicate, missing broker and repeated-failure
  rejection. Preserve exact workflow IDs and outputs.
- Activate automated integration only when final-SHA CI, CodeQL, Codacy,
  static security, performance, applicable Godot/visual/provenance workflows
  and independent Codex review all pass. Visual changes also require explicit
  final-SHA owner acceptance.

## Present behavior

Manual dispatch accepts a PR number and expected SHA, checks that the PR head
is in the same repository, that its SHA matches and that the target branch is
not `main`. It then exits nonzero with an explicit disabled-repair message.

**Automatic review, repair, automatic merging and credentialed execution are
not supplied by this bootstrap PR.** Do not infer them from a green CI or a
Codex review receipt for this documentation-only change.
