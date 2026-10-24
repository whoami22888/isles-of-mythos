import { describe, expect, it } from "vitest";
import type { Pool } from "pg";
import { CreatureResearchStore } from "./creature-research-store.js";

describe("research progression persistence contract", () => {
  it("rejects invalid caller-origin event ids before connecting to database", async () => {
    const db={connect:()=>{throw new Error("DATABASE_SHOULD_NOT_BE_TOUCHED");}} as unknown as Pool;
    const store=new CreatureResearchStore(db);
    await expect(store.unlock("player", "", "tracking")).rejects.toThrow("INVALID_PROGRESSION_REQUEST_ID");
    await expect(store.awardPlayerPractice("player", "#bad", "tracking", 10)).rejects.toThrow("INVALID_PROGRESSION_REQUEST_ID");
    await expect(store.awardCreatureTraining("player", "", "creature", 10)).rejects.toThrow("INVALID_PROGRESSION_REQUEST_ID");
  });
  it("rejects fabricated practice awards before DB access", async () => {
    const db={connect:()=>{throw new Error("DATABASE_SHOULD_NOT_BE_TOUCHED");}} as unknown as Pool;
    const store=new CreatureResearchStore(db);
    await expect(store.awardPlayerPractice("player", "server:event-1", "tracking", 0)).rejects.toThrow("INVALID_PRACTICE_AWARD");
    await expect(store.awardCreatureTraining("player", "server:event-2", "creature", 999)).rejects.toThrow("INVALID_PRACTICE_AWARD");
  });
});
