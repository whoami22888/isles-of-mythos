#!/usr/bin/env python3
"""Acquire official Quaternius H05/H06 Google Drive exports into quarantine only.

No asset is extracted to the Godot project, imported, or admitted to vendor.lock.json.
The original Drive-generated ZIP bytes, full file roster, member hashes, dependency
closure checks, and publisher-page licence evidence are retained unchanged.
"""
from __future__ import annotations

import hashlib
import json
import re
import stat
import sys
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlparse

import requests
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright

ROOT = Path("quarantine/quaternius")
ARCHIVES = ROOT / "archives"
EVIDENCE = ROOT / "evidence"
LICENSES = ROOT / "licenses"
DIAGNOSTICS = ROOT / "diagnostics"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
MAX_MEMBER_BYTES = 100 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 512 * 1024 * 1024
MAX_ENTRIES = 10000

PACKS = [
    {
        "id": "H05",
        "name": "Ultimate Monsters",
        "page": "https://quaternius.com/packs/ultimatemonsters.html",
        "announcement": "https://www.patreon.com/quaternius/posts/ultimate-50-73633148",
        "folder": "https://drive.google.com/drive/folders/18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C",
        "expected_root_names": ["Big", "Blob", "Flying", "Atlas_Monsters.png", "License.txt"],
        "historical_export_sha256": "2c7c0987c59abee705fe2b4eb74000aaa02adce556eadedec5740cf99ec159ce",
        "historical_file_count": 260,
    },
    {
        "id": "H06",
        "name": "Cute Animated Monsters",
        "page": "https://quaternius.com/packs/cutemonsters.html",
        "announcement": "https://www.patreon.com/quaternius/posts/cute-animated-20-39982825",
        "folder": "https://drive.google.com/drive/folders/1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0",
        "expected_root_names": ["Blends", "FBX", "glTF", "OBJ", "Textures"],
        "historical_export_sha256": "da8b7cf52e0b84ff24cb851bf7d6844c5581451931dc4b6ccf10d9a7b32e5060",
        "historical_file_count": 127,
    },
]

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def safe_archive_path(name: str) -> bool:
    if not name or "\x00" in name or "\\" in name:
        return False
    parts = name.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return False
    if parts[0].endswith(":"):
        return False
    return not PurePosixPath(name).is_absolute()

def capture_page(session: requests.Session, url: str, path: Path) -> dict:
    record = {"url": url, "status": "NOT_CAPTURED"}
    try:
        response = session.get(url, timeout=(15, 45), allow_redirects=True)
        response.raise_for_status()
        data = response.content
        if len(data) > 5 * 1024 * 1024:
            raise ValueError("publisher evidence page exceeded 5 MiB")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        text = re.sub(r"<[^>]+>", " ", data.decode("utf-8", errors="replace"))
        text = re.sub(r"\s+", " ", text).strip()
        record.update({
            "status": "CAPTURED",
            "final_url": response.url,
            "http_status": response.status_code,
            "content_type": response.headers.get("content-type", ""),
            "size_bytes": len(data),
            "sha256": sha256_bytes(data),
            "mentions_cc0": bool(re.search(r"\bCC0\b", text, re.I)),
            "mentions_commercial_use": bool(re.search(r"personal and commercial projects|commercial purposes", text, re.I)),
            "text_excerpt": text[:1200],
            "path": str(path),
        })
    except Exception as exc:
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record

