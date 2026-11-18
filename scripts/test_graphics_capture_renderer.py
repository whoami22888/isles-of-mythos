import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/godot-visual-evidence.yml"


class GraphicsCaptureRendererTests(unittest.TestCase):
    def test_visual_capture_uses_mobile_renderer(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("--rendering-method gl_compatibility", source)
        self.assertGreaterEqual(source.count("--rendering-method mobile"), 2)

    def test_project_declares_mobile_renderer(self):
        project = (ROOT / "client-godot/project.godot").read_text(encoding="utf-8")
        self.assertIn('renderer/rendering_method="mobile"', project)
        self.assertIn('renderer/rendering_method.mobile="mobile"', project)

    def test_vertical_slice_source_sha_is_separate_from_checksum_manifest(self):
        """Keep source metadata out of the checksum-only manifest."""
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotRegex(
            source,
            r'echo\s+"source_sha=.*>>\s*VERTICAL-SLICE-SHA256SUMS',
        )
        self.assertIn('> "$RUNNER_TEMP/visual-evidence/SOURCE_SHA.txt"', source)
        self.assertIn("${{ runner.temp }}/visual-evidence/SOURCE_SHA.txt", source)

    def test_source_sha_writer_uses_a_real_line_terminator(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(r"printf '%s\n'", source)
        self.assertNotIn(r"printf '%s\\n'", source)

    def test_coastal_still_capture_exercises_integrated_fx_scene(self):
        source = (ROOT / "client-godot/tests/render_capture.gd").read_text(encoding="utf-8")
        self.assertIn('res://scenes/realistic_coastal_fx_slice.tscn', source)
        self.assertNotIn('res://scenes/realistic_coastal_slice.tscn", "CinematicRevealCamera"', source)


    def test_visual_capture_forces_and_verifies_vulkan_mobile(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        capture = (ROOT / "client-godot/tests/render_capture.gd").read_text(encoding="utf-8")
        self.assertGreaterEqual(workflow.count("--rendering-driver vulkan"), 5)
        for dependency in ("libvulkan1", "mesa-vulkan-drivers", "vulkan-tools"):
            self.assertIn(dependency, workflow)
        self.assertIn("VK_KHR_surface", workflow)
        self.assertIn("VK_KHR_(xcb|xlib)_surface", workflow)
        self.assertIn("VK_ICD_FILENAMES", workflow)
        self.assertIn("RenderingServer.get_current_rendering_method()", capture)
        self.assertIn("RenderingServer.get_current_rendering_driver_name()", capture)
        self.assertIn('method != "mobile" or driver != "vulkan"', capture)
        self.assertIn("IOM_RENDERER_INFO_PATH", capture)

    def test_renderer_provenance_contains_source_and_asset_hashes(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("godot-renderer-provenance", source)
        self.assertIn("RENDERER-MANIFEST.txt", source)
        self.assertIn("GODOT-RENDERER.json", source)
        self.assertIn("ASSET-SHA256SUMS", source)
        self.assertIn("VISUAL-ARTIFACT-SHA256SUMS", source)


    def test_visual_artifact_checksum_manifest_uses_relative_paths(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('(cd "$RUNNER_TEMP/visual-evidence" && find . -maxdepth 1', source)
        self.assertIn("> VISUAL-ARTIFACT-SHA256SUMS)", source)
        self.assertNotIn('find "$RUNNER_TEMP/visual-evidence" -maxdepth 1', source)

if __name__ == "__main__":
    unittest.main()
