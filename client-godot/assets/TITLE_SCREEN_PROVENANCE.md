# Title-screen asset provenance

These files back the Godot 4.7.2 boot title card. They are not engine-integrated 3D world art and are not an admission of the cinematic quality floor. SHA-256 is of the bytes committed in this tree.

## User-supplied concept video

Both clips were attached by the project owner for this title screen. They are AI-made concept plates (Theora + Vorbis), not a third-party marketplace download and not a substitute for a Godot-rendered world capture.

| File | Role | Technical | SHA-256 |
| --- | --- | --- | --- |
| `client-godot/assets/video/intro_cinematic.ogv` | Opening cinematic, played with its own audio | 1280×720, 24 fps, 10.01 s, Theora + Vorbis 48 kHz stereo | `9fdea43ac38e30fd82b494653e448f53c86cea127c3830ef6f89264fe421bfd5` |
| `client-godot/assets/video/title_loop.ogv` | Looping title background, muted in the client | 1280×720, 24 fps, 12.03 s, Theora + Vorbis 24 kHz mono | `1ce3ec058e9cc70f552e867578d23b208527749da1dffb0744315972d0cdd69f` |

- Origin: owner task attachment (`intro_cinematic.ogv`, `title_loop.ogv`)
- Author: owner-supplied AI concept media
- Acquisition: copied from the task upload into `client-godot/assets/video/`
- License: supplied by the owner for the Isles of Mythos title screen. No separate marketplace license was attached. Do not treat these clips as redistributable stock or as accepted premium 3D scenery.
- Godot import: `VideoStreamTheora` (`.ogv`), played by `VideoStreamPlayer` in `scenes/boot.tscn` via `scripts/boot.gd`

## Fonts (SIL Open Font License 1.1)

| File | Source | Author / reserved name | SHA-256 |
| --- | --- | --- | --- |
| `client-godot/assets/fonts/PirataOne-Regular.ttf` | https://github.com/google/fonts/raw/main/ofl/pirataone/PirataOne-Regular.ttf | Rodrigo Fuenzalida, Nicolas Massi, 2012. Reserved Font Name "Pirata". Specimen: https://fonts.google.com/specimen/Pirata+One | `5347a2e155589ecf667d4b766613c8ee003edde9f83717fd24c09599a4b1ecc0` |
| `client-godot/assets/fonts/OFL-PirataOne.txt` | https://github.com/google/fonts/raw/main/ofl/pirataone/OFL.txt | SIL Open Font License 1.1 | `e8ad3f3de5baeff6bac6e711d8c406e0a6b8a61d2944741532d8965d893a2681` |
| `client-godot/assets/fonts/IMFeENrm28P.ttf` | https://github.com/google/fonts/raw/main/ofl/imfellenglish/IMFeENrm28P.ttf | Igino Marini, 2007. Reserved Font Name "IM FELL English". Specimen: https://fonts.google.com/specimen/IM+Fell+English | `fe9705bbde51af802719246d4608d08d37bde956ab99d9a590da996a5221a24c` |
| `client-godot/assets/fonts/OFL-IMFell.txt` | https://github.com/google/fonts/raw/main/ofl/imfellenglish/OFL.txt | SIL Open Font License 1.1 | `2a3ca501fc4d5efcad9798531e3e06962b1e20c60e464f6cbd6c17630112c773` |

License text is committed beside each font. OFL-1.1 allows commercial embedding. The reserved names were not changed. Pirata One is the carved title and the "TAP TO SET SAIL" prompt. IM Fell English is the login-panel text so account fields stay readable.

## Original audio (CC0-1.0)

No Kenney, OpenGameArt, or Sonniss file was downloaded for this screen. The hit and the music bed were synthesized by `client-godot/assets/audio/synthesize_title_audio.py` and are dedicated to the public domain under [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/).

| File | Role | SHA-256 |
| --- | --- | --- |
| `client-godot/assets/audio/cannon_boom.wav` | Layered cannon hit: falling sine thump, sub sine, a 28 ms second layer, low-passed noise, a short crack, and a tail. 44.1 kHz mono, 1.75 s | `2c9e23e2515a89340da4aad7eb1cfbf5ccf39deb4f6c631abe7a6ace4f5935d5` |
| `client-godot/assets/audio/shanty_bed.wav` | 8-bar D-dorian hornpipe at 120 BPM (melody, harmony, bass, kick, snare, hat), looped. 22.05 kHz mono, 16 s | `cba1066c35a01cfc88c55e2d97885c3d28869ba9b7e3907b58af5d3930b43aea` |

Playback uses Godot's Master bus at or below 0 dB so the phone media volume still applies. The title loop's own Vorbis track stays muted. The on-screen Sound control silences the intro, the hit, and the bed without muting the later gameplay scene.