def click_drive_download(browser, pack: dict, destination: Path) -> dict:
    result = {
        "pack_id": pack["id"],
        "folder_url": pack["folder"],
        "status": "DOWNLOAD_NOT_STARTED",
    }
    page = browser.new_page(accept_downloads=True)
    page.set_default_timeout(20000)
    try:
        response = page.goto(pack["folder"], wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(5000)
        body_text = page.locator("body").inner_text(timeout=15000)
        result["page_http_status"] = response.status if response else None
        result["page_url"] = page.url
        result["expected_root_names_visible"] = {
            name: name in body_text for name in pack["expected_root_names"]
        }
        result["page_title"] = page.title()
        result["body_excerpt"] = body_text[:3000]

        # Public Drive folder pages expose the bulk action as a visible div[role=button]
        # labelled "Download all", not as an aria-labelled native button. Match that exact
        # action first; per-file Download buttons are only exposed on row hover.
        candidates = [
            page.locator('[role="button"]').filter(
                has_text=re.compile(r"^\\s*Download all\\s*$", re.I)
            ),
            page.get_by_text("Download all", exact=True),
            page.locator('[aria-label*="Download" i]'),
            page.locator('[data-tooltip*="Download" i]'),
        ]
        download_button = None
        for locator in candidates:
            if locator.count() > 0:
                for index in range(min(locator.count(), 8)):
                    candidate = locator.nth(index)
                    try:
                        if candidate.is_visible():
                            download_button = candidate
                            break
                    except Exception:
                        continue
            if download_button is not None:
                break

        if download_button is None:
            more_actions = page.get_by_role("button", name=re.compile("more actions", re.I))
            if more_actions.count() > 0 and more_actions.first.is_visible():
                more_actions.first.click()
                menu_download = page.get_by_role("menuitem", name=re.compile("download", re.I))
                if menu_download.count() > 0:
                    download_button = menu_download.first

        if download_button is None:
            diagnostics = DIAGNOSTICS / f"{pack['id']}-folder.png"
            diagnostics.parent.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(diagnostics), full_page=True)
            (DIAGNOSTICS / f"{pack['id']}-folder.html").write_text(page.content(), encoding="utf-8")
            raise RuntimeError("official Drive folder exposed no visible Download action")

        with page.expect_download(timeout=180000) as download_info:
            download_button.click()
        download = download_info.value
        failure = download.failure()
        if failure:
            raise RuntimeError(f"Google Drive download failed: {failure}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        download.save_as(str(destination))
        data = destination.read_bytes()
        if not data.startswith(b"PK\x03\x04"):
            preview = data[:512].decode("utf-8", errors="replace")
            destination.unlink(missing_ok=True)
            raise RuntimeError(
                "Drive Download action did not return ZIP bytes; "
                f"content preview={preview!r}"
            )
        if len(data) > MAX_ARCHIVE_BYTES:
            destination.unlink(missing_ok=True)
            raise RuntimeError(f"archive exceeds {MAX_ARCHIVE_BYTES} byte quarantine cap")
        result.update({
            "status": "DOWNLOADED",
            "suggested_filename": download.suggested_filename,
            "archive_size_bytes": len(data),
            "archive_sha256": sha256_bytes(data),
            "archive_path": str(destination),
        })
    except PlaywrightTimeoutError as exc:
        result["status"] = "DOWNLOAD_FAILED"
        result["error"] = f"PlaywrightTimeoutError: {exc}"
        try:
            diagnostics = DIAGNOSTICS / f"{pack['id']}-timeout.png"
            diagnostics.parent.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(diagnostics), full_page=True)
            (DIAGNOSTICS / f"{pack['id']}-timeout.html").write_text(page.content(), encoding="utf-8")
        except Exception:
            pass
    except Exception as exc:
        result["status"] = "DOWNLOAD_FAILED"
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        page.close()
    return result

def gltf_dependencies(name: str, payload: bytes, all_paths: set[str]) -> dict:
    record = {"source": name, "status": "PASS", "references": [], "missing": [], "parse_error": None}
    try:
        document = json.loads(payload.decode("utf-8"))
        base = PurePosixPath(name).parent
        for group in ("buffers", "images"):
            for item in document.get(group, []):
                uri = item.get("uri")
                if not uri or uri.startswith("data:"):
                    continue
                parsed = urlparse(uri)
                if parsed.scheme or parsed.netloc or uri.startswith("/"):
                    record["missing"].append({"group": group, "uri": uri, "reason": "external or absolute URI"})
                    continue
                resolved = (base / PurePosixPath(unquote(uri))).as_posix()
                record["references"].append({"group": group, "uri": uri, "resolved": resolved})
                if not safe_archive_path(resolved) or resolved not in all_paths:
                    record["missing"].append({"group": group, "uri": uri, "resolved": resolved})
        if record["missing"]:
            record["status"] = "FAIL"
    except Exception as exc:
        record["status"] = "FAIL"
        record["parse_error"] = f"{type(exc).__name__}: {exc}"
    return record

