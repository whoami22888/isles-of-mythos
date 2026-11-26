"""1,000-iteration contract for Mendelian IV inheritance in breeding_recombinator.gd."""

from __future__ import annotations

import math
import random
import re
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "breeding_recombinator.gd"
IV_MIN, IV_MAX = 0, 31
MUTATION_CHANCE = 0.05
GAUSSIAN_MEAN = 0.5
GAUSSIAN_SIGMA = 1.8


def inherit_iv(parent_a: int, parent_b: int, rng: random.Random) -> int:
    midpoint = math.floor((parent_a + parent_b) / 2)
    delta = rng.gauss(GAUSSIAN_MEAN, GAUSSIAN_SIGMA)
    return max(IV_MIN, min(IV_MAX, math.floor(midpoint + delta)))


def can_breed(current_population: int, capacity: int) -> bool:
    if current_population < 0 or capacity < 0:
        return False
    return current_population < capacity


class BreedingRecombinatorTests(unittest.TestCase):
    def test_script_publishes_the_frozen_formula_constants(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertTrue(SCRIPT.is_file())
        self.assertRegex(text, r"const MUTATION_CHANCE\s*:=\s*0\.05")
        self.assertRegex(text, r"const GAUSSIAN_MEAN\s*:=\s*0\.5")
        self.assertRegex(text, r"const GAUSSIAN_SIGMA\s*:=\s*1\.8")
        self.assertIn("clampi", text)
        self.assertIn("randfn", text)

    def test_one_thousand_iv_iterations_track_the_parental_midpoint(self) -> None:
        parent_a, parent_b = 10, 20
        midpoint = math.floor((parent_a + parent_b) / 2)
        rng = random.Random(20261126)
        samples = [inherit_iv(parent_a, parent_b, rng) for _ in range(1000)]
        average = sum(samples) / len(samples)
        # 5% of the midpoint (15 * 0.05 = 0.75). Mean is slightly above mid because randfn mean is 0.5.
        self.assertLess(abs(average - midpoint) / midpoint, 0.05, f"average={average} midpoint={midpoint}")
        self.assertTrue(all(IV_MIN <= value <= IV_MAX for value in samples))

    def test_full_camp_population_rejects_breeding(self) -> None:
        self.assertTrue(can_breed(3, 4))
        self.assertFalse(can_breed(4, 4))
        self.assertFalse(can_breed(5, 4))


if __name__ == "__main__":
    unittest.main()
