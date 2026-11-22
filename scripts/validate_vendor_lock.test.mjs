import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import test from "node:test";

const { validateVendorLock } = createRequire(import.meta.url)("./validate_vendor_lock.js");
const sha = (text) => createHash("sha256").update(text).digest("hex");

function repo(files = {}, lock, manifest, { omitQuarantineRegistry = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), "vendor-lock-"));
  const fixtureFiles = omitQuarantineRegistry
    ? files
    : { [QUARANTINE_PATH]: JSON.stringify(quarantineRegistry()), ...files };
  for (const [path, body] of Object.entries(fixtureFiles)) {
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
  license_path: "vendor/kit/LICENSE.txt", license_sha256: sha("CC0"), source_url: "https://polyhaven.com/a/palm",
  vendor: "Test Fixture Vendor", source_revision: "1234567890abcdef1234567890abcdef12345678", pack_id: "test-vendor:kit", ...over
});
const good = { "vendor/kit/palm.glb": "palm", "vendor/kit/LICENSE.txt": "CC0" };
const QUARANTINE_PATH = "docs/vendor/quarantine/quaternius-h05-h06.json";
const QUARANTINED_ARCHIVE_PATH = "assets-src/quaternius/H05/ultimate-monsters.zip";
const QUARANTINED_H06_ARCHIVE_PATH = "assets-src/quaternius/H06/cute-animated-monsters.zip";
const QUARANTINED_H05_SHA256 = "f444a35e70895f822f3687eb47e608801baf98f2ae86c7ed24b6c017842f006d";
const QUARANTINED_H06_SHA256 = "93bb9e0cdd678ddd4367402a38f931d57fd52280b0c50f5075212a216ae673a3";
const QUARANTINED_SOURCES = [
  {
    harvest_id: "H05",
    pack_id: "quaternius:H05-ultimate-monsters",
    vendor: "Quaternius",
    archive_path: QUARANTINED_ARCHIVE_PATH,
    archive_sha256: QUARANTINED_H05_SHA256,
    archive_size_bytes: 46576830,
    archive_file_count: 260,
    zip_crc: "PASS",
    gltf_dependency_closure: "PASS",
    publisher_page: "https://quaternius.com/packs/ultimatemonsters.html",
    publisher_page_sha256: "5adff0c0a2d5677f59b9810cf7e40d13a72234dafcd1b50968dbdb149c9cb563",
    acquisition_workflow_run_id: 44736035009,
    historical_acquisition_commit: "b0c597fb13ff671d43e437a9c84a10dbfb723bec",
    admission_status: "LICENSE_REVIEW_REQUIRED",
    public_source_redistribution: "BLOCKED",
    production_admission: "NOT_ADMITTED"
  },
  {
    harvest_id: "H06",
    pack_id: "quaternius:H06-cute-animated-monsters",
    vendor: "Quaternius",
    archive_path: QUARANTINED_H06_ARCHIVE_PATH,
    archive_sha256: QUARANTINED_H06_SHA256,
    archive_size_bytes: 20231284,
    archive_file_count: 127,
    zip_crc: "PASS",
    gltf_dependency_closure: "PASS",
    publisher_page: "https://quaternius.com/packs/cutemonsters.html",
    publisher_page_sha256: "d3457924ed35694068d8d5c9594c26781ab9f7b3de89f6b46ecbe0af3b667834",
    acquisition_workflow_run_id: 44736035009,
    historical_acquisition_commit: "b0c597fb13ff671d43e437a9c84a10dbfb723bec",
    admission_status: "LICENSE_REVIEW_REQUIRED",
    public_source_redistribution: "BLOCKED",
    production_admission: "NOT_ADMITTED"
  }
];
const quarantineRegistry = () => ({
  schema: "iom-vendor-source-quarantine:v1",
  status: "LICENSE_REVIEW_REQUIRED",
  public_source_redistribution: "BLOCKED",
  production_admission: "NOT_ADMITTED",
  current_tree_disposition: "ARCHIVES_REMOVED_FROM_CURRENT_BRANCH_TREE",
  historical_git_blob_disposition: "NOT_PURGED; earlier public commits in this PR history still contain these archive blobs; no history rewrite was performed.",
  license_scope_summary: {
    legacy_pack_pages: "The named Ultimate Monsters and Cute Animated Monsters pages display CC0 and commercial-use language.",
    qal_v1_url: "https://quaternius.com/license.html",
    qal_v1_updated: "2026-08-28",
    qal_v1_section_3a: "Prohibits standalone redistribution of the Assets as assets or packs.",
    qal_v1_section_7: "The version in effect when the assets were obtained governs; updates are for future releases and are not retroactive.",
    unresolved_question: "No dated acquisition-time licence receipt or written vendor confirmation establishes whether these exact archives, acquired after the QAL v1.0 update, remain covered by the older pack-specific CC0 grants."
  },
  sources: QUARANTINED_SOURCES.map((source) => ({ ...source }))
});
test("quarantined vendor archives retain hash evidence but stay outside the active lock and tree", () => {
  const files = { ...good, [QUARANTINE_PATH]: JSON.stringify(quarantineRegistry()) };
  assert.deepEqual(validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] })), []);
});

