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

    @staticmethod
    def spec(folder, frames=6, **overrides):
        values = {
            "folder": Path(folder),
            "frames": frames,
            "width": 8,
            "height": 8,
            "segment_size": 2,
        }
        values.update(overrides)
        return MODULE.CaptureSpec(**values)

    def test_unbroken_capture_passes_screening_only(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24, 25])
            result = MODULE.verify(self.spec(folder))
            self.assertEqual(result["result"], "PASS_SCREENING_NOT_VISUAL_ACCEPTANCE")
            self.assertEqual(set(result["boundaries"]), {"1->2", "3->4"})

    def test_discontinuous_worker_boundary_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 230, 231, 232, 233])
            with self.assertRaisesRegex(ValueError, "boundary discontinuity"):
                MODULE.verify(self.spec(folder))

    def test_lighting_seam_rejected_even_when_global_delta_is_small(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 29, 30, 31, 32])
            with self.assertRaisesRegex(ValueError, "lighting discontinuity"):
                MODULE.verify(self.spec(
                    folder, lighting_roi=(0, 0, 8, 8), max_luma_jump=5.0
                ))

    def test_stable_lighting_boundary_passes(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24, 25])
            result = MODULE.verify(self.spec(folder, lighting_roi=(0, 0, 8, 8)))
            self.assertEqual(result['lighting_boundaries']['1->2'], 1.0)

    def test_missing_frame_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24])
            with self.assertRaisesRegex(ValueError, "missing or malformed frame 5"):
                MODULE.verify(self.spec(folder))

    def test_corrupted_frame_size_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            self.write_frames(folder, [20, 21, 22, 23, 24, 25])
            (Path(folder) / "frame_0003.rgba").write_bytes(b"bad")
            with self.assertRaisesRegex(ValueError, "missing or malformed frame 3"):
                MODULE.verify(self.spec(folder))

    def test_invalid_geometry_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "invalid capture geometry"):
                MODULE.verify(self.spec(folder, frames=5))

    def test_invalid_lighting_roi_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "invalid lighting ROI"):
                MODULE.verify(self.spec(folder, lighting_roi=(0, 0, 9, 8)))


if __name__ == "__main__":
    unittest.main()
