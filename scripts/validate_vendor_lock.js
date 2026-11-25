#!/usr/bin/env node
"use strict";
// Fail-closed check of vendor.lock.json (IOM-00). A third-party asset may only be pinned with a SHA-256 that matches
// the file on disk, an allowlisted SPDX licence and a licence file that exists in the repository. This complements,
// and does not replace, scripts/validate_godot_assets.py + client-godot/assets/external-assets.json (the rich
// provenance registry for client-godot/assets/external): entries present in both must agree on the digest, and no
// file under client-godot/assets/external may exist in neither registry.

const { createHash } = require("node:crypto");
const { existsSync, lstatSync, readdirSync, readFileSync } = require("node:fs");
const { join, relative, resolve, sep, isAbsolute, extname } = require("node:path");
const { isIP } = require("node:net");

const LICENSES = new Set(["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "MIT", "Apache-2.0", "OFL-1.1"]); // same as validate_godot_assets.py
const HASH = /^[0-9a-f]{64}$/;
const TOP_KEYS = new Set(["$schema", "version", "assets"]);
const ENTRY_KEYS = new Set(["path", "sha256", "license", "license_path", "license_sha256", "source_url", "vendor", "source_revision", "source_identity", "pack_id"]);
const EXTERNAL_DIR = "client-godot/assets/external";
const QUARANTINE_REGISTRY_PATH = "docs/vendor/quarantine/quaternius-h05-h06.json";
const QUARANTINE_MEMBER_HASH_MANIFEST_PATH = "docs/vendor/quarantine/quaternius-h05-h06-member-hashes.bin";
const QUARANTINE_MEMBER_HASH_MANIFEST = Object.freeze({
  path: QUARANTINE_MEMBER_HASH_MANIFEST_PATH,
  sha256: "fc4f7d77edf19710a817f0b9d7e9076dfa9b97678d283ef2af59ec79c9ddb07f",
  format: "IOMQH5H6-v1",
  h05_unique_sha256_count: 244,
  h06_unique_sha256_count: 127,
  total_unique_sha256_count: 371
});
const QUARANTINED_MEMBER_HASH_COUNTS = Object.freeze({ H05: 244, H06: 127 });
const QUARANTINED_QUATERNIUS_SOURCES = Object.freeze([
  Object.freeze({
    harvest_id: "H05",
    pack_id: "quaternius:H05-ultimate-monsters",
    vendor: "Quaternius",
    archive_path: "assets-src/quaternius/H05/ultimate-monsters.zip",
    archive_sha256: "f444a35e70895f822f3687eb47e608801baf98f2ae86c7ed24b6c017842f006d",
    archive_size_bytes: 46576830,
    archive_file_count: 260,
    unique_member_sha256_count: 244,
    zip_crc: "PASS",
    gltf_dependency_closure: "PASS",
    publisher_page: "https://quaternius.com/packs/ultimatemonsters.html",
    publisher_page_sha256: "5adff0c0a2d5677f59b9810cf7e40d13a72234dafcd1b50968dbdb149c9cb563",
    acquisition_workflow_run_id: 44736035009,
    historical_acquisition_commit: "b0c597fb13ff671d43e437a9c84a10dbfb723bec",
    admission_status: "ADMITTED_CC0",
    public_source_redistribution: "ALLOWED_UNDER_CC0",
    production_admission: "ADMITTED"
  }),
  Object.freeze({
    harvest_id: "H06",
    pack_id: "quaternius:H06-cute-animated-monsters",
    vendor: "Quaternius",
    archive_path: "assets-src/quaternius/H06/cute-animated-monsters.zip",
    archive_sha256: "93bb9e0cdd678ddd4367402a38f931d57fd52280b0c50f5075212a216ae673a3",
    archive_size_bytes: 20231284,
    archive_file_count: 127,
    unique_member_sha256_count: 127,
    zip_crc: "PASS",
    gltf_dependency_closure: "PASS",
    publisher_page: "https://quaternius.com/packs/cutemonsters.html",
    publisher_page_sha256: "d3457924ed35694068d8d5c9594c26781ab9f7b3de89f6b46ecbe0af3b667834",
    acquisition_workflow_run_id: 44736035009,
    historical_acquisition_commit: "b0c597fb13ff671d43e437a9c84a10dbfb723bec",
    admission_status: "ADMITTED_CC0",
    public_source_redistribution: "ALLOWED_UNDER_CC0",
    production_admission: "ADMITTED"
  })
]);
const QUARANTINED_QUATERNIUS_PACK_IDS = new Set(
  QUARANTINED_QUATERNIUS_SOURCES.map((source) => source.pack_id.toLowerCase())
);
const QUARANTINED_QUATERNIUS_ARCHIVE_SHA256S = new Set(
  QUARANTINED_QUATERNIUS_SOURCES.map((source) => source.archive_sha256)
);
const QUARANTINED_QUATERNIUS_PATH_PREFIXES = Object.freeze([
  "assets-src/quaternius/h05/",
  "assets-src/quaternius/h06/",
  "client-godot/assets/external/quaternius/"
]);
const GODOT_SIDECARS = new Set([".import", ".uid"]);
const { validateAssetSourceTree } = require("./validate_asset_src.js");

function sha256File(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function normalizeRepositoryRelativePath(value, separator = sep) {
  return value.split(separator).join("/");
}

function loadQuarantinedMemberHashes(root, errors) {
  const file = canonicalRepoPath(root, QUARANTINE_MEMBER_HASH_MANIFEST_PATH);
  if (!file) {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": must be a safe repository-relative file without symlinked components");
    return null;
  }
  let stat;
  try {
    stat = lstatSync(file);
  } catch (error) {
    if (error.code === "ENOENT") errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": required member SHA-256 manifest is missing");
    else errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": cannot inspect (" + error.message + ")");
    return null;
  }
  if (!stat.isFile()) {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": member SHA-256 manifest must be a regular file");
    return null;
  }

  let bytes;
  try {
    bytes = readFileSync(file);
  } catch (error) {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": cannot read (" + error.message + ")");
    return null;
  }
  if (createHash("sha256").update(bytes).digest("hex") !== QUARANTINE_MEMBER_HASH_MANIFEST.sha256) {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": member SHA-256 manifest digest mismatch");
    return null;
  }
  if (bytes.length < 16 || bytes.subarray(0, 8).toString("ascii") !== "IOMQH5H6") {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": invalid member SHA-256 manifest header");
    return null;
  }

  const h05Count = bytes.readUInt32BE(8);
  const h06Count = bytes.readUInt32BE(12);
  const expectedTotal = QUARANTINED_MEMBER_HASH_COUNTS.H05 + QUARANTINED_MEMBER_HASH_COUNTS.H06;
  if (h05Count !== QUARANTINED_MEMBER_HASH_COUNTS.H05 ||
      h06Count !== QUARANTINED_MEMBER_HASH_COUNTS.H06 ||
      bytes.length !== 16 + (h05Count + h06Count) * 32) {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": invalid member SHA-256 manifest counts or length");
    return null;
  }

  const hashes = new Set();
  let offset = 16;
  for (const count of [h05Count, h06Count]) {
    let previous = "";
    for (let index = 0; index < count; index++) {
      const hash = bytes.subarray(offset, offset + 32).toString("hex");
      offset += 32;
      if (!HASH.test(hash) || hash <= previous || hashes.has(hash)) {
        errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": member SHA-256 digests must be valid, unique and sorted within each source pack");
        return null;
      }
      previous = hash;
      hashes.add(hash);
    }
  }
  if (hashes.size !== expectedTotal) {
    errors.push(QUARANTINE_MEMBER_HASH_MANIFEST_PATH + ": member SHA-256 manifest does not contain the exact expected unique digest count");
    return null;
  }
  return hashes;
}

