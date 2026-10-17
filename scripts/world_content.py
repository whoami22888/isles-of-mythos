#!/usr/bin/env python3
"""Deterministic, client-only Isles of Mythos visual content selection and harvest.

This never determines combat, loot, economy, spawn authority, capture, or persistence.
Premium assets require independently verified admission; candidate URLs never spawn.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
from urllib.parse import urlsplit
from typing import Any

_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_MD5 = re.compile(r"[0-9a-f]{32}\Z")
_SLUG = re.compile(r"[a-z][a-z0-9_-]*\Z")
_TYPES = {"character", "creature", "vessel", "environment", "prop"}
_LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0"}
_LIMIT = 32 * 1024 * 1024


class ContentError(ValueError):
    """A visual source, reference, or admission property is not trustworthy."""


def _id(value: object, where: str) -> str:
    if not isinstance(value, str) or not _SLUG.fullmatch(value):
        raise ContentError(f"{where}: invalid id")
    return value


def _safe_relative(value: object) -> str:
    if not isinstance(value, str) or not value or "\\" in value or "\0" in value:
        raise ContentError("Invalid relative asset path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.parts[0] == ".":
        raise ContentError("Unsafe asset path")
    return value


def _safe_file(root: Path, relative: str) -> Path:
    relative = _safe_relative(relative)
    if root.is_symlink():
        raise ContentError("Symlinked asset root")
    current = root
    for part in PurePosixPath(relative).parts:
        current = current / part
        if current.is_symlink():
            raise ContentError("Symlinked asset path")
    if not current.resolve().is_relative_to(root.resolve()):
        raise ContentError("Asset path escapes approved root")
    return current


def _candidate(candidate: dict[str, Any]) -> None:
    name = _id(candidate.get("id"), "lighting")
    if candidate.get("status") != "candidate" or candidate.get("license") != "CC0-1.0":
        raise ContentError(f"{name}: HDRI must be an unadmitted CC0 candidate")
    _safe_relative(candidate.get("path"))
    source = urlsplit(str(candidate.get("source_url", "")))
    url = urlsplit(str(candidate.get("download_url", "")))
    slug = source.path.removeprefix("/a/")
    if (source.scheme != "https" or source.hostname != "polyhaven.com"
            or source.port not in (None, 443) or source.username or source.password
            or source.query or source.fragment or not _SLUG.fullmatch(slug)
            or source.path != f"/a/{slug}"):
        raise ContentError(f"{name}: source is not an exact Poly Haven asset page")
    if (url.scheme != "https" or url.hostname != "dl.polyhaven.org"
            or url.port not in (None, 443) or url.username or url.password
            or url.query or url.fragment or url.path !=
            f"/file/ph-assets/HDRIs/hdr/1k/{slug}_1k.hdr"):
        raise ContentError(f"{name}: download URL must match publisher HDRI 1K file")
    count = candidate.get("bytes")
    if type(count) is not int or count <= 0 or count > _LIMIT:
        raise ContentError(f"{name}: size is not within 32MiB candidate ceiling")
    if not isinstance(candidate.get("md5"), str) or not _MD5.fullmatch(candidate["md5"]):
        raise ContentError(f"{name}: publisher MD5 must be provided")
    if candidate.get("format") != "hdr":
        raise ContentError(f"{name}: only real HDR radiance candidates allowed")
    if (not isinstance(candidate.get("sha256"), str)
            or not _SHA256.fullmatch(candidate["sha256"])):
        raise ContentError(f"{name}: candidate requires a post-harvest pinned SHA256")


def validate_catalog(catalog: dict[str, Any]) -> dict[str, Any]:
    """Fail closed on invalid identities, unadmitted assets and unsafe metadata."""
    if not isinstance(catalog, dict) or catalog.get("schema_version") != 1:
        raise ContentError("Unrecognized content catalogue version")
    for key in ("archetypes", "asset_records", "lighting_candidates", "encounter_shots", "light_profiles"):
        if not isinstance(catalog.get(key), list):
            raise ContentError(f"Missing array {key}")
    unique: set[tuple[str, str]] = set()
    def register(items: list[dict], kind: str) -> dict[str, dict]:
        result = {}
        for item in items:
            if not isinstance(item, dict):
                raise ContentError(f"Invalid {kind} entry")
            key = _id(item.get("id"), kind)
            if (kind, key) in unique:
                raise ContentError(f"Duplicate {kind} id: {key}")
            unique.add((kind, key))
            result[key] = item
        return result
    assets = register(catalog["asset_records"], "asset")
    slots = register(catalog["archetypes"], "archetype")
    lights = register(catalog["light_profiles"], "lighting profile")
    hdris = register(catalog["lighting_candidates"], "lighting candidate")
    register(catalog["encounter_shots"], "encounter")
    for item in assets.values():
        if item.get("status") != "approved":
            raise ContentError("Asset records may contain only verified approved content")
        _safe_relative(item.get("path"))
        if not isinstance(item.get("sha256"), str) or not _SHA256.fullmatch(item["sha256"]):
            raise ContentError("Approved asset is missing SHA256")
        if (item.get("license") not in _LICENSES or item.get("visual_review") != "approved"
                or item.get("pbr") is not True or type(item.get("lod_levels")) is not int
                or item["lod_levels"] < 2 or not isinstance(item.get("attribution"), str)
                or not item["attribution"].strip()):
            raise ContentError("Approved art lacks licenses, PBR, LODs, or human visual acceptance")
        source = urlsplit(str(item.get("source_url", "")))
        if source.scheme != "https" or not source.hostname or source.username or source.password:
            raise ContentError("Approved art lacks publisher provenance")
        if type(item.get("bytes")) is not int or item["bytes"] < 1:
            raise ContentError("Approved art is missing file length")
    for slot in slots.values():
        if slot.get("kind") not in _TYPES:
            raise ContentError("Invalid scene actor kind")
        if not isinstance(slot.get("biomes"), list) or not slot["biomes"] or any(
                not isinstance(b, str) or not _SLUG.fullmatch(b) for b in slot["biomes"]):
            raise ContentError("Invalid supported biomes")
        asset_id = slot.get("asset_id")
        if asset_id is not None and asset_id not in assets:
            raise ContentError("Archetype cannot spawn unapproved asset")
    for hdr in hdris.values():
        _candidate(hdr)
    for light in lights.values():
        if light.get("time") not in ("dawn", "day", "sunset", "dusk", "night", "storm"):
            raise ContentError("Invalid time/lighting profile")
        if (not isinstance(light.get("exposure"), (float, int))
                or not math.isfinite(light["exposure"])
                or not 0.15 <= light["exposure"] <= 2.0):
            raise ContentError("Unbounded mobile exposure")
        if light.get("candidate_asset") is not None and light["candidate_asset"] not in hdris:
            raise ContentError("Light profile references absent HDRI")
    for shot in catalog["encounter_shots"]:
        if shot.get("lighting") not in lights or not isinstance(shot.get("cast"), list):
            raise ContentError("Encounter references unknown light profile")
        if not shot["cast"] or any(k not in slots for k in shot["cast"]):
            raise ContentError("Encounter references unknown actor archetype")
        if not isinstance(shot.get("biome"), str) or not _SLUG.fullmatch(shot["biome"]):
            raise ContentError("Invalid encounter biome")
        if any(shot["biome"] not in slots[k]["biomes"] for k in shot["cast"]):
            raise ContentError("Encounter actor does not belong in its biome")
    return catalog


def verify_admitted_assets(catalog: dict[str, Any], asset_root: Path) -> list[str]:
    """No content is approved without exact file bytes under the controlled root."""
    validate_catalog(catalog)
    paths = []
    for record in catalog["asset_records"]:
        path = _safe_file(asset_root, record["path"])
        if not path.is_file() or path.stat().st_size != record["bytes"]:
            raise ContentError("Admitted content file missing or wrong length")
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(65536), b""):
                digest.update(chunk)
        if digest.hexdigest() != record["sha256"]:
            raise ContentError("Admitted content SHA256 mismatch")
        paths.append(record["path"])
    return paths


def verify_downloaded_bytes(candidate: dict[str, Any], data: bytes) -> dict[str, Any]:
    """Verify publisher metadata and return SHA256 receipt, not automatic admission."""
    _candidate(candidate)
    if (len(data) != candidate["bytes"] or hashlib.md5(data).hexdigest() != candidate["md5"]
            or hashlib.sha256(data).hexdigest() != candidate["sha256"]):
        raise ContentError("Candidate asset differs from publisher size, MD5 or pinned SHA256")
    return {"id": candidate["id"], "bytes": len(data),
            "source_url": candidate["source_url"], "sha256": hashlib.sha256(data).hexdigest(),
            "status": "downloaded_unadmitted"}


def _valid_position(pos: object) -> bool:
    return (isinstance(pos, list) and len(pos) == 3
            and all(type(x) in (int, float) and math.isfinite(x) and abs(x) <= 1e7 for x in pos))


def select_visible(catalog: dict[str, Any], events: list[dict], camera: list[float],
                   asset_root: Path, *, max_total: int = 20, max_distance: float = 160.0,
                   near_distance: float = 35.0) -> list[dict[str, Any]]:
    """Deterministic *presentation* plan, never server authority or encounter spawns.

    This build-time/scene-transition planner is not a per-frame gameplay scheduler.
    Its budget is conservative until physical Android profiling establishes more.
    """
    validate_catalog(catalog)
    verify_admitted_assets(catalog, asset_root)
    if (not _valid_position(camera) or type(max_total) is not int or not 0 <= max_total <= 64
            or not math.isfinite(max_distance) or not 0 < max_distance <= 1000
            or not math.isfinite(near_distance) or not 0 < near_distance <= max_distance):
        raise ContentError("Invalid camera or presentation budget")
    slots = {x["id"]: x for x in catalog["archetypes"]}
    approved = {x["id"]: x for x in catalog["asset_records"]}
    seen = set()
    proposed = []
    for entity in events:
        if not isinstance(entity, dict):
            continue
        eid = entity.get("id")
        slot = slots.get(entity.get("archetype"))
        position = entity.get("position")
        if not isinstance(eid, str) or not eid or eid in seen or slot is None or not _valid_position(position):
            continue
        seen.add(eid)
        record = approved.get(slot["asset_id"])
        if record is None:
            continue
        distance_sq = sum((x - y) ** 2 for x, y in zip(position, camera))
        if distance_sq > max_distance ** 2:
            continue
        proposed.append((distance_sq, eid, record, position, slot))
    proposed.sort(key=lambda item: (item[0], item[1]))
    return [{"id": eid, "asset_path": record["path"], "kind": slot["kind"],
             "position": position, "lod_hint": 0 if d <= near_distance ** 2 else 1}
            for d, eid, record, position, slot in proposed[:max_total]]


def load_catalog(path: Path) -> dict[str, Any]:
    return validate_catalog(json.loads(path.read_text(encoding="utf-8")))
