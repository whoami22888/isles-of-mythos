extends RefCounted
## Opening story beats: short skippable subtitles plus one journal entry each.
## Text mirrors iom-docs/story_lines_v1.md. "{pet}" is the pup's given name.

const BEATS := {
	"ashore": {
		"title": "Washed Ashore",
		"lines": [["First Mate", "The Sovereign split the Mythos Wake and the UTC warship."], ["First Mate", "Silas! Answer me!"]],
		"journal": "The Abyssal Sovereign broke the Mythos Wake and the UTC warship in one bite. I woke on black sand among the wreckage. The crew are gone. Silas is missing.",
	},
	"cutlass": {
		"title": "Silas's Cutlass",
		"lines": [["First Mate", "Silas's hat is caught in the rigging. He never lost it."], ["First Mate", "His cutlass, too. He'd sooner lose a hand than that blade."], ["Silas (memory)", "\"Keep your blade close, Mate. The sea keeps everything else.\""]],
		"journal": "His hat was caught in the rigging. His cutlass lay in the sand, its grip worn smooth by his hand. No body. No tracks.",
	},
	"gather": {
		"title": "Fire Before Dark",
		"lines": [["First Mate", "Wood. Stone. A fire before dark. That's the order."]],
		"journal": "The wreck gives planks and rope. Palms and stones can give us wood and stone. I need a fire before the cold returns.",
	},
	"pet": {
		"title": "{pet}",
		"lines": [["First Mate", "Easy, little one. Let me see that flipper."], ["First Mate", "There. You're not staying in that wreck."], ["{pet}", "*presses against your boot and gives a thin squeak*"]],
		"journal": "A seal pup was pinned beneath the wreck, one flipper torn. I freed it. It follows close and finds what I miss.",
	},
	"named": {
		"title": "",
		"lines": [["First Mate", "{pet}. Two castaways, then."]],
		"journal": "",
	},
	"storm": {
		"title": "The Storm",
		"lines": [["First Mate", "That same black sky. The night the Sovereign rose."], ["First Mate", "Keep the fire alive. Stay beneath the lean-to."]],
		"journal": "The black storm returned, like the night the Sovereign rose. The fire held. The lean-to gave us a place to endure it.",
	},
	"beast": {
		"title": "Eyes in the Jungle",
		"lines": [["{pet}", "*hackles rise; a low growl cuts through the rain*"], ["First Mate", "{pet} heard it first. Something's in the trees."]],
		"journal": "A sabertooth stepped from the trees at the height of the storm. {pet} heard it before I did.",
	},
	"dawn": {
		"title": "",
		"lines": [["First Mate", "Still here. Both of us."]],
		"journal": "",
	},
	"chest": {
		"title": "Dawn and the Chest",
		"lines": [["First Mate", "The captain's chest. The chart is still inside."], ["First Mate", "Silas's knife-mark. He marked a cove across the strait."], ["First Mate", "He's alive. He has to be."]],
		"journal": "We made it to morning. The captain's chest washed ashore with a chart. Silas marked a cove across the strait.",
	},
	"overlook": {
		"title": "The Overlook",
		"lines": [["First Mate", "Smoke. A survivor camp across the strait."], ["First Mate", "Ruins beyond it. The Sovereign's storm still waits."], ["First Mate", "First the raft. Then the camp. Then Silas."]],
		"journal": "From the ridge I saw smoke from a survivor camp, ruins on the far isles, and the Sovereign's tempest beyond. Next: build a raft and cross.",
	},
}


static func fill(text: String, pet: String) -> String:
	return text.replace("{pet}", pet)
