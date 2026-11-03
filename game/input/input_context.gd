class_name InputContext
extends RefCounted

## Gameplay input contexts.
##
## The owner of the gameplay state sets the active context explicitly (see
## InputRouter.set_context). Input routing must never be derived from node
## visibility, so this enum is the single source of truth for "what mode are we
## in" as far as input is concerned.

enum Kind {
	BLOCKED,
	DIALOGUE,
	COURT,
	COURT_RECORD,
	INVESTIGATION,
	PROCEDURE,
	EVIDENCE_INSPECTION,
	MENU,
}
