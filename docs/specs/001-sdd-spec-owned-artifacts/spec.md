# 001 — sdd-spec-owned-artifacts

_Created 2026-07-21._

**Status:** shipped
**Closure:** implemented in the source plugin worktree at version 1.6.0; focused verification and scaffold dogfood passed on 2026-07-21 (see `notes.md`). Publishing/tagging and reinstalling the immutable Tachyon materialization remain release operations.
<!-- Bare enum only: draft | in-progress | shipped | shipped-partial | superseded | abandoned | deferred.
     When this ships, add a **Closure:** line here recording what shipped (commit/evidence);
     `/sdd close` flags a shipped spec that still lacks one (alongside unchecked boxes,
     placeholders, and missing dogfood proof or opt-out). -->

## Intent

The SDD plugin owns the lifecycle of a spec but currently leaves durable auxiliary artifacts such as prototypes, screenshots, diagrams, and reviews without a location contract. Agents can therefore create spec-specific files in global staging folders, or cite files that do not exist, while still satisfying the current closure audit.

Make artifact ownership explicit without making artifacts mandatory: a spec continues to scaffold only its four core Markdown files; when an author opts into a durable spec-specific artifact, it belongs under that spec directory unless a reasoned exception is declared. Closure should surface missing or externally-owned declared artifacts as compatibility-safe warnings.

## Acceptance criteria

- [x] **Scenario: optional artifacts stay optional**
  - **Given** a user scaffolds a new spec
  - **When** `new.sh` completes
  - **Then** only `spec.md`, `plan.md`, `tasks.md`, and `notes.md` are created, and the output explains where opt-in artifacts belong
- [x] **Scenario: spec-local artifact declaration**
  - **Given** a shipped spec declares an existing prototype or evidence file under its own directory
  - **When** `sdd-close.sh` audits the spec
  - **Then** no artifact-locality or artifact-missing warning is emitted
- [x] **Scenario: external artifact declaration**
  - **Given** a shipped spec declares a local artifact outside its own directory
  - **When** `sdd-close.sh` audits the spec without a reasoned location opt-out
  - **Then** it emits warning-only `artifact-outside-spec` with the path in human and JSON output
- [x] **Scenario: missing artifact declaration**
  - **Given** a shipped spec declares a local artifact path that does not exist
  - **When** `sdd-close.sh` audits the spec
  - **Then** it emits warning-only `artifact-missing` with the path in human and JSON output
- [x] **Scenario: reasoned exception**
  - **Given** a shipped spec declares an external artifact plus `Artifact-Location-Opt-Out` with a non-empty reason
  - **When** `sdd-close.sh` audits the spec
  - **Then** outside-spec ownership is accepted and the reason remains visible as a warning
- [x] URLs, preview routes, commands, and manual visual passes are not misclassified as local artifact files.
- [x] README, skill instructions, and templates state that prototypes/evidence are opt-in and spec-local when created.

## Non-goals

- Creating a prototype, evidence directory, or review for every spec.
- Adding an artifact scaffold subcommand before repeated demand proves it useful.
- Rejecting product-published assets or canonical executable fixtures that have a documented external owner.
- Turning artifact-locality warnings into blocking closure findings in the first release.

## Open questions

None. The maintainer explicitly ratified opt-in artifact creation and spec-local ownership when an artifact exists.
