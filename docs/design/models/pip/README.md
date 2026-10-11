# Pip — first 3D companion

`pip.blend` contains an editable procedural reconstruction of the approved glossy Pip concept, with a preview camera and studio lights. The unseen back continues the visible droplet shape. It is a first model for review, not a pixel-identical conversion of the concept image.

## Rebuild

From the repository root, with Blender 5.2 installed:

```bash
blender --background --python scripts/build_pip.py
```

The script writes the Blender source here, exports `Pip.usdz` and `PipStudio.hdr` into the iPhone mascot resources, and renders a transparent `PipPreview` image in the asset catalog. No paid generation service, external model, or MCP connection is required.

The rounded revision is approximately 19,268 triangles and 438 KB. The source uses opaque glossy charcoal and #0097B2 as an sRGB base color, converted to linear shader color. Reflections and lighting change the displayed pixel colors.

## Rounded revision

Pip now has a fuller belly with nearly circular cross sections, a rounded curved head, thicker arms, and shorter attached feet. Eyes and smile follow the front surface instead of sitting on a fixed flat plane. The thicker orbit ring tilts toward the viewer so its front and back read as a continuous loop, with clearance below the smile.

The native renderer uses a closer, elevated three-quarter camera, a key light plus a cool front fill, and broader studio reflections. Today centers the companion without increasing the screen's content height. Existing animation states, speech activity, Reduce Motion, loading fallback, and offscreen teardown remain in place.

## Object hierarchy

- `PipRoot`
  - `Body`: mesh, eyes, smile, and the `LeftArm`/`RightArm` pivots
  - `LeftFoot` and `RightFoot`: foot and leg meshes
  - `Orbit`: separate ring mesh

The app expects the named `Body`, `Orbit`, and `RightArm` nodes. Preserve those names when editing. Export retains separate object transforms and converts the scene to Y-up. The preview source remains in Blender's Z-up space.

Runtime motion is authored in RealityKit rather than baked clips or a skeleton. Idle uses a gentle bob and ring turn; coaching adds a nod and arm gestures; celebration plays a short bounce and lift before settling to idle motion; rest lowers the posture and slows movement. There is no lip sync, fluid simulation, or real fur in this first asset. Atlas and Flex remain subsequent models.

Physical-iPhone appearance, thermal performance, and coexistence with real music/AirPods still need verification.