test("quarantined vendor archives cannot be reintroduced into the source tree or active lock", () => {
  const files = {
    ...good,
    [QUARANTINE_PATH]: JSON.stringify(quarantineRegistry()),
    [QUARANTINED_ARCHIVE_PATH]: "archive"
  };
  const treeErrors = validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] })).join("\n");
  assert.match(treeErrors, /quarantined source must not be present in repository tree/);

  const activeEntry = entry({
    path: QUARANTINED_ARCHIVE_PATH,
    sha256: sha("archive"),
    source_revision: sha("archive")
  });
  const lockErrors = validateVendorLock(repo(files, { version: "1.0.0", assets: [entry(), activeEntry] })).join("\n");
  assert.match(lockErrors, /quarantined source must not appear in vendor.lock.json/);
});

test("quarantine archive path traversal cannot bypass active-lock protection", () => {
  const registry = quarantineRegistry();
  registry.sources[0].archive_path = "assets-src/../docs/vendor/not-a-real-archive.zip";
  const activeArchive = entry({
    path: QUARANTINED_ARCHIVE_PATH,
    sha256: sha("archive"),
    source_revision: sha("archive"),
    vendor: "Quaternius",
    source_url: "https://quaternius.com/packs/ultimatemonsters.html",
    pack_id: "quaternius:H05-ultimate-monsters"
  });
  const files = {
    ...good,
    [QUARANTINE_PATH]: JSON.stringify(registry),
    [QUARANTINED_ARCHIVE_PATH]: "archive"
  };
  const errors = validateVendorLock(
    repo(files, { version: "1.0.0", assets: [entry(), activeArchive] })
  ).join("\n");
  assert.match(errors, /archive_path must be a safe assets-src-relative path/);
});

test("the quarantine registry pins both exact H05/H06 source archives and licence-scope evidence", () => {
  const mutations = [
    (registry) => { registry.sources.pop(); },
    (registry) => { registry.sources[0].archive_sha256 = sha("replacement archive"); },
    (registry) => { registry.sources[1].archive_path = "assets-src/quaternius/H06/repacked.zip"; },
    (registry) => { registry.sources[0].publisher_page_sha256 = sha("replacement publisher page"); },
    (registry) => { registry.license_scope_summary.qal_v1_updated = "2026-01-01"; },
    (registry) => { registry.sources[1] = { ...registry.sources[0] }; }
  ];

  for (const mutate of mutations) {
    const registry = quarantineRegistry();
    mutate(registry);
    const files = { ...good, [QUARANTINE_PATH]: JSON.stringify(registry) };
    const errors = validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] })).join("\n");
    assert.ok(
      errors.includes("invalid or incomplete quarantine registry") ||
      errors.includes("exact H05/H06 source identity"),
      errors
    );
  }
});

test("Quaternius H05/H06 extracted assets cannot enter the active lock while rights remain unresolved", () => {
  for (const packId of [
    "quaternius:H05-ultimate-monsters",
    "quaternius:H06-cute-animated-monsters"
  ]) {
    const activeAsset = entry({ vendor: "Quaternius", pack_id: packId });
    const files = { ...good, [QUARANTINE_PATH]: JSON.stringify(quarantineRegistry()) };
    const errors = validateVendorLock(
      repo(files, { version: "1.0.0", assets: [activeAsset] })
    ).join("\n");
    assert.ok(errors.includes("Quaternius source is not admitted and must remain outside vendor.lock.json"), errors);
  }
});

