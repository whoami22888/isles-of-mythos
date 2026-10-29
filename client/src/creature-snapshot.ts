import type { CreatureState } from "./network.js";

// MYTHOS-NET-05: reassembles bounded, paginated server->client creature snapshots into one
// complete creature list so the UI never replaces its collection with a partial page.
// Mirrors client-godot/scripts/creature_snapshot_assembler.gd and server/src/creature-snapshot.ts.

export const MAX_SNAPSHOT_PAGES = 1024;
export const MAX_SNAPSHOT_CREATURES = 50000;

export type SnapshotFrame = {
  type: "creature_party" | "creature_party_page";
  creatures: CreatureState[];
  snapshotId?: number;
  page?: number;
  pageCount?: number;
  total?: number;
};

export type SnapshotResult = {
  status: "ignored" | "partial" | "complete" | "error";
  reason?: string;
  message?: { type: "creature_party"; creatures: CreatureState[]; total: number };
};

export type SnapshotInput = { type: string; [key: string]: unknown };

const isCount = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;

export class CreatureSnapshotAssembler {
  private active = false;
  private snapshotId = 0;
  private pageCount = 0;
  private total = 0;
  private nextPage = 0;
  private creatures: CreatureState[] = [];

  isPartial(): boolean {
    return this.active;
  }

  /** Call when the connection is lost: a partial snapshot can never be completed. */
  reset(): void {
    this.active = false;
    this.snapshotId = 0;
    this.pageCount = 0;
    this.total = 0;
    this.nextPage = 0;
    this.creatures = [];
  }

  feed(message: SnapshotInput): SnapshotResult {
    if (message.type !== "creature_party" && message.type !== "creature_party_page") return { status: "ignored" };
    if (!Array.isArray(message.creatures)) return this.fail("snapshot_malformed");
    const creatures = message.creatures as CreatureState[];

    // Legacy single-frame form: no paging metadata at all.
    if (message.type === "creature_party" && message.page === undefined && message.pageCount === undefined) {
      this.reset();
      return { status: "complete", message: { type: "creature_party", creatures, total: creatures.length } };
    }

    const { page, pageCount, total, snapshotId } = message;
    if (!isCount(page) || !isCount(pageCount) || !isCount(total) || !isCount(snapshotId) || pageCount < 1 || page >= pageCount) {
      return this.fail("snapshot_malformed");
    }
    if ((message.type === "creature_party") !== (page === 0)) return this.fail("snapshot_malformed");
    if (pageCount > MAX_SNAPSHOT_PAGES || total > MAX_SNAPSHOT_CREATURES) return this.fail("snapshot_too_large");

    if (page === 0) {
      // A new first page always supersedes an incomplete snapshot (e.g. a re-send).
      this.reset();
      this.active = true;
      this.snapshotId = snapshotId;
      this.pageCount = pageCount;
      this.total = total;
    } else {
      if (!this.active) return this.fail("snapshot_orphan_page");
      if (snapshotId !== this.snapshotId) return this.fail("snapshot_id_mismatch");
      if (pageCount !== this.pageCount || total !== this.total) return this.fail("snapshot_malformed");
      if (page !== this.nextPage) return this.fail("snapshot_page_gap");
    }

    if (this.creatures.length + creatures.length > this.total) return this.fail("snapshot_total_mismatch");
    for (const creature of creatures) this.creatures.push(creature);
    this.nextPage = page + 1;
    if (this.nextPage < this.pageCount) return { status: "partial" };
    if (this.creatures.length !== this.total) return this.fail("snapshot_total_mismatch");
    const complete = { type: "creature_party" as const, creatures: this.creatures, total: this.total };
    this.reset();
    return { status: "complete", message: complete };
  }

  private fail(reason: string): SnapshotResult {
    this.reset();
    return { status: "error", reason };
  }
}