def inspect_archive(pack: dict, archive_path: Path) -> dict:
    archive_sha = sha256_file(archive_path)
    record = {
        "pack_id": pack["id"],
        "pack_name": pack["name"],
        "publisher_page": pack["page"],
        "official_creator_announcement": pack["announcement"],
        "official_drive_folder": pack["folder"],
        "archive": {
            "path": str(archive_path),
            "filename": archive_path.name,
            "size_bytes": archive_path.stat().st_size,
            "sha256": archive_sha,
            "historical_temporary_export_sha256": pack["historical_export_sha256"],
            "matches_historical_temporary_export": archive_sha == pack["historical_export_sha256"],
        },
        "status": "QUARANTINED_BYTES_VERIFIED",
        "admission_status": "NOT_ADMITTED",
    }
    files = []
    license_candidates = []
    gltf_sources = []
    extensions = Counter()
    seen = set()
    total_uncompressed = 0
    with zipfile.ZipFile(archive_path) as archive:
        infos = archive.infolist()
        if len(infos) > MAX_ENTRIES:
            raise ValueError(f"{pack['id']}: ZIP entry count exceeds {MAX_ENTRIES}")
        bad_member = archive.testzip()
        if bad_member is not None:
            raise ValueError(f"{pack['id']}: CRC failure in {bad_member}")
        for info in infos:
            if info.is_dir():
                continue
            name = info.filename
            if not safe_archive_path(name):
                raise ValueError(f"{pack['id']}: unsafe archive member path {name!r}")
            if name in seen:
                raise ValueError(f"{pack['id']}: duplicate archive member {name!r}")
            seen.add(name)
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise ValueError(f"{pack['id']}: symlink archive member rejected: {name}")
            if info.file_size > MAX_MEMBER_BYTES:
                raise ValueError(f"{pack['id']}: member exceeds 100 MiB: {name}")
            total_uncompressed += info.file_size
            if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
                raise ValueError(f"{pack['id']}: uncompressed archive exceeds 512 MiB")
            digest = hashlib.sha256()
            capture = (
                PurePosixPath(name).suffix.lower() in (".gltf", ".txt", ".md")
                or PurePosixPath(name).name.lower() in ("readme", "license", "licence", "notice", "copyright", "credits")
            )
            payload = bytearray() if capture else None
            with archive.open(info) as member:
                for chunk in iter(lambda: member.read(1024 * 1024), b""):
                    digest.update(chunk)
                    if payload is not None:
                        payload.extend(chunk)
            suffix = PurePosixPath(name).suffix.lower() or "[no-extension]"
            extensions[suffix] += 1
            files.append({
                "path": name,
                "size_bytes": info.file_size,
                "sha256": digest.hexdigest(),
                "extension": suffix,
            })
            if suffix == ".gltf" and payload is not None:
                gltf_sources.append((name, bytes(payload)))
            if re.search(r"license|licence|readme|notice|copyright|credits?", PurePosixPath(name).name, re.I):
                license_path = LICENSES / pack["id"] / name
                license_path.parent.mkdir(parents=True, exist_ok=True)
                license_path.write_bytes(bytes(payload) if payload is not None else b"")
                text = bytes(payload or b"").decode("utf-8", errors="replace")
                license_candidates.append({
                    "path": name,
                    "size_bytes": info.file_size,
                    "sha256": digest.hexdigest(),
                    "quarantine_copy": str(license_path),
                    "text_preview": text[:6000],
                })
    all_paths = {item["path"] for item in files}
    dependency_checks = [
        gltf_dependencies(name, payload, all_paths)
        for name, payload in gltf_sources
    ]
    missing = [item for item in dependency_checks if item["status"] != "PASS"]
    record["file_count"] = len(files)
    record["entry_count_including_directories"] = len(infos)
    record["uncompressed_bytes"] = total_uncompressed
    record["extension_counts"] = dict(sorted(extensions.items()))
    record["per_file_manifest"] = files
    record["license_candidates"] = license_candidates
    record["gltf_dependency_checks"] = dependency_checks
    record["gltf_dependency_closure"] = "PASS" if not missing else "FAIL"
    record["zip_crc"] = "PASS"
    record["historical_file_count_match"] = len(files) == pack["historical_file_count"]
    record["licence_assessment"] = (
        "REVIEW_REQUIRED_H05_TITLE_MISMATCH" if pack["id"] == "H05"
        else "MISSING_EMBEDDED_LICENCE_H06"
    )
    return record