test("H05/H06 archive paths cannot be reintroduced by relabelling the vendor", () => {
  for (const path of [QUARANTINED_ARCHIVE_PATH, QUARANTINED_H06_ARCHIVE_PATH]) {
    const bytes = "archive";
    const digest = sha(bytes);
    const activeAsset = entry({
      path,
      sha256: digest,
      source_revision: digest,
      vendor: "Another Vendor",
      pack_id: "another-vendor:archive",
      source_url: "https://example.com/source.zip"
    });
    const files = {
      ...good,
      [QUARANTINE_PATH]: JSON.stringify(quarantineRegistry()),
      [path]: bytes
    };
    const errors = validateVendorLock(
      repo(files, { version: "1.0.0", assets: [activeAsset] })
    ).join("\n");
    assert.ok(errors.includes("Quaternius source is not admitted and must remain outside vendor.lock.json"), errors);
  }
});

test("a malformed quarantine registry fails closed", () => {
  const files = { ...good, [QUARANTINE_PATH]: JSON.stringify({ schema: "wrong", sources: [] }) };
  assert.match(validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] })).join("\n"), /invalid or incomplete quarantine registry/);
});

test("top-level quarantine state cannot authorize source redistribution or production admission", () => {
  for (const [key, value] of [
    ["public_source_redistribution", "ALLOWED"],
    ["production_admission", "ADMITTED"]
  ]) {
    const registry = quarantineRegistry();
    registry[key] = value;
    const files = { ...good, [QUARANTINE_PATH]: JSON.stringify(registry) };
    const errors = validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] })).join("\n");
    assert.match(errors, /invalid or incomplete quarantine registry/);
  }
});

test("a missing quarantine registry fails closed", () => {
  const root = repo(good, { version: "1.0.0", assets: [entry()] }, undefined, { omitQuarantineRegistry: true });
  assert.match(validateVendorLock(root).join("\n"), /required quarantine registry is missing/);
});

test("a symlinked quarantine registry path fails closed", () => {
  const outside = mkdtempSync(join(tmpdir(), "outside-quarantine-"));
  writeFileSync(join(outside, "quaternius-h05-h06.json"), JSON.stringify(quarantineRegistry()));
  const root = repo(good, { version: "1.0.0", assets: [entry()] }, undefined, { omitQuarantineRegistry: true });
  mkdirSync(join(root, "docs/vendor"), { recursive: true });
  symlinkSync(outside, join(root, "docs/vendor/quarantine"), "dir");
  assert.match(validateVendorLock(root).join("\n"), /safe repository-relative file without symlinked components/);
});
 
test("a symlinked vendor.lock.json fails closed", () => {
  const root = repo(good, { version: "1.0.0", assets: [entry()] });
  const outside = mkdtempSync(join(tmpdir(), "outside-vendor-lock-"));
  const outsideLock = join(outside, "vendor.lock.json");
  writeFileSync(outsideLock, JSON.stringify({ version: "1.0.0", assets: [entry()] }));
  unlinkSync(join(root, "vendor.lock.json"));
  symlinkSync(outsideLock, join(root, "vendor.lock.json"));
  const errors = validateVendorLock(root).join("\n");
  assert.ok(errors.includes("vendor.lock.json: must be a safe repository-relative file without symlinked components"), errors);
});

test("a symlinked external-assets manifest fails closed", () => {
  const manifest = { schema_version: 1, assets: [] };
  const root = repo(good, { version: "1.0.0", assets: [entry()] }, manifest);
  const outside = mkdtempSync(join(tmpdir(), "outside-external-manifest-"));
  const outsideManifest = join(outside, "external-assets.json");
  writeFileSync(outsideManifest, JSON.stringify(manifest));
  const manifestPath = join(root, "client-godot/assets/external-assets.json");
  unlinkSync(manifestPath);
  symlinkSync(outsideManifest, manifestPath);
  const errors = validateVendorLock(root).join("\n");
  assert.ok(errors.includes("external-assets.json: must be a safe repository-relative file without symlinked components"), errors);
});

