class_name StoryState
extends RefCounted

enum RuntimeState {
	RUNNING,
	WAIT_DIALOGUE,
	WAIT_CHOICE,
	WAIT_COURT,
	WAIT_INVESTIGATION,
	WAIT_PROCEDURE,
	WAIT_ANIMATION,
	PAUSED,
	FINISHED,
	ERROR,
}

var current_chapter: StringName
var current_scene: StringName
var current_instruction: int = 0
var call_stack: Array[StoryStackFrame]
var runtime_state: RuntimeState = RuntimeState.RUNNING
# Last background requested by the story. Presentation rebuilds from this after
# a load; it is an authored asset ID, never a node property.
var current_background: StringName
