# Vendor asset source identity

## Pin semantics

- `sha256` is the digest of the exact file bytes admitted to the repository.
- `license_sha256` pins the exact bytes at `license_path`, independently of the asset digest; the validator recomputes it for every lock entry and rejects missing or altered licence evidence.
- `source_revision` is reserved for an immutable upstream revision, such as a
  Git commit, or the SHA-256 of the original source archive. Never copy a file's
  own SHA-256 into this field and call it a pack revision.
- `source_identity` is a documented, immutable per-file identity for the
  existing Poly Haven files where the source page identifies the asset but the
  downloaded file set has no separately verified upstream archive revision. It
  is not a vendor revision and is not an archive digest.

## Poly Haven format

`polyhaven-file:<asset-slug>/<path-relative-to-that-asset>@sha256:<file-sha256>`

The validator requires all of the following to agree:

1. `source_url` is the official `https://polyhaven.com/a/<asset-slug>` page.
2. `pack_id` is `polyhaven:<asset-slug>`.
3. The repository path is under
   `client-godot/assets/external/polyhaven/<asset-slug>/`.
4. The relative file path and SHA-256 in `source_identity` exactly match the
   lock entry.
5. The actual repository file bytes match the lock entry's `sha256`.

This records the identity of one exact file from one official asset page. It
does **not** prove that the original ZIP/archive was complete, that every file
in a pack was admitted, or that the asset's licence is satisfied. The licence
path, official source page, redistribution rights and dependency closure remain
separate checks.

## Other vendors

For source imports under `assets-src/`, retain an immutable `source_revision`
(Git commit or verified source-archive SHA-256), the exact archive/file hashes,
embedded licence evidence and complete dependency roster. Kenney and Quaternius
admission must use the exact official archive bytes and inspect the embedded
licence and file roster; this Poly Haven per-file identity format is not a
substitute.
