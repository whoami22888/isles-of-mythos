import unittest

from scripts.check_ship_occupancy import FRAMES, PIXEL_COUNT, validate_samples


def sample(frame, hull, sails, total):
    return {
        "frame": frame,
        "hull_pixels": hull,
        "sail_pixels": sails,
        "ship_pixels": total,
        "ship_fraction": total / PIXEL_COUNT,
        "hull_fraction": hull / PIXEL_COUNT,
        "sail_fraction": sails / PIXEL_COUNT,
        "composite_frame_sha256": "a" * 64,
        "mask_frame_sha256": "b" * 64,
    }


class ShipOccupancyTests(unittest.TestCase):
    def valid_samples(self):
        return {
            0: sample(0, 8000, 12000, 20000),
            24: sample(24, 10000, 14000, 24000),
            48: sample(48, 11000, 15000, 26000),
            71: sample(71, 13000, 16000, 29000),
        }

    def test_accepts_bound_increasing_hull_and_sail_coverage(self):
        self.assertEqual(validate_samples(self.valid_samples()), [])

    def test_rejects_missing_sails(self):
        samples = self.valid_samples()
        samples[24]["sail_pixels"] = 0
        self.assertTrue(any("No visible sail" in error for error in validate_samples(samples)))

    def test_rejects_a_detail_shot_that_shrinks(self):
        samples = self.valid_samples()
        samples[71]["ship_fraction"] = samples[48]["ship_fraction"]
        self.assertTrue(any("Detail shot" in error for error in validate_samples(samples)))

    def test_rejects_a_late_approach_that_shrinks(self):
        samples = self.valid_samples()
        samples[48]["ship_fraction"] = samples[24]["ship_fraction"]
        self.assertTrue(any("Late approach" in error for error in validate_samples(samples)))

    def test_requires_hull_and_sail_growth_at_each_shot_beat(self):
        samples = self.valid_samples()
        samples[48]["sail_fraction"] = samples[24]["sail_fraction"]
        self.assertTrue(any("Sail coverage" in error for error in validate_samples(samples)))

    def test_requires_all_four_camera_beats(self):
        samples = self.valid_samples()
        samples.pop(48)
        self.assertIn("Expected exactly the wide, two approach and detail frame samples",
                      validate_samples(samples))


if __name__ == "__main__":
    unittest.main()
