import { execFileSync } from "node:child_process";
import { describe, expect, it } from "vitest";

// Runtime datastore snapshots (Redis RDB/AOF) can embed test or session state and are never source fixtures.
const DATASTORE_ARTIFACT = /(^|\/)(dump\.rdb|appendonly\.aof|[^/]+\.(rdb|aof)|appendonlydir\/.*)$/i;

function trackedFiles(): string[] | null {
  try {
    return execFileSync("git", ["ls-files", "-z"], { encoding: "utf8", cwd: new URL("../..", import.meta.url) })
      .split("\0").filter(Boolean);
  } catch {
    return null; // not a git checkout (e.g. packaged source); nothing to inspect
  }
}

describe("repository hygiene", () => {
  it("does not track Redis RDB/AOF datastore artifacts", () => {
    const files = trackedFiles();
    if (files === null) return;
    expect(files.filter(f => DATASTORE_ARTIFACT.test(f))).toEqual([]);
  });

  it("recognises the artifact shapes it must reject", () => {
    for (const f of ["server/dump.rdb", "dump.rdb", "data/x.rdb", "appendonly.aof", "appendonlydir/a.aof"]) {
      expect(DATASTORE_ARTIFACT.test(f), f).toBe(true);
    }
    for (const f of ["server/src/anti-cheat.ts", "docs/rdbms.md"]) expect(DATASTORE_ARTIFACT.test(f), f).toBe(false);
  });
});
