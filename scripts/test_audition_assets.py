import json
import tempfile
import unittest
from pathlib import Path
from PIL import Image

from audition_assets import validate_manifest, patch_sail_opacity, AssetFailure, validate_engine_frames


class AuditionAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = {
            'asset_id':'dutch_ship_medium','license':'CC0-1.0',
            'publisher':'https://polyhaven.com/a/dutch_ship_medium',
            'files':[
                {'path':'dutch_ship_medium_1k.gltf','url':'https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/dutch_ship_medium/dutch_ship_medium_1k.gltf','size':70,'md5':'a'*32,'sha256':'b'*64},
                {'path':'textures/dutch_ship_medium_sails_diff_1k.jpg','url':'https://dl.polyhaven.org/file/ph-assets/Models/jpg/1k/dutch_ship_medium/dutch_ship_medium_sails_diff_1k.jpg','size':80,'md5':'a'*32,'sha256':'b'*64},
                {'path':'textures/dutch_ship_medium_sails_alpha_1k.png','url':'https://dl.polyhaven.org/file/ph-assets/Models/png/1k/dutch_ship_medium/dutch_ship_medium_sails_alpha_1k.png','size':80,'md5':'a'*32,'sha256':'b'*64},
            ]
        }

    def test_manifest_allowlists_creator_and_file_routes(self):
        validate_manifest(self.manifest)

    def test_manifest_rejects_host_confusion_and_traversal(self):
        for u in ['https://dl.polyhaven.org.evil.test/file/x', 'https://evil.test/file/x',
                  'http://dl.polyhaven.org/file/x', 'https://dl.polyhaven.org@evil.test/file/x']:
            m=json.loads(json.dumps(self.manifest))
            m['files'][0]['url']=u
            with self.subTest(u=u), self.assertRaises(AssetFailure): validate_manifest(m)
        self.manifest['files'][0]['path']='../models/intruder.gltf'
        with self.assertRaises(AssetFailure): validate_manifest(self.manifest)

    def test_manifest_rejects_unpinned_original_glb_and_texture_source(self):
        m=json.loads(json.dumps(self.manifest))
        m['files'][0].pop('sha256')
        with self.assertRaises(AssetFailure): validate_manifest(m)
        m=json.loads(json.dumps(self.manifest))
        m['files'][1]['sha256']=''
        with self.assertRaises(AssetFailure): validate_manifest(m)

    def test_manifest_rejects_missing_or_invalid_hash_size(self):
        for change in [{'md5':'bad'},{'size':0},{'size':100_000_000}]:
            m=json.loads(json.dumps(self.manifest))
            m['files'][0].update(change)
            with self.subTest(change=change), self.assertRaises(AssetFailure):validate_manifest(m)

    def test_sail_opacity_is_alpha_capable_and_uses_mask(self):
        gltf={'images':[{'uri':'textures/dutch_ship_medium_sails_diff_1k.jpg'}],
              'textures':[{'source':0}],
              'materials':[{'name':'dutch_ship_medium_sails','alphaMode':'OPAQUE',
                  'pbrMetallicRoughness':{'baseColorTexture':{'index':0}}}]}
        file=self.root/'dutch_ship_medium_1k.gltf';file.write_text(json.dumps(gltf))
        tex=self.root/'textures';tex.mkdir()
        Image.new('RGB',(4,4),'brown').save(tex/'dutch_ship_medium_sails_diff_1k.jpg')
        alpha=Image.new('L',(4,4),255);alpha.putpixel((0,0),0)
        alpha.save(tex/'dutch_ship_medium_sails_alpha_1k.png')
        receipts=patch_sail_opacity(self.root)
        corrected=json.loads(file.read_text())
        self.assertEqual(corrected['materials'][0]['alphaMode'],'MASK')
        imgpath=corrected['images'][0]['uri']
        with Image.open(self.root/imgpath) as rgba:
            self.assertEqual(rgba.mode,'RGBA')
            self.assertEqual(rgba.getpixel((0,0))[3],0)
            self.assertEqual(rgba.getpixel((1,1))[3],255)
        self.assertEqual(len(receipts['sha256']),64)

    def test_missing_opacity_is_rejected_not_faked(self):
        (self.root/'dutch_ship_medium_1k.gltf').write_text(json.dumps({'images':[],'materials':[]}))
        with self.assertRaises(AssetFailure):patch_sail_opacity(self.root)

    def test_rendered_frames_require_nonblank_and_temporal_change(self):
        d=self.root/'frames';d.mkdir()
        for i in range(3):
            im=Image.new('RGB',(64,64),'navy')
            for x in range(3+i,12+i):
                for y in range(5,30):im.putpixel((x,y),(240,170,60))
            im.save(d/f'frame_{i:03d}.png')
        self.assertTrue(validate_engine_frames(d,min_frames=3,min_width=64))
        for i in range(3): Image.new('RGB',(64,64),'navy').save(d/f'frame_{i:03d}.png')
        with self.assertRaises(AssetFailure): validate_engine_frames(d,min_frames=3,min_width=64)

    def test_godot_capture_rejects_nonexistent_float_trig_functions(self):
        # Regression from CI 39041111587: GDScript 4.7.2 exposes sin/cos, not sinf/cosf.
        source = (Path(__file__).resolve().parents[1] / 'client-godot/tests/render_vessel_audition.gd').read_text()
        self.assertNotRegex(source, r'\b(?:sinf|cosf)\s*\(')

    def test_engine_audition_enforces_full_model_camera_framing(self):
        # Root cause from actual PR #171 engine-rendered still:
        # mast/sail geometry clipped above the 1280x720 capture.
        source = (Path(__file__).resolve().parents[1] / 'client-godot/tests/render_vessel_audition.gd').read_text()
        self.assertIn('unproject_position(', source)
        self.assertIn('if not framed:', source)
        self.assertIn('Cannot frame complete ship geometry', source)

    def test_static_image_without_motion_is_rejected_as_animation(self):
        d=self.root/'frames';d.mkdir()
        Image.new('RGB',(128,128),'white').save(d/'frame_000.png')
        with self.assertRaises(AssetFailure):validate_engine_frames(d,min_frames=3,min_width=64)


class CinematicSourceRegressions(unittest.TestCase):
    def setUp(self):
        self.script = (Path(__file__).parents[1] / 'client-godot/tests/render_vessel_audition.gd').read_text()
        self.workflow = (Path(__file__).parents[1] / '.github/workflows/iom-premium-asset-audition.yml').read_text()

    def test_reference_duration_and_frame_rate(self):
        self.assertIn('const CAPTURE_FRAMES := 240', self.script)
        self.assertIn(' -framerate 24 ', self.workflow)
        self.assertIn('--min-frames 240', self.workflow)
        self.assertIn('test "$COUNT" = 240', self.workflow)

    def test_true_water_geometry_and_time_variation(self):
        self.assertIn('PlaneMesh.new()', self.script)
        self.assertIn('ShaderMaterial.new()', self.script)
        self.assertIn('water_phase', self.script)
        self.assertIn('_setup_ocean()', self.script)
        self.assertIn('RenderingServer.frame_post_draw', self.script)

    def test_real_ship_sails_with_cloth_motion_not_a_still(self):
        self.assertIn('_setup_canvas_sails(', self.script)
        self.assertIn('fabric_phase', self.script)
        self.assertIn('SurfaceTool.new()', self.script)

if __name__=='__main__':
    unittest.main()
