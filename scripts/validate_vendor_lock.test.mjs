import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import test from "node:test";

const { validateVendorLock } = createRequire(import.meta.url)("./validate_vendor_lock.js");
const sha = (text) => createHash("sha256").update(text).digest("hex");

function repo(files = {}, lock, manifest) {
  const root = mkdtempSync(join(tmpdir(), "vendor-lock-"));
  for (const [path, body] of Object.entries(files)) {
    mkdirSync(join(root, path, ".."), { recursive: true });
    writeFileSync(join(root, path), body);
  }
  writeFileSync(join(root, "vendor.lock.json"), JSON.stringify(lock ?? { version: "1.0.0", assets: [] }));
  if (manifest) {
    mkdirSync(join(root, "client-godot/assets"), { recursive: true });
    writeFileSync(join(root, "client-godot/assets/external-assets.json"), JSON.stringify(manifest));
  }
  return root;
}
const entry = (over = {}) => ({
  path: "vendor/kit/palm.glb", sha256: sha("palm"), license: "CC0-1.0",
  license_path: "vendor/kit/LICENSE.txt", source_url: "https://polyhaven.com/a/palm", ...over
});
const good = { "vendor/kit/palm.glb": "palm", "vendor/kit/LICENSE.txt": "CC0" };

test("an empty lock is valid", () => {
  assert.deepEqual(validateVendorLock(repo()), []);
});
test("a fully verified entry passes", () => {
  assert.deepEqual(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry()] })), []);
});
test("a missing lock file fails closed", () => {
  const root = mkdtempSync(join(tmpdir(), "vendor-lock-"));
  assert.match(validateVendorLock(root).join("\n"), /vendor\.lock\.json/);
});
test("a SHA-256 mismatch is rejected", () => {
  const errs = validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ sha256: sha("other") })] }));
  assert.match(errs.join("\n"), /sha256 mismatch/i);
});
test("a malformed or missing SHA-256 is rejected", () => {
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ sha256: "abc" })] })).join("\n"), /sha256/i);
  const { sha256, ...rest } = entry();
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [rest] })).join("\n"), /sha256/i);
});
test("a missing license_path or a license file that does not exist is rejected", () => {
  const { license_path, ...rest } = entry();
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [rest] })).join("\n"), /license_path/);
  const noFile = { "vendor/kit/palm.glb": "palm" };
  assert.match(validateVendorLock(repo(noFile, { version: "1.0.0", assets: [entry()] })).join("\n"), /license file/i);
});
test("licences outside the allowlist are rejected", () => {
  const errs = validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ license: "CC-BY-NC-4.0" })] }));
  assert.match(errs.join("\n"), /license/i);
});
test("path traversal and absolute paths are rejected", () => {
  for (const path of ["../outside.glb", "/etc/passwd"]) {
    assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ path })] })).join("\n"), /path/i);
  }
});
test("duplicate paths are rejected", () => {
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry(), entry()] })).join("\n"), /duplicate/i);
});
test("a non-https source_url is rejected", () => {
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ source_url: "http://x.test/a" })] })).join("\n"), /source_url/);
});
test("unknown top-level or entry keys are rejected (no silent schema drift)", () => {
  assert.match(validateVendorLock(repo({}, { version: "1.0.0", assets: [], extra: 1 })).join("\n"), /unknown/i);
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ surprise: 1 })] })).join("\n"), /unknown/i);
});
test("an entry also in external-assets.json must agree on the digest", () => {
  const ext = "client-godot/assets/external/vendor/kit/palm.glb";
  const files = { [ext]: "palm", "vendor/kit/LICENSE.txt": "CC0" };
  const lock = { version: "1.0.0", assets: [entry({ path: ext })] };
  const bad = { schema_version: 1, assets: [{ path: "vendor/kit/palm.glb", sha256: sha("different") }] };
  assert.match(validateVendorLock(repo(files, lock, bad)).join("\n"), /external-assets\.json/);
  const ok = { schema_version: 1, assets: [{ path: "vendor/kit/palm.glb", sha256: sha("palm") }] };
  assert.deepEqual(validateVendorLock(repo(files, lock, ok)), []);
});
test("a third-party file under client-godot/assets/external that is in neither registry is rejected", () => {
  const files = { ...good, "client-godot/assets/external/polyhaven/x/x.glb": "x" };
  const errs = validateVendorLock(repo(files, undefined, { schema_version: 1, assets: [] }));
  assert.match(errs.join("\n"), /unregistered/i);
});
test("a third-party file registered only in external-assets.json is accepted", () => {
  const files = { "client-godot/assets/external/polyhaven/x/x.glb": "x" };
  const manifest = { schema_version: 1, assets: [{ path: "polyhaven/x/x.glb", sha256: sha("x") }] };
  assert.deepEqual(validateVendorLock(repo(files, undefined, manifest)), []);
});

test("falsy or non-object JSON documents are rejected, never treated as an empty lock (Codex P2)", () => {
  for (const body of ["null", "false", "0", '""', "[]", "true"]) {
    const root = mkdtempSync(join(tmpdir(), "vendor-lock-"));
    writeFileSync(join(root, "vendor.lock.json"), body);
    const errs = validateVendorLock(root);
    assert.ok(errs.length > 0, `body ${body} must fail`);
  }
});
test("a malformed external-assets.json fails closed", () => {
  const root = repo({}, undefined, null);
  mkdirSync(join(root, "client-godot/assets"), { recursive: true });
  for (const body of ["null", "0", '{"assets": 3}']) {
    writeFileSync(join(root, "client-godot/assets/external-assets.json"), body);
    assert.ok(validateVendorLock(root).length > 0, body);
  }
});
test("a symlinked parent directory cannot smuggle files from outside the repository (Codex P2)", () => {
  const outside = mkdtempSync(join(tmpdir(), "outside-"));
  writeFileSync(join(outside, "asset.bin"), "palm");
  writeFileSync(join(outside, "LICENSE.txt"), "CC0");
  const root = repo({}, { version: "1.0.0", assets: [entry({ path: "vendor/asset.bin", license_path: "vendor/LICENSE.txt" })] });
  symlinkSync(outside, join(root, "vendor"));
  const errs = validateVendorLock(root).join("\n");
  assert.match(errs, /symlink|outside/i);
});
test("a symlinked licence directory is rejected too", () => {
  const outside = mkdtempSync(join(tmpdir(), "outside-"));
  writeFileSync(join(outside, "LICENSE.txt"), "CC0");
  const root = repo({ "vendor/kit/palm.glb": "palm" }, { version: "1.0.0", assets: [entry({ license_path: "lic/LICENSE.txt" })] });
  symlinkSync(outside, join(root, "lic"));
  assert.match(validateVendorLock(root).join("\n"), /symlink|outside|license file/i);
});
