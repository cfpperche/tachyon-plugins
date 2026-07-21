# 001 — sdd-spec-owned-artifacts — plan

_Drafted from `spec.md` on 2026-07-21. The approach, not the steps (those go in `tasks.md`)._

## Approach

Extend the prose contract and scaffold nudges, then add a conservative declaration parser to `sdd-close.sh`. The parser only treats backticked values on `Prototype:` or `Evidence:` lines as local artifacts when they look like durable file paths. It resolves workspace-relative paths (`docs/...`, `test/...`, absolute paths) and spec-relative paths (`./...`, `prototype.*`, `prototypes/...`, `evidence/...`, `reviews/...`). URLs, preview routes, and prose evidence remain untouched.

Artifact locality is warning-only for compatibility. A non-empty `**Artifact-Location-Opt-Out:**` accepts an external location while keeping the reason visible. Missing declared local files still warn because an ownership exception cannot make absent evidence exist.

## Key decisions

_Each decision + why this option over the alternatives considered. Record rejected alternatives — they explain the design as much as the chosen path does._

- **Opt-in, never scaffolded by default** — chosen because most specs need no prototype or durable visual file; rejected empty `prototype.html`/`evidence/` creation because it produces noise and empty directories are not tracked.
- **Declaration-based validation** — chosen because `Prototype:`/`Evidence:` express ownership intent; rejected scanning every path in a spec because architecture links, code files, fixtures, and published assets would create false positives.
- **Warning-first rollout** — chosen for compatibility with existing projects and legitimate external assets; rejected an immediate hard close failure because the plugin has never previously declared this contract.
- **Reasoned opt-out** — chosen because published docs assets and canonical project fixtures can legitimately live elsewhere; rejected a blanket ban on `docs/assets/` because the plugin is project-neutral.
- **No artifact helper yet** — chosen because contract + templates + close provide the needed forcing function; rejected a generic generator because artifact content and formats vary too widely.

## Files touched

- `sdd/skills/sdd/SKILL.md` — define spec-owned artifacts and closure warnings.
- `sdd/README.md` — document the human-facing policy and closure behavior.
- `sdd/skills/sdd/templates/plan.md.tmpl` — make artifact ownership explicit during planning.
- `sdd/skills/sdd/templates/tasks.md.tmpl` — give spec-local declaration examples.
- `sdd/skills/sdd/scripts/new.sh` — print a non-creating locality reminder.
- `sdd/skills/sdd/scripts/sdd-close.sh` — parse declared artifacts and emit warnings/JSON.
- `sdd/skills/sdd/scripts/test-artifact-locality-close.sh` — focused regression matrix.
- `sdd/tachyon-plugin.json` — bump the plugin feature version to 1.6.0.
- `README.md` — update the repository plugin summary.
- `docs/specs/001-sdd-spec-owned-artifacts/*` — contract, plan, tasks, and verification notes.

## Risks & unknowns

- Shell parsing could classify a preview route or command as a file; constrain candidates by declaration label and artifact-like file extension.
- Relative paths could escape with `..`; treat any parent traversal as outside ownership.
- Valid external assets could warn; provide a reasoned opt-out and keep rollout warning-only.
- Installed copies are immutable materializations; change the source plugin, validate it, publish a new ref, then reinstall through Tachyon rather than editing `.agents/skills/sdd` directly.

## Visual impact

No product UI changes. Human-facing terminal output from `new.sh` and `sdd-close.sh` changes. Focused shell tests cover exact warning names and JSON shape.

## Sources consulted

- `/home/goat/tachyon-plugins/sdd/skills/sdd/SKILL.md`
- `/home/goat/tachyon-plugins/sdd/skills/sdd/scripts/{new.sh,sdd-close.sh}`
- `/home/goat/tachyon-plugins/sdd/skills/sdd/templates/{plan,tasks}.md.tmpl`
- `/home/goat/tachyon-plugins/sdd/skills/sdd/scripts/test-{visual,cookbook}-close.sh`
- Tachyon SDD 390 prototype history and the missing SDD 386 prototype reference.
