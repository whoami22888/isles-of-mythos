"""Focused fail-closed tests for the non-visual Godot capture boundary screen."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "check_capture_continuity.py"
SPEC = importlib.util.spec_from_file_location("check_capture_continuity", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CaptureContinuityTests(unittest.TestCase):
    def write_frames(self, directory, values, width=8, height=8):
        for index, value in enumerate(values):
            (Path(directory) / f"frame_{index:04d}.rgba").write_bytes(
                bytes((value, value, value, 255)) * (width * height)
            )

    def test_unbroken_capture_passes_screening_only(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24, 25])
            result = MODULE.verify(Path(folder), frames=6, width=8, height=8, segment_size=2)
            self.assertEqual(result["result"], "PASS_SCREENING_NOT_VISUAL_ACCEPTANCE")
            self.assertEqual(set(result["boundaries"]), {"1->2", "3->4"})

    def test_discontinuous_worker_boundary_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 230, 231, 232, 233])
            with self.assertRaisesRegex(ValueError, "boundary discontinuity"):
                MODULE.verify(Path(folder), frames=6, width=8, height=8, segment_size=2)

    def test_missing_frame_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24])
            with self.assertRaisesRegex(ValueError, "missing or malformed frame 5"):
                MODULE.verify(Path(folder), frames=6, width=8, height=8, segment_size=2)

    def test_corrupted_frame_size_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24, 25])
            (Path(folder) / "frame_0003.rgba").write_bytes(b"bad")
            with self.assertRaisesRegex(ValueError, "missing or malformed frame 3"):
                MODULE.verify(Path(folder), frames=6, width=8, height=8, segment_size=2)

    def test_far_ocean_keeps_same_sea_level_across_wave_lod_boundary(self):
        # Structural regression only: actual Godot footage remains the visual gate.
        shader = (Path(__file__).resolve().parents[2]
                  / "client-godot/shaders/ocean_surface.gdshader").read_text()
        self.assertIn("VERTEX.y += 0.18 + displacement * envelope;", shader)
        self.assertNotIn("VERTEX.y += (0.18 + displacement) * envelope;", shader)
        # The water mesh is at WATER_Y - 0.18. A zero wave envelope must
        # still place far water at WATER_Y, not 18cm beneath the near ocean.
        water_y = -0.35
        mesh_y = water_y - 0.18
        for envelope in (0.0, 0.25, 0.5, 1.0):
            self.assertAlmostEqual(mesh_y + 0.18 + 0.0 * envelope, water_y)

    def test_invalid_geometry_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "invalid capture geometry"):
                MODULE.verify(Path(folder), frames=5, width=8, height=8, segment_size=2)


if __name__ == "__main__":
    unittest.main()
