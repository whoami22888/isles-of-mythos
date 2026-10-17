import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image

from audition_pinnace_source import (
    SourceError, validate_manifest, inspect_gltf, add_sail_alpha,
    validate_dependency_closure, safe_path, verified_download,
)


class PinnaceSourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manifest = {
            'asset_id': 'ship_pinnace', 'license': 'CC0-1.0',
            'publisher': 'https://polyhaven.com/a/ship_pinnace',
            'status': 'quarantined-for-evaluation',
            'files': [
                {'path': 'ship_pinnace_1k.gltf',
                 'url': 'https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/ship_pinnace/ship_pinnace_1k.gltf',
                 'size': 25, 'md5': '1' * 32},
                {'path': 'ship_pinnace.bin',
                 'url': 'https://dl.polyhaven.org/file/ph-assets/Models/gltf/4k/ship_pinnace/ship_pinnace.bin',
                 'size': 200, 'md5': '2' * 32},
                {'path': 'textures/ship_pinnace_sails_alpha_1k.png',
                 'url': 'https://dl.polyhaven.org/file/ph-assets/Models/png/1k/ship_pinnace/ship_pinnace_sails_alpha_1k.png',
                 'size': 50, 'md5': '3' * 32},
            ],
        }

    def test_exact_publisher_and_valid_source_routes(self):
        validate_manifest(self.manifest)
        for src in ('http://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/ship_pinnace/ship_pinnace_1k.gltf',
                    'https://dl.polyhaven.org.evil.test/file/ph-assets/Models/gltf/1k/ship_pinnace/ship_pinnace_1k.gltf',
                    'https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/dutch_ship_medium/foo.gltf',
                    'https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/ship_pinnace/other.gltf',
                    'https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/ship_pinnace/ship_pinnace_1k.gltf?q=evil'):
            changed = json.loads(json.dumps(self.manifest))
            changed['files'][0]['url'] = src
            with self.subTest(src=src), self.assertRaises(SourceError):
                validate_manifest(changed)

    def test_noncanonical_paths_and_duplicate_paths_rejected(self):
        for wrong in ('../ship.bin', '/absolute.bin', 'textures/../../a.bin', r'textures\\x.jpg'):
            with self.subTest(path=wrong), self.assertRaises(SourceError):
                safe_path(wrong)
        v = json.loads(json.dumps(self.manifest))
        v['files'].append(dict(v['files'][1]))
        with self.assertRaises(SourceError): validate_manifest(v)

    def test_bad_hash_and_unbounded_download_rejected(self):
        for update in ({'md5': 'abc'}, {'sha256': 'not_hash'}, {'size': 0}, {'size': 90000000}):
            v = json.loads(json.dumps(self.manifest))
            v['files'][0].update(update)
            with self.subTest(update=update), self.assertRaises(SourceError):
                validate_manifest(v)

    def test_gltf_requires_high_detail_materials_and_real_sails(self):
        doc = {'nodes':[{'name':f'ship_pinnace_{part}', 'mesh':i} for i,part in enumerate(
            ('aft','rigging','details','hull','deck','interior','sails'))],
            'meshes':[{'primitives':[{'indices':i}]} for i in range(7)],
            'accessors':[{'count':24000} for _ in range(7)],
            'materials':[{'name':f'ship_pinnace_{part}','normalTexture':{'index':i},
                          'pbrMetallicRoughness':{'baseColorTexture':{'index':i},
                          'metallicRoughnessTexture':{'index':i}}}
                         for i,part in enumerate(('aft','rigging','details','hull','deck','interior','sails'))],
            'buffers':[{'uri':'ship_pinnace.bin','byteLength':200}],
            'images':[{'uri':'textures/ship_pinnace_sails_diff_1k.jpg'}],
        }
        doc['materials'][-1]['alphaMode']='MASK'
        stats=inspect_gltf(doc)
        self.assertEqual(stats['triangles'],56000)
        self.assertEqual(stats['skeletal_skins'],0)
        self.assertFalse(stats['animated'])
        for change in ('no_sails','no_normal','fake_motion'):
            v=json.loads(json.dumps(doc))
            if change=='no_sails':v['nodes'].pop()
            if change=='no_normal':v['materials'][0].pop('normalTexture')
            if change=='fake_motion':v['animations']=[{'name':'idle'}]
            with self.subTest(change=change), self.assertRaises(SourceError):inspect_gltf(v)

    def test_rgba_sail_mask_preserves_publisher_alpha(self):
        (self.root/'textures').mkdir()
        model = {'images':[{'uri':'textures/ship_pinnace_sails_diff_1k.jpg'}],
                 'textures':[{'source':0}],
                 'materials':[{'name':'ship_pinnace_sails','alphaMode':'MASK',
                               'pbrMetallicRoughness':{'baseColorTexture':{'index':0}}}]}
        (self.root/'ship_pinnace_1k.gltf').write_text(json.dumps(model))
        Image.new('RGB',(8,8),(200,160,120)).save(self.root/'textures/ship_pinnace_sails_diff_1k.jpg')
        mask=Image.new('L',(8,8),255);mask.putpixel((0,0),0)
        mask.save(self.root/'textures/ship_pinnace_sails_alpha_1k.png')
        receipt=add_sail_alpha(self.root)
        patched=json.loads((self.root/'ship_pinnace_1k.gltf').read_text())
        self.assertEqual(patched['materials'][0]['alphaMode'],'MASK')
        with Image.open(self.root/patched['images'][0]['uri']) as im:
            self.assertEqual(im.mode,'RGBA')
            self.assertEqual(im.getpixel((0,0))[3],0)
            self.assertEqual(im.getpixel((1,1))[3],255)
        self.assertEqual(len(receipt['derived_sha256']),64)

    def test_missing_sail_opacity_not_silently_ignored(self):
        (self.root/'ship_pinnace_1k.gltf').write_text(json.dumps({'images':[],'materials':[]}))
        with self.assertRaises(SourceError): add_sail_alpha(self.root)

    def test_closure_rejects_missing_and_path_escape(self):
        (self.root/'ship_pinnace.bin').write_bytes(b'123')
        doc={'buffers':[{'uri':'ship_pinnace.bin'}],'images':[{'uri':'textures/missing.png'}]}
        with self.assertRaises(SourceError):validate_dependency_closure(doc,self.root)
        doc['images'][0]['uri']='../outside.png'
        with self.assertRaises(SourceError):validate_dependency_closure(doc,self.root)

    def test_verified_download_checks_exact_bytes_and_sha256(self):
        body=b'pinnace source bytes'
        record = dict(self.manifest['files'][0])
        record['size']=len(body)
        record['md5']=hashlib.md5(body).hexdigest()
        record['sha256']=hashlib.sha256(body).hexdigest()
        got=verified_download(record,self.root,fetch=lambda _:body)
        self.assertEqual(got['sha256'],record['sha256'])
        wrong=dict(record,sha256='0'*64)
        with self.assertRaises(SourceError):verified_download(wrong,self.root/'wrong',fetch=lambda _:body)
        with self.assertRaises(SourceError):verified_download(record,self.root/'short',fetch=lambda _:body[:-1])

    def test_admission_remains_false_even_after_source_verification(self):
        self.assertEqual(self.manifest['status'],'quarantined-for-evaluation')

if __name__=='__main__':unittest.main()

class GodotPinnaceCaptureContract(unittest.TestCase):
    def test_render_uses_original_source_sail_mesh_not_flat_panels(self):
        path=Path(__file__).parents[1]/'client-godot/tests/render_pinnace_audition.gd'
        code=path.read_text()
        self.assertIn('ship_pinnace_1k.gltf',code)
        self.assertIn('ship_pinnace_sails',code)
        self.assertIn('_setup_source_sails',code)
        self.assertNotIn('_setup_canvas_sails',code)
        self.assertNotIn('SurfaceTool.new()',code)
    def test_mp4_requires_true_rendered_frames_and_full_reference_duration(self):
        path=Path(__file__).parents[1]/'client-godot/tests/render_pinnace_audition.gd'
        code=path.read_text()
        self.assertIn('const CAPTURE_FRAMES := 240',code)
        self.assertIn('RenderingServer.frame_post_draw',code)
        self.assertIn('get_image()',code)
        wf=(Path(__file__).parents[1]/'.github/workflows/iom-pinnace-source-audition.yml').read_text()
        self.assertIn('-framerate 24',wf)
        self.assertIn('frame_%03d.png',wf)
        self.assertIn('candidate_engine_motion.mp4',wf)
