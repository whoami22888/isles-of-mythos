// MYTHOS-NET-05: bounded, paginated server->client creature snapshots.
//
// The server's 64 KiB `maxPayload` only bounds frames a client SENDS. Server->client
// snapshots were unbounded: `creature_party` carried every owned creature in one frame,
// so a large collection could exceed what a client accepts and be dropped after a
// successful login. Snapshots are now split by serialized (UTF-8) size.
//
// Wire contract (additive, backward compatible for collections that fit one page):
//   page 0      -> { type:"creature_party", creatures, snapshotId, page:0, pageCount, total }
//   pages 1..n  -> { type:"creature_party_page", creatures, snapshotId, page, pageCount, total }
// Pages of one snapshot share `snapshotId`, are sent consecutively on one socket, and
// `creatures` across pages concatenates (in order) to the complete owned collection.
// Every frame is within CREATURE_SNAPSHOT_PAGE_BYTES; a creature that cannot fit one frame is
// rejected (CreatureTooLargeError) instead of being emitted oversize or dropped.
// Clients reassemble and must discard a partial snapshot on a gap or a lost connection;
// the server re-sends a fresh, complete snapshot after every authentication.

export const CREATURE_SNAPSHOT_PAGE_BYTES = 49152;

export interface CreatureSnapshotFrame {
  type: "creature_party" | "creature_party_page";
  snapshotId: number;
  page: number;
  pageCount: number;
  total: number;
  creatures: unknown[];
}

// Worst-case envelope (longest type name, widest numbers) reserved from every page budget.
const ENVELOPE_RESERVE_BYTES = Buffer.byteLength(
  JSON.stringify({
    type: "creature_party_page",
    snapshotId: Number.MAX_SAFE_INTEGER,
    page: 999999,
    pageCount: 999999,
    total: 99999999,
    creatures: [],
  }),
  "utf8",
);

/**
 * A single creature whose serialized form cannot fit one budgeted frame. Normal rows are a few
 * hundred bytes (nickname is varchar(32)); only a corrupt `ability_ids` array can reach this.
 * Carries sizes only, never creature data or identifiers.
 */
export class CreatureTooLargeError extends Error {
  constructor(readonly bytes: number, readonly maxBytes: number, readonly index: number) {
    super(`creature snapshot item exceeds the per-frame bound (${bytes} > ${maxBytes} bytes)`);
    this.name = "CreatureTooLargeError";
  }
}

export function buildCreatureSnapshotFrames(
  creatures: readonly unknown[],
  snapshotId: number,
  pageBytes: number = CREATURE_SNAPSHOT_PAGE_BYTES,
): CreatureSnapshotFrame[] {
  if (!Number.isFinite(pageBytes) || pageBytes <= 0) throw new RangeError("pageBytes must be a positive finite number");
  const budget = Math.max(1, Math.floor(pageBytes) - ENVELOPE_RESERVE_BYTES);

  const pages: unknown[][] = [];
  let current: unknown[] = [];
  let currentBytes = 0;
  let index = 0;
  for (const creature of creatures) {
    // One serialization per creature; +1 accounts for the separating comma.
    const size = Buffer.byteLength(JSON.stringify(creature), "utf8") + 1;
    // Every emitted frame must stay within the budget: a creature that cannot fit a frame on its
    // own is rejected before anything is built, never emitted oversize and never silently dropped.
    if (size > budget) throw new CreatureTooLargeError(size - 1, budget - 1, index);
    if (current.length > 0 && currentBytes + size > budget) {
      pages.push(current);
      current = [];
      currentBytes = 0;
    }
    current.push(creature);
    currentBytes += size;
    index += 1;
  }
  pages.push(current); // always at least one page, so an empty collection still yields a frame

  return pages.map((page, index) => ({
    type: index === 0 ? "creature_party" : "creature_party_page",
    snapshotId,
    page: index,
    pageCount: pages.length,
    total: creatures.length,
    creatures: page,
  }));
}