/**
 * Resolve a repo-relative path; returns null when it is absolute, empty, escapes the repository, or when any existing
 * component below the repository root is a symlink (a symlinked parent could point outside the tree while the
 * lexical path still looks contained).
 */
function inside(root, p) {
  if (typeof p !== "string" || p.trim() === "" || isAbsolute(p)) return null;
  const abs = resolve(root, p);
  if (!(abs === root || abs.startsWith(root + sep))) return null;
  let current = root;
  for (const part of relative(root, abs).split(sep).filter(Boolean)) {
    current = join(current, part);
    let st;
    try {
      st = lstatSync(current);
    } catch {
      break; // not present yet: the caller reports a missing file
    }
    if (st.isSymbolicLink()) return null;
  }
  return abs;
}

function canonicalRepoPath(root, p) {
  if (typeof p !== "string" || p.includes("\\")) return null;
  const abs = inside(root, p);
  if (!abs) return null;
  const canonical = relative(root, abs).split(sep).join("/");
  return canonical === p ? abs : null;
}

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = lstatSync(full);
    if (st.isSymbolicLink()) out.push({ full, symlink: true });
    else if (st.isDirectory()) walk(full, out);
    else out.push({ full, symlink: false });
  }
  return out;
}

const READ_FAILED = Symbol("read-failed");

