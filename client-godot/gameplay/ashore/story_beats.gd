extends RefCounted
## Opening story beats: short skippable subtitles plus one journal entry each.
## Text mirrors iom-docs/story_lines_v1.md. "{pet}" is the pup's given name.

const BEATS := {
	"ashore": {
		"title": "Washed Ashore",
		"lines": [["First Mate", "The Mythos Wake... snapped in two like kindling."], ["First Mate", "Silas? SILAS! ...Only the surf answers."]],
		"journal": "The Abyssal Sovereign broke the Mythos Wake and the UTC warship in one bite. I woke on black sand among the wreckage. No sign of the crew.",
	},
	"cutlass": {
		"title": "Silas's Cutlass",
		"lines": [["First Mate", "Silas's cutlass. He'd sooner lose a hand than this blade."], ["Silas (memory)", "\"Keep your blade close, Mate. The sea keeps everything else.\""], ["First Mate", "No body, no tracks. The tide took him... or he walked."]],
		"journal": "Found Silas's cutlass driven into the sand by the wreck. No body, no tracks. I'm keeping it until I can hand it back.",
	},
	"gather": {
		"title": "Fire Before Dark",
		"lines": [["First Mate", "Wood and stone. Fire before dark, or the cold finishes me."]],
		"journal": "The wreck gives planks and rope; the palms and rocks give wood and stone. Enough for a fire and a lean-to if I'm quick.",
	},
	"pet": {
		"title": "Tide-Puck",
		"lines": [["First Mate", "Easy, little one. That flipper's torn - I've got you."], ["Tide-Puck", "*presses against your leg and squeaks*"]],
		"journal": "Freed a seal pup pinned under the wreck, flipper torn. Named it {pet}. It sniffs out things I'd miss and won't leave my side.",
	},
	"named": {
		"title": "",
		"lines": [["First Mate", "{pet} it is. Two castaways, then."]],
		"journal": "",
	},
	"storm": {
		"title": "The Storm",
		"lines": [["First Mate", "Same black sky as the night the Sovereign rose."], ["First Mate", "Keep the fire fed. Stay under the lean-to."]],
		"journal": "The storm came in black and loud, like the night the Sovereign rose. The fire was all that kept us alive.",
	},
	"beast": {
		"title": "Eyes in the Jungle",
		"lines": [["{pet}", "*hackles up - a low, shaking growl*"], ["First Mate", "Eyes in the treeline. Something big - and it's hungry."]],
		"journal": "A sabertooth came out of the trees at the height of the storm. {pet} heard it before I saw it.",
	},
	"dawn": {
		"title": "",
		"lines": [["First Mate", "Still breathing. Both of us."]],
		"journal": "",
	},
	"chest": {
		"title": "Dawn and the Chest",
		"lines": [["First Mate", "The captain's sea chest! A chart... and Silas's knife-mark on it."], ["First Mate", "He marked a cove across the strait. He's alive. He has to be."]],
		"journal": "We made it to morning. The captain's sea chest washed in with a chart - Silas marked a cove across the strait.",
	},
	"overlook": {
		"title": "The Overlook",
		"lines": [["First Mate", "Smoke across the strait. Survivors."], ["First Mate", "And out past them... the Sovereign's storm. Still waiting."], ["First Mate", "First a raft. Then the camp. Then I find Silas."]],
		"journal": "From the ridge: smoke from a survivor camp across the strait, ruins on the far isles, and the Sovereign's tempest on the horizon. Next: build a raft and cross.",
	},
}


static func fill(text: String, pet: String) -> String:
	return text.replace("{pet}", pet)
