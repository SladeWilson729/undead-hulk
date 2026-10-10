class_name KillCause
extends RefCounted
## How a soldier died. Every kill() / pin_to() passes one, so the run summary can say
## "Smashed: 30, Eaten: 4, Crushed: 10" and the score can reward style.
## Use as KillCause.SMASHED etc.

enum {
	UNKNOWN,
	SMASHED,        # Punched.
	STOMPED,        # Ground pound.
	EATEN,          # Grabbed and eaten.
	CRUSHED,        # Hit by, or pinned to and crushed by, a thrown car; flattened by a flying can or cart.
	BURIED,         # Flying rubble from a smashed pillar.
	FRIENDLY_FIRE,  # Caught in his own side's rocket blast.
	FELL,           # Knocked off the level.
	GLITTER_BOMBED, # Hit by a flying body with the Glitter Bomb augment.
	TACKLED,        # Run down by the Foolsball Helmet charge.
	YEETED,         # Grabbed and thrown, or hit by a thrown soldier.
	BLOWN_UP,       # Caught in a fuel barrel the Hulk set off.
}

## Summary-screen names, in the order the summary lists them.
const LABELS := {
	SMASHED: "Smashed",
	STOMPED: "Stomped",
	TACKLED: "Tackled",
	YEETED: "Yeeted",
	BLOWN_UP: "Blown Up",
	EATEN: "Eaten",
	CRUSHED: "Crushed",
	BURIED: "Buried",
	FRIENDLY_FIRE: "Friendly Fire",
	FELL: "Fell",
	GLITTER_BOMBED: "Glitter Bombed",
	UNKNOWN: "Other",
}


static func label(cause: int) -> String:
	return LABELS.get(cause, "Other")