function readJson(file, errors, label) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    errors.push(`${label}: cannot read or parse (${error.message})`);
    return READ_FAILED;
  }
}

const isPlainObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const QUATERNIUS_HOSTS = Object.freeze([
  "quaternius.com",
  "quaternius.itch.io"
]);

function isValidHostname(hostname) {
  const normalized = hostname.toLowerCase().replace(/\.$/, "");
  if (!normalized || normalized.length > 253) return false;
  const unwrapped = normalized.startsWith("[") && normalized.endsWith("]")
    ? normalized.slice(1, -1)
    : normalized;
  if (isIP(unwrapped) !== 0) return true;
  return normalized.split(".").every((label) =>
    label.length > 0 && label.length <= 63 &&
    /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label)
  );
}

function parseHttpsUrl(value) {
  if (typeof value !== "string" || value.trim() !== value || /[\u0000-\u0020]/.test(value)) return null;
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "https:" || !parsed.hostname ||
        parsed.username !== "" || parsed.password !== "" ||
        !isValidHostname(parsed.hostname)) return null;
    return parsed;
  } catch {
    return null;
  }
}

function isQuaterniusSourceUrl(value) {
  const parsed = value instanceof URL ? value : parseHttpsUrl(value);
  if (!parsed) return false;
  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, "");
  return QUATERNIUS_HOSTS.some((host) =>
    hostname === host || hostname.endsWith("." + host)
  );
}

function referencesQuarantinedQuaterniusSourceDigest(record, memberHashes) {
  if (!isPlainObject(record)) return false;
  return ["sha256", "source_revision", "source_identity", "archive_sha256"].some((field) => {
    const value = record[field];
    if (typeof value !== "string") return false;
    const hashes = value.toLowerCase().match(/[0-9a-f]{64}/g) ?? [];
    return hashes.some((hash) => QUARANTINED_QUATERNIUS_ARCHIVE_SHA256S.has(hash) || memberHashes.has(hash));
  });
}


