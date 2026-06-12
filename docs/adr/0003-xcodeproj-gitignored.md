# ADR 0003: Kigo.xcodeproj is generated and gitignored

## Status

Accepted (walking skeleton, slice #2)

## Context

XcodeGen generates `Kigo.xcodeproj` from the committed `project.yml`. The CI
workflow (`.github/workflows/afk-ci.yml`) runs `xcodegen generate` before every
build and test run, so the generated artifact is always up-to-date in CI without
being committed to the repo.

Committing a generated `.xcodeproj` creates noise in diffs, merge conflicts in
`project.pbxproj`, and a false source of truth (the real source of truth is
`project.yml`). This is standard XcodeGen practice.

## Decision

Add `Kigo.xcodeproj/` to `.gitignore`. Source of truth for project structure is
`project.yml`. Every developer and CI run must execute `xcodegen generate` to
produce the project before building.

## Consequences

- Clean diffs — only `project.yml` and Swift source files appear in PRs.
- Every checkout requires `xcodegen generate` before opening in Xcode (documented
  implicitly by the CI workflow).
- No `.xcodeproj` merge conflicts.
