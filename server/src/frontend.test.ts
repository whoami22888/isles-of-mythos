import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { buildApp } from "./app.js";

describe("production frontend delivery", () => {
  const tempDirectories: string[] = [];

  afterEach(async () => {
    await Promise.all(tempDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
  });

  it("serves the built client and SPA fallback without exposing protected backend paths", async () => {
    const directory = await mkdtemp(join(tmpdir(), "isles-client-"));
    tempDirectories.push(directory);
    await writeFile(join(directory, "index.html"), "<!doctype html><title>Isles of Mythos</title>");
    await writeFile(join(directory, "app.js"), "console.log('isles');");

    const app = await buildApp({ clientDistDir: directory });
    try {
      const root = await app.inject({ method: "GET", url: "/" });
      expect(root.statusCode).toBe(200);
      expect(root.headers["content-type"]).toContain("text/html");
      expect(root.headers["cache-control"]).toBe("no-cache");
      expect(root.body).toContain("Isles of Mythos");

      const asset = await app.inject({ method: "GET", url: "/app.js" });
      expect(asset.statusCode).toBe(200);
      expect(asset.headers["content-type"]).toContain("text/javascript");
      expect(asset.headers["cache-control"]).toContain("immutable");
      expect(asset.body).toContain("console.log");

      const spa = await app.inject({ method: "GET", url: "/account/settings" });
      expect(spa.statusCode).toBe(200);
      expect(spa.body).toContain("Isles of Mythos");

      const traversal = await app.inject({ method: "GET", url: "/%2e%2e/%2e%2e/package.json" });
      expect(traversal.statusCode).toBe(400);

      const backend = await app.inject({ method: "GET", url: "/health" });
      expect(backend.statusCode).toBe(200);
    } finally {
      await app.close();
    }
  });
});