test("a symlinked external asset root fails closed", () => {
  const manifest = { schema_version: 1, assets: [] };
  const root = repo(good, { version: "1.0.0", assets: [entry()] }, manifest);
  const outside = mkdtempSync(join(tmpdir(), "outside-external-assets-"));
  symlinkSync(outside, join(root, "client-godot/assets/external"), "dir");
  const errors = validateVendorLock(root).join("\n");
  assert.ok(errors.includes("client-godot/assets/external: must be a safe repository-relative directory without symlinked components"), errors);
});

test("an empty lock is rejected because it admits no source dependency", () => {
  const errors = validateVendorLock(repo()).join("\n");
  assert.match(errors, /assets must contain at least one verified dependency/);
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
test("a missing, whitespace-only, or absent license_path is rejected", () => {
  const { license_path, ...rest } = entry();
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [rest] })).join("\n"), /license_path/);
  for (const value of [" ", "\t", "\n", " \t\n"]) {
    assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ license_path: value })] })).join("\n"), /license_path is required/);
  }
  const noFile = { "vendor/kit/palm.glb": "palm" };
  assert.match(validateVendorLock(repo(noFile, { version: "1.0.0", assets: [entry()] })).join("\n"), /license file/i);
});
test("a missing or malformed license_sha256 is rejected", () => {
  const { license_sha256, ...rest } = entry();
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [rest] })).join("\n"), /license_sha256/);
  for (const value of ["", " ", "A".repeat(64), "a".repeat(63)]) {
    assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ license_sha256: value })] })).join("\n"), /license_sha256/);
  }
});
test("a modified license file fails its independently pinned SHA-256", () => {
  const files = { ...good, "vendor/kit/LICENSE.txt": "changed license text" };
  const errors = validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] })).join("\n");
  assert.match(errors, /license sha256 mismatch/);
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

test("vendor and source_revision are required for every lock entry", () => {
  const withoutVendor = entry();
  delete withoutVendor.vendor;
  const withoutRevision = entry();
  delete withoutRevision.source_revision;
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [withoutVendor] })).join("\n"), /vendor must be a non-empty string/);
  assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [withoutRevision] })).join("\n"), /exactly one of source_revision or source_identity/);
});

test("pack_id must be non-empty when provided", () => {
  for (const value of ["", " ", "\t", "\n", " \t\n"]) {
    assert.match(validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ pack_id: value })] })).join("\n"), /pack_id must be a non-empty string/);
  }
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
  const files = { ...good, "client-godot/assets/external/polyhaven/x/x.glb": "x" };
  const manifest = { schema_version: 1, assets: [{ path: "polyhaven/x/x.glb", sha256: sha("x") }] };
  const lock = { version: "1.0.0", assets: [entry()] };
  assert.deepEqual(validateVendorLock(repo(files, lock, manifest)), []);
});