function validateQuarantinedSources(root, lock, memberHashes) {
  const errors = [];
  const file = canonicalRepoPath(root, QUARANTINE_REGISTRY_PATH);
  if (!file) {
    return [QUARANTINE_REGISTRY_PATH + ": must be a safe repository-relative file without symlinked components"];
  }
  if (!existsSync(file)) {
    return [QUARANTINE_REGISTRY_PATH + ": required quarantine registry is missing"];
  }
  let fileStat;
  try {
    fileStat = lstatSync(file);
  } catch (error) {
    return [QUARANTINE_REGISTRY_PATH + ": cannot inspect (" + error.message + ")"];
  }
  if (!fileStat.isFile()) {
    return [QUARANTINE_REGISTRY_PATH + ": quarantine registry must be a regular file"];
  }
  const registry = readJson(file, errors, QUARANTINE_REGISTRY_PATH);
  if (registry === READ_FAILED) return errors;
  if (!isPlainObject(registry)) {
    return [...errors, QUARANTINE_REGISTRY_PATH + ": invalid or incomplete quarantine registry"];
  }

  const licenseSummary = registry.license_scope_summary;
  if (registry.schema !== "iom-vendor-source-admission:v1" ||
      registry.status !== "SOURCE_ARCHIVES_ADMITTED" ||
      registry.public_source_redistribution !== "ALLOWED_UNDER_CC0" ||
      registry.production_admission !== "ADMITTED" ||
      registry.current_tree_disposition !== "ARCHIVES_PINNED_IN_ASSETS_SRC" ||
      typeof registry.historical_git_blob_disposition !== "string" ||
      !registry.historical_git_blob_disposition.startsWith("NOT_PURGED;") ||
      !isPlainObject(licenseSummary) ||
      !isPlainObject(registry.member_hash_manifest) ||
      Object.entries(QUARANTINE_MEMBER_HASH_MANIFEST).some(([key, value]) => registry.member_hash_manifest[key] !== value) ||
      licenseSummary.qal_v1_url !== "https://quaternius.com/license.html" ||
      licenseSummary.qal_v1_updated !== "2026-08-28" ||
      typeof licenseSummary.qal_v1_section_3a !== "string" ||
      !/standalone redistribution/i.test(licenseSummary.qal_v1_section_3a) ||
      typeof licenseSummary.qal_v1_section_7 !== "string" ||
      !/version in effect when.*obtained/i.test(licenseSummary.qal_v1_section_7) ||
      typeof licenseSummary.resolved_admission_note !== "string" ||
      !licenseSummary.resolved_admission_note.trim() ||
      !Array.isArray(registry.sources) ||
      registry.sources.length !== QUARANTINED_QUATERNIUS_SOURCES.length) {
    return [...errors, QUARANTINE_REGISTRY_PATH + ": invalid or incomplete quarantine registry"];
  }

  const expectedByHarvestId = new Map(
    QUARANTINED_QUATERNIUS_SOURCES.map((source) => [source.harvest_id, source])
  );
  const lockedPaths = new Set(lock.assets
    .filter(asset => isPlainObject(asset) && typeof asset.path === "string")
    .map(asset => asset.path));
  const seenPaths = new Set();
  const seenHarvestIds = new Set();

  for (const [index, source] of registry.sources.entries()) {
    const at = QUARANTINE_REGISTRY_PATH + " source " + index;
    if (!isPlainObject(source)) {
      errors.push(at + ": must be an object");
      continue;
    }

    const expected = expectedByHarvestId.get(source.harvest_id);
    if (!expected ||
        seenHarvestIds.has(source.harvest_id) ||
        Object.entries(expected).some(([key, value]) => source[key] !== value)) {
      errors.push(at + ": exact H05/H06 source identity, archive hash and admission state must match the verified quarantine record");
    }
    seenHarvestIds.add(source.harvest_id);

    const archivePath = source.archive_path;
    const abs = canonicalRepoPath(root, archivePath);
    const canonicalArchivePath = abs ? relative(root, abs).split(sep).join("/") : null;
    if (!abs ||
        typeof archivePath !== "string" ||
        canonicalArchivePath !== archivePath ||
        !canonicalArchivePath.startsWith("assets-src/")) {
      errors.push(at + ": archive_path must be a safe assets-src-relative path");
      continue;
    }
    if (seenPaths.has(archivePath)) errors.push(at + ": duplicate quarantined archive path " + archivePath);
    seenPaths.add(archivePath);
    if (typeof source.archive_sha256 !== "string" || !HASH.test(source.archive_sha256)) {
      errors.push(at + ": archive_sha256 must be 64 lowercase hex characters");
    }
    if (source.admission_status !== "ADMITTED_CC0" ||
        source.public_source_redistribution !== "ALLOWED_UNDER_CC0" ||
        source.production_admission !== "ADMITTED") {
      errors.push(at + ": admitted source must remain marked ADMITTED_CC0 / ALLOWED_UNDER_CC0 / ADMITTED");
    }
    if (existsSync(abs)) {
      const actual = sha256File(abs);
      if (actual !== source.archive_sha256) {
        errors.push(at + ": archive sha256 mismatch for " + archivePath + " (expected " + source.archive_sha256 + ", actual " + actual + ")");
      }
    }
  }

  for (const expected of QUARANTINED_QUATERNIUS_SOURCES) {
    if (!seenHarvestIds.has(expected.harvest_id)) {
      errors.push(QUARANTINE_REGISTRY_PATH + ": required quarantined source " + expected.harvest_id + " is missing");
    }
  }

  // Admitted CC0 H05/H06 sources may appear in the lock only with the pinned pack ids,
  // official publisher pages, CC0-1.0, and the exact archive or member digests.
  for (const asset of lock.assets) {
    if (!isPlainObject(asset)) continue;
    const vendor = typeof asset.vendor === "string" ? asset.vendor.trim().toLowerCase() : "";
    const packId = typeof asset.pack_id === "string" ? asset.pack_id.trim().toLowerCase() : "";
    const assetPath = typeof asset.path === "string"
      ? asset.path.replaceAll(String.fromCharCode(92), "/").toLowerCase()
      : "";
    const hasQuaterniusUrl = isQuaterniusSourceUrl(asset.source_url);
    const hasQuarantinedSourceDigest = referencesQuarantinedQuaterniusSourceDigest(asset, memberHashes);
    const isQuaterniusAsset = vendor === "quaternius" || hasQuaterniusUrl || hasQuarantinedSourceDigest ||
        QUARANTINED_QUATERNIUS_PACK_IDS.has(packId) ||
        QUARANTINED_QUATERNIUS_PATH_PREFIXES.some((prefix) => assetPath.startsWith(prefix)) ||
        assetPath.startsWith("licenses/cc0-1.0-quaternius-");
    if (!isQuaterniusAsset) continue;
    if (asset.license !== "CC0-1.0") {
      errors.push("Admitted Quaternius source must use CC0-1.0: " + String(asset.path));
    }
    if (!QUARANTINED_QUATERNIUS_PACK_IDS.has(packId)) {
      errors.push("Admitted Quaternius source must use a pinned H05/H06 pack_id: " + String(asset.path));
    }
    if (!hasQuaterniusUrl) {
      errors.push("Admitted Quaternius source_url must be an official quaternius.com page: " + String(asset.path));
    }
    if (!hasQuarantinedSourceDigest) {
      errors.push("Admitted Quaternius source must pin the exact H05/H06 archive or member SHA-256: " + String(asset.path));
    }
  }

  return errors;
}

