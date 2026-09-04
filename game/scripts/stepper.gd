class_name Stepper
extends RefCounted
## Stair climbing for CharacterBody3D — shared by the player and creatures.
##
## move_and_slide() climbs slopes up to floor_max_angle but has no notion of a
## step: a stair riser is a vertical face, so the capsule catches on every
## tread and WoW's real stair geometry feels like a wall. After a body's own
## move_and_slide(), if it is grounded, pushing into a wall, and the wall is no
## taller than STEP_H, this lifts it over: rise, re-try the denied forward
## motion, then settle back onto the tread. Nothing happens for real walls
## (blocked even from above), ledges (nothing to land on), or steep landings.
## The net effect is that stairs play like a ramp.

const STEP_H := 0.45          # tallest riser climbed; WoW stairs are ~0.3-0.4
const SNAP := 0.5             # floor snap so descending stairs doesn't launch
# The landing must be something the body could already walk on. WoW stair
# collision is the render mesh, and its triangulated step corners read as
# ~50° slopes, so a tighter threshold than the body's own floor_max_angle
# rejected every real tread (measured: landing normal y=0.64 on the
# Shadowfang entrance stairs, wall normal y=0.31).


static func climb(body: CharacterBody3D, wish: Vector3, dt: float) -> void:
	## wish: the horizontal velocity the body was trying to move with (not
	## the post-slide velocity, which the wall has already zeroed).
	body.floor_snap_length = SNAP
	if wish.length_squared() < 1e-4 or not body.is_on_wall():
		return
	var up := Vector3.UP * STEP_H
	var from := body.global_transform
	if body.test_move(from, up):
		return                          # headroom blocked: not a step
	var raised := from.translated(up)
	var fwd := wish * dt
	if body.test_move(raised, fwd):
		return                          # still blocked from above: a real wall
	var over := raised.translated(fwd)
	var col := KinematicCollision3D.new()
	if not body.test_move(over, -up * 1.05, col):
		return                          # nothing to land on: a ledge, leave it
	if col.get_normal().y < cos(body.floor_max_angle):
		return                          # steeper than the body can stand on
	# Commit only the rise. Placing the body at the forward landing point
	# left it touching the slope, and the next slide pushed it back out —
	# it oscillated and never crossed. Lifting to tread height and letting
	# the following move_and_slide carry it over the lip is stable.
	var rise := STEP_H - col.get_travel().length()
	if rise < 0.02:
		return                          # already level with it: nothing to climb
	body.global_position.y += rise + 0.01
	body.velocity.y = 0.0
