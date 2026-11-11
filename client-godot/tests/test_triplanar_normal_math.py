"""CPU reference checks for Prompt 005 triplanar normal orientation.

These tests do not compile or render a Godot shader; engine evidence remains mandatory.
"""
import math
import unittest


def normalize(v):
    length = math.sqrt(sum(x * x for x in v))
    return tuple(x / length for x in v)


def blend_normal(geometric, samples, sharpness=4.0):
    n = normalize(geometric)
    raw = [abs(v) ** sharpness for v in n]
    total = sum(raw)
    weights = [v / total for v in raw]
    signs = [1 if v >= 0 else -1 for v in n]
    nx, ny, nz = samples
    tx = (nx[2] * signs[0], nx[0], nx[1])
    ty = (ny[0], ny[2] * signs[1], ny[1])
    tz = (nz[0], nz[1], nz[2] * signs[2])
    flats = ((signs[0], 0, 0), (0, signs[1], 0), (0, 0, signs[2]))
    projections = (tx, ty, tz)
    perturbation = tuple(sum(weights[j] * (projections[j][i] - flats[j][i]) for j in range(3)) for i in range(3))
    return normalize(tuple(n[i] + perturbation[i] for i in range(3)))


class TriplanarNormalReferenceTests(unittest.TestCase):
    def test_flat_normal_map_preserves_six_axis_faces(self):
        flat = (0.0, 0.0, 1.0)
        for axis in range(3):
            for sign in (-1, 1):
                face = tuple(sign if i == axis else 0 for i in range(3))
                actual = blend_normal(face, (flat, flat, flat))
                for a, expected in zip(actual, face):
                    self.assertAlmostEqual(a, expected, places=7)

    def test_flat_normal_map_preserves_oblique_faces(self):
        flat = (0.0, 0.0, 1.0)
        for face in ((1, 1, 1), (-1, 2, -3), (0.1, -0.2, 0.7),
                     (-0.5, -0.5, 0.25)):
            actual = blend_normal(face, (flat, flat, flat))
            for component, expected in zip(actual, normalize(face)):
                self.assertAlmostEqual(component, expected, places=7)

    def test_weighted_blend_remains_normalized(self):
        samples = ((0.2, -0.1, math.sqrt(0.95)),
                   (-0.1, 0.2, math.sqrt(0.95)),
                   (0.1, 0.2, math.sqrt(0.95)))
        for face in ((1, 2, 3), (-1, 2, -3), (0.1, -0.2, 0.7)):
            result = blend_normal(face, samples)
            self.assertAlmostEqual(sum(v * v for v in result), 1.0, places=7)
            self.assertTrue(all(math.isfinite(v) for v in result))


if __name__ == '__main__':
    unittest.main()
