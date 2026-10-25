"""Execute the production reducer against a closed topology fixture."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CoastalTopologyTests(unittest.TestCase):
    def test_closed_surface_has_no_new_boundary(self):
        source = (ROOT / "client-godot/scripts/realistic_coastal_slice.gd").read_text()
        reducer = source[source.index("func _reduce_surface_triangles"):source.index("func _apply_far_foliage_lod")]
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "topology.gd"
            script.write_text("extends SceneTree\n" + reducer + FIXTURE)
            result = subprocess.run([os.environ.get("GODOT_BIN", "godot"), "--headless", "--script", str(script)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

FIXTURE = 'func _init():\n\tvar a=[]\n\ta.resize(Mesh.ARRAY_MAX)\n\ta[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,1,0),Vector3(0,0,1)])\n\ta[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,0,1,3,1,2,3,2,0,3])\n\tvar m=ArrayMesh.new()\n\tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)\n\tvar r=_reduce_surface_triangles(m,0,2)\n\tvar edges={}\n\tvar ids=r[Mesh.ARRAY_INDEX]\n\tfor i in range(0,ids.size(),3):\n\t\tfor j in range(3):\n\t\t\tvar x=ids[i+j]\n\t\t\tvar y=ids[i+(j+1)%3]\n\t\t\tvar k=Vector2i(mini(x,y),maxi(x,y))\n\t\t\tedges[k]=edges.get(k,0)+1\n\tfor count in edges.values():\n\t\tif count != 2:\n\t\t\tprinterr("RED: triangle reduction opens a closed surface")\n\t\t\tquit(1)\n\t\t\treturn\n\tquit(0)\n'

if __name__ == "__main__":
    unittest.main()
