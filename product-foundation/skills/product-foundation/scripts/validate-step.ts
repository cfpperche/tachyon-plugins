/**
 * validate-step.ts — the plugin-native Layer-1 schema-floor validator (re-homes the
 * dead pipeline-MCP's validate-then-write invariant).
 *
 * A step's `schema.md` declares its Layer-1 floor in a fenced ```required_files``` JSON block:
 *   { "required_files": [ { "path", "min_size", "contains": [...], "any_of_contains"?: [...] } ] }
 *
 * The orchestrator (SKILL.md body) MUST run this AFTER a step's producer returns and BEFORE it
 * advances `.state.json`. On a failure it prints a `schema-incomplete` result (which file/floor
 * failed) and exits NON-ZERO — the body re-dispatches the step and does NOT advance. On success
 * it exits 0. This is the mechanical floor; the quality judge is the orthogonal semantic verdict.
 *
 * Invocation (bun): the artifact files are passed in the SAME ORDER as the schema's required_files[]
 * (primary first, then any extra_files), so a path-vs-basename rename never breaks matching:
 *   bun scripts/validate-step.ts <schema.md> <file0> [file1 ...] [--json]
 *
 * Exit: 0 all floors pass · 1 schema-incomplete (≥1 floor failed) · 2 usage / unreadable schema.
 */

import { readFileSync, statSync, existsSync } from "node:fs";

interface FloorEntry {
  path: string;
  min_size?: number;
  contains?: string[];
  any_of_contains?: string[];
}
interface Failure {
  file: string;
  reason: string;
}

/** Extract the `required_files` array from the schema.md's fenced block (```required_files``` or a
 *  fenced JSON block that carries a `required_files` key). Returns null if none is declared. */
export function extractFloor(schemaText: string): FloorEntry[] | null {
  // REQUIRE an explicit `required_files` (or `json`) fence tag — matching bare ``` closings as openings
  // misaligns the pairing when a schema has earlier ```markdown/```yaml example blocks.
  const fences = schemaText.matchAll(/```(?:required_files|json)[ \t]*\r?\n([\s\S]*?)\r?\n```/g);
  for (const m of fences) {
    const body = m[1].trim();
    if (!body.includes("required_files")) continue;
    try {
      const parsed = JSON.parse(body) as { required_files?: FloorEntry[] };
      if (Array.isArray(parsed.required_files)) return parsed.required_files;
    } catch {
      /* not this fence */
    }
  }
  return null;
}

/** Validate the produced artifact files (in schema order) against the floor. */
export function validate(floor: FloorEntry[], files: string[]): Failure[] {
  const failures: Failure[] = [];
  floor.forEach((entry, i) => {
    const f = files[i];
    const label = entry.path || `file[${i}]`;
    if (!f || !existsSync(f)) {
      failures.push({ file: label, reason: `missing — no artifact produced for required file '${label}'` });
      return;
    }
    const size = statSync(f).size;
    if (typeof entry.min_size === "number" && size < entry.min_size) {
      failures.push({ file: label, reason: `under the size floor (${size} < ${entry.min_size} bytes) — likely a stub` });
    }
    const text = readFileSync(f, "utf8");
    for (const needle of entry.contains ?? []) {
      if (!text.includes(needle)) failures.push({ file: label, reason: `missing required anchor: ${JSON.stringify(needle)}` });
    }
    if (Array.isArray(entry.any_of_contains) && entry.any_of_contains.length > 0) {
      if (!entry.any_of_contains.some((n) => text.includes(n))) {
        failures.push({ file: label, reason: `none of the required alternatives present: ${JSON.stringify(entry.any_of_contains)}` });
      }
    }
  });
  return failures;
}

function main(argv: string[]): number {
  const json = argv.includes("--json");
  const pos = argv.filter((a) => a !== "--json");
  const schemaPath = pos[0];
  const files = pos.slice(1);
  if (!schemaPath || !existsSync(schemaPath)) {
    process.stderr.write("usage: bun scripts/validate-step.ts <schema.md> <file0> [file1 ...] [--json]\n");
    return 2;
  }
  const floor = extractFloor(readFileSync(schemaPath, "utf8"));
  if (floor === null) {
    // No machine-readable floor → nothing to enforce mechanically (the judge still grades it).
    process.stdout.write(json ? JSON.stringify({ code: "no-floor", schema: schemaPath }) + "\n" : `validate-step: no required_files floor in ${schemaPath} — skipping mechanical check\n`);
    return 0;
  }
  const failures = validate(floor, files);
  if (failures.length === 0) {
    process.stdout.write(json ? JSON.stringify({ code: "ok", checked: floor.length }) + "\n" : `validate-step: ok (${floor.length} file floor[s] passed)\n`);
    return 0;
  }
  if (json) {
    process.stdout.write(JSON.stringify({ code: "schema-incomplete", missing_or_invalid: failures }) + "\n");
  } else {
    process.stdout.write(`validate-step: schema-incomplete — ${failures.length} floor failure(s); the step did NOT pass, do NOT advance:\n`);
    for (const fl of failures) process.stdout.write(`  ✗ ${fl.file}: ${fl.reason}\n`);
  }
  return 1;
}

if (import.meta.main) {
  process.exit(main(process.argv.slice(2)));
}