def main() -> int:
    for folder in (ARCHIVES, EVIDENCE, LICENSES, DIAGNOSTICS):
        folder.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml,*/*"})
    evidence = {}
    for pack in PACKS:
        evidence[pack["id"]] = capture_page(
            session, pack["page"], EVIDENCE / f"{pack['id']}-publisher-page.html"
        )
    evidence["CC0_DEED"] = capture_page(
        session, "https://creativecommons.org/publicdomain/zero/1.0/",
        EVIDENCE / "CC0-1.0-deed.html",
    )
    evidence["QAL_V1"] = capture_page(
        session, "https://quaternius.com/license.html",
        EVIDENCE / "Quaternius-Asset-License-v1.html",
    )

    acquisitions = []
    inspections = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, args=["--no-sandbox", "--disable-dev-shm-usage"])
        for pack in PACKS:
            destination = ARCHIVES / f"{pack['id']}.zip"
            acquisition = click_drive_download(browser, pack, destination)
            acquisitions.append(acquisition)
            if acquisition["status"] == "DOWNLOADED":
                try:
                    inspections.append(inspect_archive(pack, destination))
                except Exception as exc:
                    acquisition["status"] = "ARCHIVE_REJECTED"
                    acquisition["validation_error"] = f"{type(exc).__name__}: {exc}"
                    destination.unlink(missing_ok=True)
        browser.close()

    manifest = {
        "schema": "iom-quaternius-source-quarantine:v1",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "classification": "QUARANTINE_ONLY_NOT_VENDOR_ADMISSION",
        "policy": {
            "no_assets_src_import": True,
            "no_vendor_lock_change": True,
            "no_godot_import": True,
            "no_production_pr": True,
            "exact_publisher_drive_download_bytes_only": True,
            "no_repacked_or_third_party_archive": True,
        },
        "publisher_page_evidence": evidence,
        "acquisitions": acquisitions,
        "packs": inspections,
        "overall_admission_status": "NOT_ADMITTED",
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    downloaded = [item for item in inspections if item["status"] == "QUARANTINED_BYTES_VERIFIED"]
    summary = [
        "# Quaternius H05/H06 source quarantine",
        "",
        "**Classification:** QUARANTINE ONLY — NOT VENDOR ADMISSION.",
        "",
        "No assets were extracted into the Godot project, imported, added to vendor.lock.json, or represented as production-ready.",
        "",
    ]
    for item in acquisitions:
        summary.append(f"- {item['pack_id']}: {item['status']} — {item.get('archive_sha256', item.get('error', item.get('validation_error', 'no archive')))}")
    for item in inspections:
        summary.append(
            f"- {item['pack_id']}: {item['file_count']} files; ZIP CRC {item['zip_crc']}; "
            f"GLTF dependency closure {item['gltf_dependency_closure']}; licence {item['licence_assessment']}; "
            "NOT_ADMITTED."
        )
    summary.extend([
        "",
        "H05's embedded License.txt title mismatch and H06's missing embedded licence remain explicit review blockers.",
        "Publisher-page CC0 and CC0-deed captures are separate evidence; they do not silently replace or rewrite embedded notices.",
        "Only exact Google Drive Download all ZIP bytes are retained. No locally rebuilt ZIP is created.",
    ])
    (ROOT / "summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print(json.dumps({
        "downloaded_archives": len(downloaded),
        "acquisition_statuses": [item["status"] for item in acquisitions],
        "pack_file_counts": {item["pack_id"]: item["file_count"] for item in inspections},
        "overall_admission_status": "NOT_ADMITTED",
    }, indent=2))
    return 0 if downloaded else 1

if __name__ == "__main__":
    sys.exit(main())