function validateVendorLock(root = resolve(__dirname, "..")) {
  root = resolve(root);
  const errors = [];
  const quarantinedMemberHashes = loadQuarantinedMemberHashes(root, errors) ?? new Set();
  const lockFile = canonicalRepoPath(root, "vendor.lock.json");
  if (!lockFile) {
    return ["vendor.lock.json: must be a safe repository-relative file without symlinked components"];
  }
  let lockStat;
  try {
    lockStat = lstatSync(lockFile);
  } catch (error) {
    if (error.code === "ENOENT") return ["vendor.lock.json is missing"];
    return ["vendor.lock.json: cannot inspect (" + error.message + ")"];
  }
  if (!lockStat.isFile()) return ["vendor.lock.json: must be a regular file"];
  const lock = readJson(lockFile, errors, "vendor.lock.json");
  if (lock === READ_FAILED) return errors;
  if (!isPlainObject(lock)) return ["vendor.lock.json: top level must be an object"];
  for (const key of Object.keys(lock)) if (!TOP_KEYS.has(key)) errors.push(`vendor.lock.json: unknown key "${key}"`);
  if (typeof lock.version !== "string" || !lock.version) errors.push("vendor.lock.json: version must be a non-empty string");
  if (!Array.isArray(lock.assets)) return [...errors, "vendor.lock.json: assets must be an array"];
  if (lock.assets.length === 0) {
    errors.push("vendor.lock.json: assets must contain at least one verified dependency; an empty lock does not prove Prompt 001 source admission");
  }

  const manifestRelativePath = "client-godot/assets/external-assets.json";
  const manifestFile = canonicalRepoPath(root, manifestRelativePath);
  let manifest = null;
  if (!manifestFile) {
    errors.push("external-assets.json: must be a safe repository-relative file without symlinked components");
  } else {
    let manifestStat;
    try {
      manifestStat = lstatSync(manifestFile);
    } catch (error) {
      if (error.code !== "ENOENT") errors.push("external-assets.json: cannot inspect (" + error.message + ")");
    }
    if (manifestStat) {
      if (!manifestStat.isFile()) {
        errors.push("external-assets.json: must be a regular file");
      } else {
        manifest = readJson(manifestFile, errors, "external-assets.json");
        if (manifest !== READ_FAILED && !(isPlainObject(manifest) && Array.isArray(manifest.assets))) {
          errors.push("external-assets.json: top level must be an object with an assets array");
        }
      }
    }
  }
  const manifestByRepoPath = new Map();
  for (const [index, item] of (isPlainObject(manifest) && Array.isArray(manifest.assets) ? manifest.assets : []).entries()) {
    if (!isPlainObject(item) || typeof item.path !== "string") {
      errors.push(`external-assets.json asset ${index}: path must be a canonical repository-relative path`);
      continue;
    }
    const pathParts = item.path.split("/");
    if (item.path === "" || item.path.includes("\\") ||
        pathParts.some((part) => part === "" || part === "." || part === "..")) {
      errors.push(`external-assets.json asset ${index}: path must be a canonical repository-relative path without dot, empty, or backslash segments`);
      continue;
    }
    const repoPath = join(EXTERNAL_DIR, item.path).split(sep).join("/");
    const manifestAbs = canonicalRepoPath(root, repoPath);
    if (!manifestAbs) {
      errors.push(`external-assets.json asset ${index}: path must resolve to a canonical repository-relative file inside ${EXTERNAL_DIR}`);
      continue;
    }

    const attribution = typeof item.attribution === "string" ? item.attribution.trim().toLowerCase() : "";
    let hasQuaterniusUrl = false;
    for (const field of ["source_url", "download_url"]) {
      if (!Object.hasOwn(item, field)) continue;
      const parsed = parseHttpsUrl(item[field]);
      if (!parsed) {
        errors.push(`external-assets.json asset ${index}: ${field} must be an absolute HTTPS URL with a valid hostname`);
      } else if (isQuaterniusSourceUrl(parsed)) {
        hasQuaterniusUrl = true;
      }
    }
    const hasQuarantinedSourceDigest = referencesQuarantinedQuaterniusSourceDigest(item, quarantinedMemberHashes);
    const isQuaterniusItem = attribution.includes("quaternius") || hasQuaterniusUrl || hasQuarantinedSourceDigest ||
        repoPath.toLowerCase().startsWith("client-godot/assets/external/quaternius/");
    if (isQuaterniusItem && !hasQuarantinedSourceDigest) {
      errors.push(`external-assets.json asset ${index}: Quaternius asset must pin an exact admitted H05/H06 archive or member SHA-256: ${item.path}`);
    }
    if (isQuaterniusItem && hasQuarantinedSourceDigest) {
      const identified = attribution.includes("quaternius") ||
        repoPath.toLowerCase().startsWith("client-godot/assets/external/quaternius/") ||
        hasQuaterniusUrl;
      if (!identified) {
        errors.push(`external-assets.json asset ${index}: must identify the admitted Quaternius H05/H06 source: ${item.path}`);
      }
    }
    manifestByRepoPath.set(repoPath, item);
  }

  const seen = new Set();
  lock.assets.forEach((asset, index) => {
    const at = `vendor.lock.json asset ${index}`;
    if (!asset || typeof asset !== "object" || Array.isArray(asset)) return errors.push(`${at}: must be an object`);
    for (const key of Object.keys(asset)) if (!ENTRY_KEYS.has(key)) errors.push(`${at}: unknown key "${key}"`);
    const abs = canonicalRepoPath(root, asset.path);
    if (!abs) return errors.push(`${at}: path must be a canonical repository-relative path with no dot, empty, backslash, or symlinked component`);
    if (seen.has(abs)) errors.push(`${at}: duplicate path ${asset.path}`);
    seen.add(abs);
    if (typeof asset.sha256 !== "string" || !HASH.test(asset.sha256)) errors.push(`${at}: sha256 must be 64 lowercase hex characters`);
    if (!LICENSES.has(asset.license)) errors.push(`${at}: license "${asset.license}" is not allowlisted; review before admission`);
    if (!parseHttpsUrl(asset.source_url)) errors.push(`${at}: source_url must be an absolute HTTPS URL with a valid hostname`);
    if (typeof asset.vendor !== "string" || !asset.vendor.trim()) errors.push(`${at}: vendor must be a non-empty string`);
    const hasRevision = Object.hasOwn(asset, "source_revision");
    const hasIdentity = Object.hasOwn(asset, "source_identity");
    if (hasRevision === hasIdentity) {
      errors.push(`${at}: exactly one of source_revision or source_identity is required`);
    } else if (hasRevision) {
      if (typeof asset.source_revision !== "string" || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(asset.source_revision)) {
        errors.push(`${at}: source_revision must be an immutable 40/64-character lowercase hex revision or archive digest`);
      }
    } else {
      const prefix = "client-godot/assets/external/polyhaven/";
      const relativeAssetPath = typeof asset.path === "string" && asset.path.startsWith(prefix)
        ? asset.path.slice(prefix.length)
        : "";
      const parts = relativeAssetPath.split("/");
      const slug = parts.shift() ?? "";
      const relativeFile = parts.join("/");
      const hasUnsafePathSegment = parts.some((part) => part === "" || part === "." || part === "..") ||
        relativeAssetPath.includes("\\");
      const slugDirectory = slug ? resolve(root, EXTERNAL_DIR, "polyhaven", slug) : "";
      const staysWithinSlugDirectory = slugDirectory !== "" && abs.startsWith(slugDirectory + sep);
      if (hasUnsafePathSegment || !staysWithinSlugDirectory) {
        errors.push(`${at}: Poly Haven asset path must stay inside its slug directory without dot, empty, or backslash segments`);
      }
      const sourceSlug = typeof asset.source_url === "string"
        ? /^https:\/\/polyhaven\.com\/a\/([a-z0-9_-]+)\/?$/.exec(asset.source_url)?.[1]
        : undefined;
      const expectedIdentity = HASH.test(asset.sha256 ?? "")
        ? `polyhaven-file:${slug}/${relativeFile}@sha256:${asset.sha256}`
        : "";
      if (asset.vendor !== "Poly Haven" || !slug || !relativeFile || sourceSlug !== slug ||
          asset.pack_id !== `polyhaven:${slug}` || asset.source_identity !== expectedIdentity) {
        errors.push(`${at}: source_identity must match the Poly Haven asset page, pack id, repository-relative file path and exact sha256`);
      }
    }
    if (asset.pack_id !== undefined && (typeof asset.pack_id !== "string" || !asset.pack_id.trim())) errors.push(`${at}: pack_id must be a non-empty string when provided`);
    let licenseAbs = null;
    if (typeof asset.license_path !== "string" || !asset.license_path.trim()) {
      errors.push(`${at}: license_path is required`);
    } else {
      licenseAbs = canonicalRepoPath(root, asset.license_path);
      if (!licenseAbs || !existsSync(licenseAbs) || !lstatSync(licenseAbs).isFile()) {
        errors.push(`${at}: license file not found at ${asset.license_path}`);
        licenseAbs = null;
      }
    }
    if (typeof asset.license_sha256 !== "string" || !HASH.test(asset.license_sha256)) {
      errors.push(`${at}: license_sha256 must be 64 lowercase hex characters`);
    } else if (licenseAbs) {
      const actualLicense = sha256File(licenseAbs);
      if (actualLicense !== asset.license_sha256) errors.push(`${at}: license sha256 mismatch for ${asset.license_path} (expected ${asset.license_sha256}, actual ${actualLicense})`);
    }
    if (!existsSync(abs) || lstatSync(abs).isSymbolicLink() || !lstatSync(abs).isFile()) {
      return errors.push(`${at}: file not found or not a regular file: ${asset.path}`);
    }
    const actual = sha256File(abs);
    if (HASH.test(asset.sha256 ?? "") && actual !== asset.sha256) errors.push(`${at}: sha256 mismatch for ${asset.path} (expected ${asset.sha256}, actual ${actual})`);
    const registered = manifestByRepoPath.get(normalizeRepositoryRelativePath(relative(root, abs)));
    if (registered && registered.sha256 !== asset.sha256) errors.push(`${at}: digest disagrees with external-assets.json for ${asset.path}`);
  });

  const externalAbs = canonicalRepoPath(root, EXTERNAL_DIR);
  if (!externalAbs) {
    errors.push(`${EXTERNAL_DIR}: must be a safe repository-relative directory without symlinked components`);
  } else {
    let externalStat;
    try {
      externalStat = lstatSync(externalAbs);
    } catch (error) {
      if (error.code !== "ENOENT") errors.push(`${EXTERNAL_DIR}: cannot inspect (${error.message})`);
    }
    if (externalStat) {
      if (!externalStat.isDirectory()) {
        errors.push(`${EXTERNAL_DIR}: must be a directory`);
      } else {
        const manifestPaths = new Set(manifestByRepoPath.keys());
        for (const file of walk(externalAbs)) {
          const rel = normalizeRepositoryRelativePath(relative(root, file.full));
          if (file.symlink) errors.push(`symlink under ${EXTERNAL_DIR}: ${rel}`);
          else if (GODOT_SIDECARS.has(extname(file.full).toLowerCase())) continue;
          else if (!manifestPaths.has(rel) && !seen.has(file.full)) errors.push(`unregistered file under ${EXTERNAL_DIR}: ${rel}`);
        }
      }
    }
  }
  errors.push(...validateQuarantinedSources(root, lock, quarantinedMemberHashes));
  errors.push(...validateAssetSourceTree(root, lock.assets));
  return errors;
}

module.exports = { validateVendorLock, LICENSES, normalizeRepositoryRelativePath, canonicalRepoPath };

if (require.main === module) {
  const errors = validateVendorLock();
  if (errors.length) {
    console.error("Vendor lock validation FAIL:\n" + errors.map((e) => ` - ${e}`).join("\n"));
    process.exit(1);
  }
  console.log("Vendor lock validation PASS");
}
