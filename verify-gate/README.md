# verify-gate

A landing gate for your trunk. Before a push reaches a protected branch, run the project's
verification command; if it fails, the push is refused.

## Why

Most projects already have a verification command and a CI that runs it. Both can be absent at the
moment it matters:

- CI runs **after** the push, so it reports damage rather than preventing it.
- Required status checks need branch protection, which on GitHub means a public repo or a paid plan.
- CI minutes run out.
- And plenty of work never goes through a pull request at all — it is merged locally and pushed.

What is left holding the trunk is discipline: remembering to run the suite before pushing. That
works until someone is in a hurry, or an unattended agent lands work and stops.

This plugin closes that gap locally, with no service and no plan tier.

## What it does

Git feeds `pre-push` one line per ref on stdin:

```
<local ref> <local sha> <remote ref> <remote sha>
```

The gate reads those lines and only acts when a ref targets a protected branch. A push to a feature
branch exits immediately and costs nothing. A branch deletion lands no code, so it is skipped too.

When the push does target the trunk, it runs your verification command and refuses the push on a
non-zero exit, propagating that exit code.

## Install

```
Plugins → install → verify-gate
```

Nothing else is required if your `package.json` already has a `verify:full`, `verify` or `test`
script — the gate finds it.

## Configure

Everything is read from the environment, so nothing in the plugin is project-specific.

| Variable | Default | Meaning |
|---|---|---|
| `VERIFY_GATE_BRANCHES` | `main master` | Space/comma list of protected branch names |
| `VERIFY_GATE_CMD` | resolved from `package.json` | The command to run |
| `VERIFY_GATE_SKIP=1` | unset | Bypass the gate for one push |

Command resolution, when `VERIFY_GATE_CMD` is unset: the first of `verify:full`, `verify`, `test`
declared in `package.json` scripts.

## Fail-closed

If the gate cannot resolve a command, it **refuses the push** rather than letting it through.
Installing the plugin is the opt-in to gating, so a gate that does not know what to run is a
misconfiguration, not permission to skip. The refusal message names both fixes.

## What this is not

It is a floor, not a vault. `git push --no-verify` skips git hooks entirely — no client-side hook
can prevent that. `VERIFY_GATE_SKIP=1` exists so that a deliberate bypass is at least explicit and
visible in shell history rather than reaching for `--no-verify` out of habit.

If you need a bypass nobody can take, that is server-side: branch protection with required status
checks. This plugin is for the very common case where that is unavailable or turned off, and the
alternative today is nothing at all.

## Cost

The gate runs your full verification on every push to the trunk, which is the point. Keep that
command fast enough that you do not resent it — if it takes minutes, consider pointing
`VERIFY_GATE_CMD` at a quicker subset and leaving the exhaustive run to your landing ritual.

Measure before splitting it, though. On the repository this was built in, the parallelized full
gate finished in **80s**, while a hand-picked "fast subset" of typecheck plus unit tests took
**137s** run sequentially — the full gate was cheaper *and* complete.
