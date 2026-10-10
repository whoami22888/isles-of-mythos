export type EngineState = "menu" | "overworld" | "base-build" | "combat-ui";

const TRANSITIONS: Readonly<Record<EngineState, readonly EngineState[]>> = {
  menu: ["overworld"],
  overworld: ["menu", "base-build", "combat-ui"],
  "base-build": ["overworld"],
  "combat-ui": ["overworld"],
};

export class EngineStateManager {
  private current: EngineState = "menu";

  get state(): EngineState {
    return this.current;
  }

  transition(next: EngineState): EngineState {
    if (next === this.current) return this.current;
    if (!TRANSITIONS[this.current].includes(next)) {
      throw new Error(`INVALID_ENGINE_STATE_TRANSITION:${this.current}->${next}`);
    }
    this.current = next;
    return this.current;
  }
}

/** Prevents long suspended-tab frames from producing oversized gameplay deltas. */
export function normalizeFrameDelta(deltaMs: number, maximumDeltaMs = 100): number {
  if (!Number.isFinite(maximumDeltaMs) || maximumDeltaMs <= 0) {
    throw new RangeError("INVALID_MAXIMUM_FRAME_DELTA");
  }
  if (!Number.isFinite(deltaMs) || deltaMs <= 0) return 0;
  return Math.min(deltaMs, maximumDeltaMs);
}
