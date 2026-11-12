"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { mkdtempSync, mkdirSync, writeFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { createHash } = require("node:crypto");
const { validateVendorLock } = require("../scripts/validate_vendor_lock.js");

function fixture(revision, vendor = "Example Vendor") {
  const root = mkdtempSync(join(tmpdir(), "iom-vendor-provenance-"));
  mkdirSync(join(root, "assets-src"));
  mkdirSync(join(root, "licenses"));
  const bytes = Buffer.from("fixture asset bytes");
  writeFileSync(join(root, "assets-src", "sample.bin"), bytes);
  writeFileSync(join(root, "licenses", "sample.txt"), "MIT test fixture");
  writeFileSync(join(root, "vendor.lock.json"), JSON.stringify({
    version: "1",
    assets: [{
      path: "assets-src/sample.bin",
      sha256: createHash("sha256").update(bytes).digest("hex"),
      license: "MIT",
      license_path: "licenses/sample.txt",
      source_url: "https://example.org/source",
      vendor,
      source_revision: revision
    }]
  }));
  return root;
}

test("valid immutable revision and vendor pass", () => {
  const root = fixture("a".repeat(40));
  try { assert.deepEqual(validateVendorLock(root), []); }
  finally { rmSync(root, { recursive: true, force: true }); }
});

test("missing vendor fails", () => {
  const root = fixture("a".repeat(40), "");
  try { assert.match(validateVendorLock(root).join("\n"), /vendor must be a non-empty string/); }
  finally { rmSync(root, { recursive: true, force: true }); }
});

for (const revision of ["", "main", "ABCDEF".repeat(7), "f".repeat(39)]) {
  test("invalid revision is rejected: " + JSON.stringify(revision), () => {
    const root = fixture(revision);
    try { assert.match(validateVendorLock(root).join("\n"), /source_revision must be an immutable/); }
    finally { rmSync(root, { recursive: true, force: true }); }
  });
}
