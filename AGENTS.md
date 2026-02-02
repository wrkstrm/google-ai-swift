# AGENTS.md

## Scope

This file defines local guidance for the `google-ai-swift` submodule. It is
additive to any parent repo policies.

## Start here

1. Read this file first.
2. If this repo is nested inside a parent workspace, also read the parent
   `AGENTS.md` and `.clia/AGENTS.md`.
3. Review the local CLIA triads under `.clia/agents/**` before making changes.

## CLIA and triads

- Canonical source is JSON triads (`*.agent.triad.json`, `*.agenda.triad.json`,
  `*.agency.triad.json`).
- Markdown mirrors in `.generated/` are non-canonical.
- Keep triads formatted with the repo’s canonical JSON formatter when editing.

## Build and test

- SwiftPM only. Prefer release builds when validating packaging.
- Tests use Swift Testing (`import Testing`), not XCTest.

## Guardrails

- Subprocesses must use CommonShell/CommonProcess; never use
  `Foundation.Process`.
- Prefer Swift over Python for automation; keep shell snippets minimal.
- Do not add Makefiles.
- Git operations require explicit human approval.
