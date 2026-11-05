extends RefCounted
## Reference-calibrated rest geometry, shared by the visual rig and wrist solver.
## Metres; the CharacterMotor collision capsule follows SCALE below.
##
## SCALE is the single knob for overall character size. Length constants that are
## consumed in body-pivot space (skeleton joints, proportions) already include it.
## The constants consumed inside a locally scaled child (head, torso) stay at
## reference size, because that child multiplies them by SCALE itself.
const SCALE := 1.5
const HEAD_CENTER := 1.015*SCALE
const HEAD_SCALE := Vector3(1.247,0.88,1.118)
const SHOULDER_X := 0.162*SCALE
const SHOULDER_Y := 0.80625*SCALE
const UPPER_ARM := 0.172*SCALE
const LOWER_ARM := 0.177375*SCALE
const HIP_X := 0.084925*SCALE
const HIP_Y := 0.42*SCALE
const THIGH := 0.2025*SCALE
const SHIN := 0.1825*SCALE
const SHIRT_CENTER := 0.6315625
const SHIRT_HALF := Vector3(0.15,0.1854375,0.1075)
const BAG_SCALE := 0.70*SCALE
## Gameplay envelope, deliberately NOT scaled with the visual body.
##
## CharacterMotor's capsule and GroundSpace's navmesh agent radius must agree, so
## both read it here. Scaling it with SCALE (0.33/1.95) made the navmesh carve the
## 木桥 and several narrow docks away: the walk from the landing to the farm box no
## longer completed (test_surface_movement「木桥连接可达」). Walkable reach is a
## gameplay contract, so the envelope stays at its authored reference size and only
## the visual body grows; the proxy is a soft skin, and slight visual overlap at a
## wall is preferable to losing a route.
const BODY_RADIUS := 0.22
const BODY_HEIGHT := 1.30
## Height the follow camera aims at. Authored against the reference body (0.7 of
## 1.26m hair top) and scaled with the visual body, otherwise the enlarged head
## drifts toward the top of the frame.
const CAMERA_FOCUS := 0.7*SCALE

static func shoulder(side: float) -> Vector3: return Vector3(side*SHOULDER_X,SHOULDER_Y,0)
static func rest_hand(side: float) -> Vector3: return Vector3(side*SHOULDER_X,SHOULDER_Y-UPPER_ARM-LOWER_ARM,0.006*SCALE)
