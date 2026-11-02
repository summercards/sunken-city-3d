extends RefCounted
## Reference-calibrated rest geometry, shared by the visual rig and wrist solver.
## Metres; the CharacterMotor collision contract remains independent.
const HEAD_CENTER := 1.015
const HEAD_SCALE := Vector3(1.247,0.88,1.118)
const SHOULDER_X := 0.162
const SHOULDER_Y := 0.80625
const UPPER_ARM := 0.172
const LOWER_ARM := 0.177375
const HIP_X := 0.084925
const HIP_Y := 0.42
const THIGH := 0.2025
const SHIN := 0.1825
const SHIRT_CENTER := 0.6315625
const SHIRT_HALF := Vector3(0.15,0.1854375,0.1075)
const BAG_SCALE := 0.70

static func shoulder(side: float) -> Vector3: return Vector3(side*SHOULDER_X,SHOULDER_Y,0)
static func rest_hand(side: float) -> Vector3: return Vector3(side*SHOULDER_X,SHOULDER_Y-UPPER_ARM-LOWER_ARM,0.006)
