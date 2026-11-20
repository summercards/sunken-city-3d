

## Mask/capsule diagnostic update

The authoritative static wall layer is `256`; `512` is the actor layer and the CharacterMotor collision mask. The probe now uses ray mask 256 and a real temporary `CharacterBody3D` capsule with actor layer 512/mask 256 for the wall contact. Final isolated evidence:

```text
/Users/zyq/work/sea-work/sunroom-mask-final2-iLgFzH/verification/20261120-113227-verification-a84b97
```

`asset-import` exit 0 and `sunroom-surface-collision` 12/0 exit 0. First-hit diagnostics identify `.../SurfaceCollision`, layer 256 at wall/waist and lateral capsule contact; door samples are limited to the authored opening corridor and pass forward/reverse. This is an actor-wall acceptance only; Boat hull/manual sea and full boarding migration remain unimplemented.

## User-directed model alignment correction

The current segmented boxes remain an authored collision approximation and must not be treated as a final model-aligned result. The next adjustment is to derive the local wall segment extents from the runtime `SunnyBloomVisual` MultiMesh instance metadata and source component bounds, while retaining manually segmented BoxShapes, the door/ladder opening, and the surface-owner transform. Do not convert render meshes to collision and do not use the old WalkArea rectangles for collision calibration. A temporary slope for the formal uphill test will be instantiated only by a test harness and freed before exit; it will not enter `main.tscn` or user placement.

## Model-aligned collision and temporary slope update

The current surface box extents were narrowed using the authored component bounds and `instances.json` transform scales rather than the old WalkArea rectangles: side/front/back segments follow the house/upper-room structural footprint, while the entry/ladder corridor stays open. Final isolated model-aligned run `sea-work/sunroom-model-aligned-ycBMwx/verification/20261120-131412-verification-486458` passed `sunroom-surface-collision` 12/0, `sunroom-runtime` 21/0, `sunroom-repair` 14/0, `ground-space` 37/0 and `interaction-reach` 36/0.

The uphill test reused the existing physical motor fixture (temporary static slope/real CharacterBody3D, freed by the test) rather than adding a ramp to `main.tscn`: `character-motor` 42/0, exit 0 at `sea-work/sunroom-model-aligned-ycBMwx/verification/20261120-131539-verification-e5e6a5`. No permanent slope or placement transform was added.

## Owner-visible temporary slope update

A temporary slope is now instantiated only inside `test_sunroom_surface_collision.gd` after formal Main loads. It uses `scenes/components/minimal_main/ramp.tscn`, is placed under `TemporaryUphillFixture`, and is freed before test exit; no ramp node/resource was added to `main.tscn` or user placement. The final isolated run `sea-work/sunroom-shared-final-KvSTKR/verification/20261120-134748-verification-55bfb7` passed `sunroom-surface-collision` 14/0, including explicit temporary-ramp presence and cleanup. This is a scripted test fixture, not human input evidence.
