#!/usr/bin/env node
"use strict";
// Fail-closed check of vendor.lock.json (IOM-00). A third-party asset may only be pinned with a SHA-256 that matches
// the file on disk, an allowlisted SPDX licence and a licence file that exists in the repository. This complements,
// and does not replace, scripts/validate_godot_assets.py + client-godot/assets/external-assets.json (the rich
// provenance registry for client-godot/assets/external): entries present in both must agree on the digest, and no
// file under client-godot/assets/external may exist in neither registry.

const { createHash } = require("node:crypto");
const { existsSync, lstatSync, readdirSync, readFileSync } = require("node:fs");
const { join, relative, resolve, sep, isAbsolute } = require("node:path");

const LICENSES = new Set(["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "MIT", "Apache-2.0", "OFL-1.1"]); // same as validate_godot_assets.py
const HASH = /^[0-9a-f]{64}$/;
const TOP_KEYS = new Set(["$schema", "version", "assets"]);
const ENTRY_KEYS = new Set(["path", "sha256", "license", "license_path", "source_url"]);
const EXTERNAL_DIR = join("client-godot", "assets", "external");

function sha256File(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

/** Resolve a repo-relative path; returns null when it is absolute, empty or escapes the repository. */
function inside(root, p) {
  if (typeof p !== "string" || p.trim() === "" || isAbsolute(p)) return null;
  const abs = resolve(root, p);
  return abs === root || abs.startsWith(root + sep) ? abs : null;
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

function readJson(file, errors, label) {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    errors.push(`${label}: cannot read or parse (${error.message})`);
    return null;
  }
}

function validateVendorLock(root = resolve(__dirname, "..")) {
  root = resolve(root);
  const errors = [];
  const lockFile = join(root, "vendor.lock.json");
  if (!existsSync(lockFile)) return ["vendor.lock.json is missing"];
  const lock = readJson(lockFile, errors, "vendor.lock.json");
  if (!lock) return errors;
  if (typeof lock !== "object" || Array.isArray(lock)) return ["vendor.lock.json: top level must be an object"];
  for (const key of Object.keys(lock)) if (!TOP_KEYS.has(key)) errors.push(`vendor.lock.json: unknown key "${key}"`);
  if (typeof lock.version !== "string" || !lock.version) errors.push("vendor.lock.json: version must be a non-empty string");
  if (!Array.isArray(lock.assets)) return [...errors, "vendor.lock.json: assets must be an array"];

  const manifestFile = join(root, "client-godot", "assets", "external-assets.json");
  const manifest = existsSync(manifestFile) ? readJson(manifestFile, errors, "external-assets.json") : null;
  const manifestByRepoPath = new Map();
  for (const item of manifest?.assets ?? []) {
    if (item && typeof item.path === "string") manifestByRepoPath.set(join(EXTERNAL_DIR, item.path), item);
  }

  const seen = new Set();
  lock.assets.forEach((asset, index) => {
    const at = `vendor.lock.json asset ${index}`;
    if (!asset || typeof asset !== "object" || Array.isArray(asset)) return errors.push(`${at}: must be an object`);
    for (const key of Object.keys(asset)) if (!ENTRY_KEYS.has(key)) errors.push(`${at}: unknown key "${key}"`);
    const abs = inside(root, asset.path);
    if (!abs) return errors.push(`${at}: path must be a non-empty repository-relative path`);
    if (seen.has(abs)) errors.push(`${at}: duplicate path ${asset.path}`);
    seen.add(abs);
    if (typeof asset.sha256 !== "string" || !HASH.test(asset.sha256)) errors.push(`${at}: sha256 must be 64 lowercase hex characters`);
    if (!LICENSES.has(asset.license)) errors.push(`${at}: license "${asset.license}" is not allowlisted; review before admission`);
    if (typeof asset.source_url !== "string" || !asset.source_url.startsWith("https://")) errors.push(`${at}: source_url must be https`);
    if (typeof asset.license_path !== "string" || !asset.license_path.trim()) {
      errors.push(`${at}: license_path is required`);
    } else {
      const licenseAbs = inside(root, asset.license_path);
      if (!licenseAbs || !existsSync(licenseAbs) || !lstatSync(licenseAbs).isFile()) errors.push(`${at}: license file not found at ${asset.license_path}`);
    }
    if (!existsSync(abs) || lstatSync(abs).isSymbolicLink() || !lstatSync(abs).isFile()) {
      return errors.push(`${at}: file not found or not a regular file: ${asset.path}`);
    }
    const actual = sha256File(abs);
    if (HASH.test(asset.sha256 ?? "") && actual !== asset.sha256) errors.push(`${at}: sha256 mismatch for ${asset.path}`);
    const registered = manifestByRepoPath.get(relative(root, abs));
    if (registered && registered.sha256 !== asset.sha256) errors.push(`${at}: digest disagrees with external-assets.json for ${asset.path}`);
  });

  const externalAbs = join(root, EXTERNAL_DIR);
  if (existsSync(externalAbs)) {
    const manifestPaths = new Set(manifestByRepoPath.keys());
    for (const file of walk(externalAbs)) {
      const rel = relative(root, file.full);
      if (file.symlink) errors.push(`symlink under ${EXTERNAL_DIR}: ${rel}`);
      else if (!manifestPaths.has(rel) && !seen.has(file.full)) errors.push(`unregistered file under ${EXTERNAL_DIR}: ${rel}`);
    }
  }
  return errors;
}

module.exports = { validateVendorLock, LICENSES };

if (require.main === module) {
  const errors = validateVendorLock();
  if (errors.length) {
    console.error("Vendor lock validation FAIL:\n" + errors.map((e) => ` - ${e}`).join("\n"));
    process.exit(1);
  }
  console.log("Vendor lock validation PASS");
}
