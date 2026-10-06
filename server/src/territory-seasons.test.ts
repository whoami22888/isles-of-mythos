import {describe,expect,it} from "vitest";
import {SEASON_INTERVAL_SECONDS} from "./territory-seasons.js";
describe("Gate 16 territory seasons",()=>{
 it("uses a bounded timestamp scoring interval",()=>expect(SEASON_INTERVAL_SECONDS).toBe(60));
});
