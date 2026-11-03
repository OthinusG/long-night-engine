class_name PenaltySystem
extends RefCounted


static func apply(state: CourtState, amount: int) -> int:
	assert(state != null, "CourtState is required")
	assert(amount >= 0, "Penalty amount cannot be negative")
	state.penalty = clampi(state.penalty - amount, 0, CourtState.DEFAULT_PENALTY)
	return state.penalty
