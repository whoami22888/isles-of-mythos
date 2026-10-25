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

    def test_coastal_still_capture_exercises_integrated_fx_scene(self):
        source = (ROOT / "client-godot/tests/render_capture.gd").read_text(encoding="utf-8")
        self.assertIn('res://scenes/realistic_coastal_fx_slice.tscn', source)
        self.assertNotIn('res://scenes/realistic_coastal_slice.tscn", "CinematicRevealCamera"', source)


if __name__ == "__main__":
    unittest.main()
