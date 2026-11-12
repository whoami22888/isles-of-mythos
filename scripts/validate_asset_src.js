#!/usr/bin/env node
"use strict";

// Fail-closed guard for incoming, original third-party source imports.
// Unlike Godot-generated sidecars, source imports are never exempt.
const { createHash } = require("node:crypto");
const { existsSync, lstatSync, readdirSync, readFileSync } = require("node:fs");
const { join, relative, resolve, sep } = require("node:path");

const SHA256 = /^[0-9a-f]{64}$/;
const REVISION = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;

function fileHash(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function validateAssetSourceTree(repositoryRoot, lockEntries) {
  const root = resolve(repositoryRoot);
  const sourceRoot = join(root, "assets-src");
  const sourceLocks = lockEntries.filter((entry) => entry && typeof entry.path === "string" && entry.path.startsWith("assets-src/"));
  if (!existsSync(sourceRoot)) {
    return sourceLocks.map((entry) => "assets-src: locked import missing " + entry.path);
  }
  const errors = [];
  const stat = lstatSync(sourceRoot);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    return ["assets-src: must be a real directory, not a symlink or file"];
  }

  const entries = new Map();
  for (const entry of lockEntries) {
    if (!entry || typeof entry.path !== "string" || !entry.path.startsWith("assets-src/")) continue;
    if (entries.has(entry.path)) errors.push("assets-src: duplicate lock entry " + entry.path);
    entries.set(entry.path, entry);
  }

  const observed = new Set();
  function inspect(directory) {
    for (const filename of readdirSync(directory).sort()) {
      const absolute = join(directory, filename);
      const rel = relative(root, absolute).split(sep).join("/");
      const status = lstatSync(absolute);
      if (status.isSymbolicLink()) {
        errors.push("assets-src: symlink rejected: " + rel);
        continue;
      }
      if (status.isDirectory()) {
        inspect(absolute);
        continue;
      }
      if (!status.isFile()) {
        errors.push("assets-src: non-regular file rejected: " + rel);
        continue;
      }
      observed.add(rel);
      const actual = fileHash(absolute);
      const record = entries.get(rel);
      if (!record) {
        errors.push("assets-src: unlisted import " + rel + " (actual sha256 " + actual + ")");
        continue;
      }
      if (!SHA256.test(record.sha256 ?? "") || actual !== record.sha256) {
        errors.push("assets-src: sha256 mismatch " + rel + " (expected " + String(record.sha256) + ", actual " + actual + ")");
      }
      if (typeof record.vendor !== "string" || !record.vendor.trim()) {
        errors.push("assets-src: " + rel + " missing vendor provenance");
      }
      if (typeof record.source_revision !== "string" || !REVISION.test(record.source_revision)) {
        errors.push("assets-src: " + rel + " must pin a 40/64-character hexadecimal source_revision");
      }
    }
  }
  inspect(sourceRoot);
  for (const path of entries.keys()) {
    if (!observed.has(path)) errors.push("assets-src: locked import missing " + path);
  }
  return errors;
}

module.exports = { validateAssetSourceTree };
