"""Cold-open contract for the 15-minute onboarding sequence."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "onboarding_sequence.gd"
SCENE = ROOT / "scenes" / "onboarding_sequence.tscn"


class OnboardingSequenceTests(unittest.TestCase):
    def test_cold_open_covers_the_four_published_beats_within_15_minutes(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")
        scene = SCENE.read_text(encoding="utf-8")
        self.assertTrue(SCRIPT.is_file())
        self.assertTrue(SCENE.is_file())
        for beat in (
            "tutorial_cannon_battle",
            "scripted_shipwreck",
            "mythos_rescue",
            "first_campsite_placement",
        ):
            self.assertIn(beat, script)
        self.assertIn("15 * 60", script)
        self.assertIn("onboarding_sequence.gd", scene)


if __name__ == "__main__":
    unittest.main()