test("Godot import sidecars under external assets are ignored after import", () => {
  const ext = "client-godot/assets/external/polyhaven/x/x.glb";
  const files = {
    ...good,
    [ext]: "x",
    [`${ext}.import`]: "Godot import metadata",
    [`${ext}.uid`]: "Godot UID metadata"
  };
  const manifest = { schema_version: 1, assets: [{ path: "polyhaven/x/x.glb", sha256: sha("x") }] };
  assert.deepEqual(validateVendorLock(repo(files, { version: "1.0.0", assets: [entry()] }, manifest)), []);
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


const SOURCE_REVISION = "1234567890abcdef1234567890abcdef12345678";
function sourceEntry(overrides = {}) {
  return entry({
    path: "assets-src/H01/palm.glb", vendor: "Kenney",
    source_revision: SOURCE_REVISION, ...overrides
  });
}
test("incoming assets-src import with verified vendor and revision passes", () => {
  const files = { "assets-src/H01/palm.glb": "palm", "vendor/kit/LICENSE.txt": "CC0" };
  assert.deepEqual(validateVendorLock(repo(files, { version: "1.0.0", assets: [sourceEntry()] })), []);
});

test("a 64-character source revision for a source archive must match the exact archive SHA-256", () => {
  const path = "assets-src/H01/kenney-pirate-kit.zip";
  const bytes = "archive bytes";
  const digest = sha(bytes);
  const files = { [path]: bytes, "vendor/kit/LICENSE.txt": "CC0" };
  const base = {
    path,
    sha256: digest,
    source_url: "https://kenney.nl/media/pages/assets/pirate-kit/archive.zip",
    pack_id: "kenney:H01-pirate-kit-2.1"
  };
  const mismatched = sourceEntry({ ...base, source_revision: sha("different archive") });
  const errors = validateVendorLock(repo(files, { version: "1.0.0", assets: [mismatched] })).join("\n");
  assert.match(errors, /archive source_revision must equal sha256/);

  const matching = sourceEntry({ ...base, source_revision: digest });
  assert.deepEqual(validateVendorLock(repo(files, { version: "1.0.0", assets: [matching] })), []);
});
test("incoming assets-src unlisted binary is rejected with its real SHA-256", () => {
  const errs = validateVendorLock(repo({ "assets-src/H01/palm.glb": "palm" })).join("\n");
  assert.match(errs, /unlisted import/);
  assert.ok(errs.includes(sha("palm")));
});
test("incoming assets-src altered binary is rejected with both hashes", () => {
  const files = { "assets-src/H01/palm.glb": "changed", "vendor/kit/LICENSE.txt": "CC0" };
  const errs = validateVendorLock(repo(files, { version: "1.0.0", assets: [sourceEntry()] })).join("\n");
  assert.match(errs, /sha256 mismatch/);
  assert.ok(errs.includes(sha("palm")) && errs.includes(sha("changed")));
});
test("incoming assets-src cannot omit exact source revision or vendor identity", () => {
  const files = { "assets-src/H01/palm.glb": "palm", "vendor/kit/LICENSE.txt": "CC0" };
  for (const override of [{ source_revision: "latest" }, { vendor: "" }]) {
    const errs = validateVendorLock(repo(files, { version: "1.0.0", assets: [sourceEntry(override)] })).join("\n");
    assert.match(errs, /source_revision|vendor provenance/);
  }
});
test("incoming assets-src symlinks are rejected", () => {
  const root = repo({});
  mkdirSync(join(root, "assets-src"), { recursive: true });
  symlinkSync("/etc/passwd", join(root, "assets-src", "escape.bin"));
  assert.match(validateVendorLock(root).join("\n"), /symlink rejected/);
});

test("a deleted locked source file fails closed", () => {
  const root = repo({ "vendor/kit/LICENSE.txt": "CC0" }, { version: "1.0.0", assets: [sourceEntry()] });
  assert.match(validateVendorLock(root).join("\\n"), /locked import missing/);
});
test("a missing assets-src directory fails when source imports are locked", () => {
  const root = repo({ "vendor/kit/LICENSE.txt": "CC0" }, { version: "1.0.0", assets: [sourceEntry()] });
  assert.match(validateVendorLock(root).join("\\n"), /locked import missing/);
});
test("a dangling assets-src root symlink is rejected", () => {
  const root = repo({ "vendor/kit/LICENSE.txt": "CC0" }, { version: "1.0.0", assets: [sourceEntry()] });
  symlinkSync(join(root, "missing-source-archive"), join(root, "assets-src"), "dir");
  assert.match(validateVendorLock(root).join("\\n"), /assets-src: must be a real directory/);
});
test("a stale source lock entry fails despite another valid import", () => {
  const files = { "assets-src/H01/palm.glb": "palm", "vendor/kit/LICENSE.txt": "CC0" };
  const stale = sourceEntry({ path: "assets-src/H01/deleted.glb" });
  const errs = validateVendorLock(repo(files, { version: "1.0.0", assets: [sourceEntry(), stale] })).join("\\n");
  assert.ok(errs.includes("locked import missing assets-src/H01/deleted.glb"));
});
test("all present locked source imports continue to pass", () => {
  const files = { "assets-src/H01/palm.glb": "palm", "vendor/kit/LICENSE.txt": "CC0" };
  assert.deepEqual(validateVendorLock(repo(files, { version: "1.0.0", assets: [sourceEntry()] })), []);
});


test("every committed vendor entry pins the exact bytes of its licence file", () => {
  const lock = JSON.parse(readFileSync(new URL("../vendor.lock.json", import.meta.url), "utf8"));
  for (const asset of lock.assets) {
    const licenseBytes = readFileSync(new URL(`../${asset.license_path}`, import.meta.url));
    const actual = createHash("sha256").update(licenseBytes).digest("hex");
    assert.equal(asset.license_sha256, actual, asset.path);
  }
});

test("committed Corsairs naval-math sources pin the immutable upstream revision and MIT notice", () => {
  const lock = JSON.parse(readFileSync(new URL("../vendor.lock.json", import.meta.url), "utf8"));
  const entries = lock.assets.filter((asset) => asset.pack_id === "corsairs:naval-math");
  assert.equal(entries.length, 7);
  assert.ok(entries.every((asset) =>
    asset.source_revision === "22467f438be328924e6abf0578e970943eb0fd88" &&
    asset.license === "MIT" &&
    asset.license_path === "LICENSES/MIT-Corsairs.txt"
  ));
  assert.deepEqual(
    entries.map((asset) => asset.path).sort(),
    [
      "assets-src/corsairs/core/ammo.gd",
      "assets-src/corsairs/core/boarding.gd",
      "assets-src/corsairs/core/combat.gd",
      "assets-src/corsairs/core/sailing.gd",
      "assets-src/corsairs/core/ship.gd",
      "assets-src/corsairs/core/ship_types.gd",
      "LICENSES/MIT-Corsairs.txt"
    ].sort()
  );
  const license = readFileSync(new URL("../LICENSES/MIT-Corsairs.txt", import.meta.url), "utf8");
  assert.ok(license.includes("Copyright (c) 2026 Elkhan Isayev"));
});

const vendorLockEntrySchema = JSON.parse(readFileSync(new URL("../schemas/vendor-lock.schema.json", import.meta.url), "utf8"))
  .properties.assets.items.properties;
const vendorSchema = vendorLockEntrySchema.vendor;
test("vendor JSON Schema rejects whitespace-only provenance values just like runtime validation", () => {
  assert.equal(vendorSchema.minLength, 1);
  assert.equal(vendorSchema.pattern, "\\S");
  const nonWhitespace = new RegExp(vendorSchema.pattern);
  for (const value of [" ", "\t", "\n", " \t\n"]) {
    assert.equal(nonWhitespace.test(value), false, JSON.stringify(value));
    const errors = validateVendorLock(repo(good, { version: "1.0.0", assets: [entry({ vendor: value })] })).join("\\n");
    assert.match(errors, /vendor must be a non-empty string/);
  }
  assert.equal(nonWhitespace.test("Kenney"), true);
  assert.equal(nonWhitespace.test("Poly Haven"), true);
});


test("vendor JSON Schema constrains asset and licence paths to repository-relative lexical paths", () => {
  assert.equal(vendorLockEntrySchema.path.pattern, "^(?=.*\\S)(?!/)(?![A-Za-z]:)(?!.*(?:^|/)\\.\\.?(/|$))(?!.*\\\\).+$");
  assert.equal(vendorLockEntrySchema.license_path.pattern, vendorLockEntrySchema.path.pattern);
  const safe = new RegExp(vendorLockEntrySchema.path.pattern);
  for (const value of ["../outside.glb", "/tmp/file", "C:\\tmp\\file", "assets/../outside.glb", "assets/./file.glb", "\\\\server\\share", " \t\n"]) {
    assert.equal(safe.test(value), false, JSON.stringify(value));
  }
  for (const value of ["assets-src/corsairs/core/ammo.gd", "client-godot/assets/external/polyhaven/model.glb"]) {
    assert.equal(safe.test(value), true, value);
  }
});

test("vendor JSON Schema rejects whitespace-only license paths and pack IDs", () => {
  assert.equal(vendorLockEntrySchema.pack_id.pattern, "\\S");
  for (const field of ["license_path", "pack_id"]) {
    const pattern = new RegExp(vendorLockEntrySchema[field].pattern);
    for (const value of [" ", "\t", "\n", " \t\n"]) {
      assert.equal(pattern.test(value), false, `${field}: ${JSON.stringify(value)}`);
    }
    assert.equal(pattern.test(field === "license_path" ? "LICENSES/MIT-Corsairs.txt" : "kenney:pirate-pack"), true);
  }
});

test("vendor JSON Schema requires exactly one immutable source revision or per-file identity", () => {
  const schema = JSON.parse(readFileSync(new URL("../schemas/vendor-lock.schema.json", import.meta.url), "utf8"));
  const item = schema.properties.assets.items;
  assert.ok(item.required.includes("vendor"));
  assert.ok(item.oneOf.some((choice) => choice.required?.includes("source_revision")));
  assert.ok(item.oneOf.some((choice) => choice.required?.includes("source_identity")));
  assert.equal(item.properties.source_identity.pattern, "^polyhaven-file:[a-z0-9_-]+/[A-Za-z0-9._/-]+@sha256:[0-9a-f]{64}$");
  assert.equal(item.then.properties.vendor.const, "Poly Haven");
});

test("Poly Haven per-file identity must match its official asset page, pack, path and SHA-256", () => {
  const path = "client-godot/assets/external/polyhaven/coast_rocks_05/textures/coast_rocks_05_diff_1k.jpg";
  const bytes = "texture bytes";
  const digest = sha(bytes);
  const entry = {
    path,
    sha256: digest,
    license: "CC0-1.0",
    license_path: "vendor/kit/LICENSE.txt",
    license_sha256: sha("CC0"),
    source_url: "https://polyhaven.com/a/coast_rocks_05",
    vendor: "Poly Haven",
    pack_id: "polyhaven:coast_rocks_05",
    source_identity: `polyhaven-file:coast_rocks_05/textures/coast_rocks_05_diff_1k.jpg@sha256:${digest}`
  };
  const files = { [path]: bytes, "vendor/kit/LICENSE.txt": "CC0" };
  assert.deepEqual(validateVendorLock(repo(files, { version: "1.0.0", assets: [entry] })), []);
  for (const override of [
    { source_url: "https://polyhaven.com/a/other_asset" },
    { pack_id: "polyhaven:other_asset" },
    { source_identity: entry.source_identity.replace("coast_rocks_05", "other_asset") },
    { source_revision: "a".repeat(40) }
  ]) {
    const errors = validateVendorLock(repo(files, { version: "1.0.0", assets: [{ ...entry, ...override }] })).join("\n");
    assert.match(errors, /source_identity|exactly one/);
  }
});

test("Poly Haven per-file identity cannot traverse outside its slug directory", () => {
  const path = "client-godot/assets/external/polyhaven/palm/../../other/x.glb";
  const bytes = "x";
  const digest = sha(bytes);
  const asset = {
    path,
    sha256: digest,
    license: "CC0-1.0",
    license_path: "vendor/kit/LICENSE.txt",
    license_sha256: sha("CC0"),
    source_url: "https://polyhaven.com/a/palm",
    vendor: "Poly Haven",
    pack_id: "polyhaven:palm",
    source_identity: `polyhaven-file:palm/../../other/x.glb@sha256:${digest}`
  };
  const files = {
    "client-godot/assets/external/other/x.glb": bytes,
    "vendor/kit/LICENSE.txt": "CC0"
  };
  const errors = validateVendorLock(repo(files, { version: "1.0.0", assets: [asset] })).join("\n");
  assert.match(errors, /Poly Haven asset path must stay inside its slug directory/);
});

test("the committed Poly Haven lock keeps all 64 exact per-file source identities executable", () => {
  const lock = JSON.parse(readFileSync(new URL("../vendor.lock.json", import.meta.url), "utf8"));
  const entries = lock.assets.filter((asset) => asset.vendor === "Poly Haven");
  assert.equal(entries.length, 64);
  for (const asset of entries) {
    assert.equal(asset.source_revision, undefined, asset.path);
    const prefix = "client-godot/assets/external/polyhaven/";
    assert.ok(asset.path.startsWith(prefix), asset.path);
    const parts = asset.path.slice(prefix.length).split("/");
    const slug = parts.shift();
    const relativeFile = parts.join("/");
    assert.ok(parts.length > 0 && parts.every((part) => part !== "" && part !== "." && part !== ".."), asset.path);
    assert.equal(asset.path.includes("\\"), false, asset.path);
    assert.equal(asset.source_url, `https://polyhaven.com/a/${slug}`, asset.path);
    assert.equal(asset.pack_id, `polyhaven:${slug}`, asset.path);
    assert.equal(asset.source_identity, `polyhaven-file:${slug}/${relativeFile}@sha256:${asset.sha256}`, asset.path);
  }
});
