# Mixed mesh and Gaussian scenes

Import **GLB or glTF 2.0** through the existing red Import control, file drop or recent-file list. They share the same scene with Gaussian PLY/GSRES assets. The application runtime uses GDScript and Godot's native glTF importer; Python is used only by development/qualification tools.

## Mutual GS and mesh occlusion

A native GLB model can hide behind a Gaussian-splat tree, wall or other captured feature. Gaussian opacity determines how much of the model remains visible, including exposed parts beside the foreground scan. Opaque native geometry also hides GS behind it. Both directions use the existing renderer's resolved depth and opacity composition in perspective and orthographic views. No conversion of the scan into a triangle mesh is needed. This is an application feature to preserve in future feature documentation; renderer capability metadata exposes both directions to Cortex through the existing scene context.

Visual occlusion and physical collision are separate capabilities. A scanned tree can visually hide a GLB without becoming a physical wall. Scanned surfaces need an explicit mesh proxy for physical navigation.

## Everyday workflow

1. Import an environment. Use **Environment** in the import options, or leave **Automatic** for bounds-based classification. Environments keep their authored origin and skip cursor placement. GS environments retain the existing interior camera-entry calculation. Mesh environments open with a framed overview; use the existing camera controls to navigate inside.
2. Import a model. **Clear scene before importing** remains unchecked by default. Choose **Model** to place it on a visible GS or colliding mesh surface. Click or press Enter to place; Escape cancels. **Keep original** retains its source placement.
3. Left-click the model or choose it in the existing model selector/Scene navigator. One imported GLB/glTF hierarchy is one selectable asset. The same move/rotate/scale gizmo, XYZ numerical fields and undo/redo work for meshes and GS. Ctrl-click adds to a mixed selection. Edits apply to the asset root; its children retain their local transforms. **Solid** defaults on for rigid GLB models and constrains edits against the reference/native floor and other native geometry. Turn it off for deliberate overlaps or unrestricted authoring. Environments remain freely alignable.
4. Use **Lock transform** in Scene navigator to protect a completed placement from numeric/gizmo editing. Visibility, removal, framing, filtering and camera navigation remain in the existing controls. The lock is an editing convenience, not an authenticated security role.
5. Save from Scene navigator. `.pxrscene` retains model identities, exact full transforms, visibility, import kind, locks, selection, camera, sky and existing rendering settings. Opening replaces; the normal unchecked Import adds a composition and remaps duplicate identities.
6. To move a composition to another computer, enable **Include asset files** before saving. Copy the `.pxrscene` and its adjacent `.pxrscene.assets-…` folder together. Linked saving remains the default. Portable saving copies original scans, GLB/glTF, geometry buffers and textures; it does not merge geometry or convert GS into meshes.

During placement, a native model uses temporary instance transparency so it cannot obscure the GS surface being picked underneath its own preview. Confirming restores the original instance transparency; source materials and textures are untouched.

Original files are never overwritten or deleted. Sources and external mesh dependencies are fingerprinted. Missing or changed sources reject saving/opening rather than substituting different content. A failed mixed replacement restores resident GS data and the original native roots; a failed append removes only its newly added assets. A cancelled portable save preserves the previous manifest. Unique asset folders are intentional: an overwritten manifest cannot damage an older bundle. Empty folders may remain after cancellation; old bundles are not automatically pruned.

The first confirmed mesh applies **Soft mesh lighting** when Sky contribution and Ambient energy still have their factory values. This mixes 30% of Sky3D's existing ambient color into native lighting, avoiding black native surfaces in deep city shadows. The existing Sky3D fields remain authoritative; customized contribution/energy values are preserved, cancelled imports do not change lighting, and opening a saved composition restores its exact saved view. **Lighting → Sky & time → Soft mesh lighting** reapplies the preset explicitly. Advanced Sky contribution can restore 100% sky lighting. No material, GS grading value or source radiance is rewritten; automatic exposure can still respond to a changing scene, as before.

The underlying ambient color/sky blend is Godot's existing [Environment lighting control](https://docs.godotengine.org/en/4.6/classes/class_environment.html#class-environment-property-ambient-light-sky-contribution).

Portable glTF needs relative dependency URIs or embedded data. Absolute dependency URIs can be loaded locally but portable saving asks for a GLB or relative glTF export. Remote dependency fetching is unsupported. Copy any whole model folder for a linked glTF with external files.

## Ownership and preserved behavior

| Responsibility | Existing authoritative owner / extension |
|---|---|
| Import routes | ProductionUI and viewer; GLB/glTF adapter joins the current dispatcher |
| Live geometry and transform | GaussianSplat or GSSceneMesh Node3D; native children/materials stay native |
| Selection, stable IDs, undo/redo | GaussianSplattingViewer; the generic asset view references the existing GS residency registry and native roots |
| Gizmo and numeric editing | Existing ModelTransformControls and SceneManagerPanel; no second toolbar or transform store |
| Placement | Existing GSPlacementSession, floor/physics/GPU target resolution and authored PlacementHUD scene |
| GS residency and loading | Existing atlas, GPU decoder, caches and bounded queues; mesh vertices never become splats or consume atlas instance IDs |
| Persistence | Existing protected GSComposition transaction; v2 adds native entries, pure-GS saves remain v1 and both versions reopen |
| Cortex context/actions | Existing stable-ID context and action handlers; the existing local role and explicit action permission apply to native assets too |
| UI | Existing scene-authored Polygonics panels/theme/scale, drag behavior and import-clear default |
| Solid editing | Viewer applies accepted edits during physics; GSMeshEditGuard holds query-only collision helpers, never persistent model poses |
| Moving-shape preparation | Each loaded GSSceneMesh owns one job/cache, shared by editing and Drive |
| Mutual visual occlusion | Existing renderer depth/opacity composition; capability metadata is exposed through the existing Cortex context |

Native parsing and file verification run in an isolated worker. Godot scene generation, collision preparation and attachment run on the main thread. Cancellation discards an unfinished result and joins native work during teardown; it cannot interrupt Godot halfway through a native parse. Closing the viewer completes waiting operations before destroying their owner.

Mesh triangles supply picking, placement and the existing protected-camera collision system. Hidden roots and pending-placement models disable their colliders. Mixed picking combines native geometry hits with the existing visible GS pick and rejects stale camera, lens, viewport or asset revisions. The non-occluding reference grid remains a fallback for placement.

## Solid navigation

### Solid editing without Drive

The model toolbar's **Solid** toggle enables the same physical geometry during ordinary gizmo and numerical edits. Translation sweeps against other imported triangles, including long pointer jumps. Rotation and scale test intermediate compound shapes, stopping before an intersection. Mixed selections use one shared movement fraction, retaining their relative translation. A colliding group rotation/scale step stays at the previous accepted pose to preserve the group's relative transforms. One completed gizmo drag or numerical edit remains one existing undo transaction. Requests run in the physics phase; the Node3D remains the single live pose owner.

The existing model toolbar offers **Fast** (default) and **Detailed** collision quality. Fast calls Godot's native `Mesh.create_convex_shape(true, false)` (QuickHull) separately for each source mesh. It follows the model's mesh parts instead of using a whole-model box. A concavity or opening inside one source mesh can be filled by its convex envelope; choose Detailed when that space matters. Detailed retains the previous native V-HACD settings below. Static meshes still use their original triangles in both modes; their doorways and camera collision are unchanged. This quality choice is explicit and is stored in `.pxrscene` as `view.editing.shape_quality`; older documents default to Fast.

Preparation starts on demand and uses one model-owned worker and a cache for each quality. Completed results are also stored as checksum-verified, object-free geometry in `user://mesh-motion-v2`. Cache identities include the source/dependency fingerprints, engine version, algorithm revision and quality. Unchanged files can reopen without another decomposition, including after restarting the app; a moved/copied identical asset does not depend on its previous absolute path. A missing, truncated or invalid cache regenerates from source. The source model, materials and authored pose are never rewritten. Repeated instances within a job reuse their mesh's shapes. Caching is an optimization, not a required portable resource.

If the first drag ends while preparation is running, its last requested pose completes when ready; Escape cancels the pending drag and restores its exact start pose. Loading GS does not start shape generation. Rotation/scale are checked in bounded steps; very thin features or fine concavities may be approximated. This is collision-aware authoring, without automatic rigid-body pushing.

Solid defaults on in a new viewer. Its setting is stored in `.pxrscene`; older documents default on. Opening/placing with **Keep original**, undo and redo preserve their exact authored matrices, including existing overlaps, rather than silently repairing a composition. An existing below-reference-floor pose can be moved out without an automatic jump. In a native environment, actual triangle floors take precedence over the prototype grid. **Solid off** permits unrestricted model editing. GS transforms retain their existing authoring behavior.

### Drive a model

Import a GLB/glTF room or city as **Environment**, then import the character, vehicle or other rigid asset as **Model**. Place it in a clear space on the environment floor, select it, and open **Camera → Drive selected GLB**. Drive always uses Detailed shapes so the previously supported openings between limbs remain passable. The first uncached Detailed preparation can still take time on a complex asset. Results are reused for subsequent walks, Detailed edits and future app runs. Ordinary imports and GS loading do not run convex decomposition.

| Control | Behavior |
|---|---|
| WASD | Move the model relative to the camera, sliding along solid walls |
| Shift | Move at twice the selected travel speed |
| Space | Jump from a floor; gravity returns the geometry to a solid floor |
| Right mouse drag | Look around the model with the protected follow camera |
| Camera panel speed slider | Adjust travel speed while Drive is active |
| Escape / disable Drive | Return to Edit mode and finish one undoable movement |
| Undo after exiting | Restore the exact pose from before the walk |

The imported Node3D remains the authoritative pose. Drive preserves its rotation and XYZ scale while a temporary CharacterBody3D sweeps compound convex pieces through native collision geometry. It collides with other imported GLBs and the camera's sphere, including a limb touching an obstacle while an opening between limbs stays passable. A rotated, nonuniformly scaled root is baked into the physical pieces rather than applied as a nonuniform physics-body scale. This is solid walking and sliding; it does not simulate pushing other objects or rotate a rigid body through impacts.

Static native assets use their actual rest-mesh **triangles**, preserving doorways and openings. Detailed edits and Drive use Godot's [native convex decomposition](https://docs.godotengine.org/en/4.6/classes/class_meshinstance3d.html#class-meshinstance3d-method-create-multiple-convex-collisions), with up to 16 convex hulls per source mesh and up to 64 vertices per hull, resolution 100000 and max concavity 0.0025. These are geometry-derived approximations, not a single bounding box and not mathematically exact moving concave surfaces. Very fine details may be simplified. The supplied Jesus asset produces 113 Detailed pieces in the qualified Godot build. Native decomposition cannot be interrupted halfway through a mesh. Cancelling Drive releases input/mode ownership immediately and drains the worker at the next mesh boundary; destroying the model must join that operation before freeing its geometry.

When a visible native environment is loaded, its actual floors take precedence over the prototype grid collider, including floors below the reference plane. The camera and model no longer hover on an invisible grid floor inside that environment. A native environment without floor geometry permits falling; assign the Environment role to an asset that contains the intended physical environment. With GS alone, the existing reference floor remains available. GS surfaces are captured visual data and need an explicit mesh proxy for physical walls or uneven floors.

Edit mode retains placement and XYZ gizmo/numeric tools, with Solid on or off as chosen above. Drive temporarily isolates them, respects transform locks, stops on selection change/hide/deletion, releases held input on focus loss, and stops before a scene save/open/append or a new placement. Existing panel/dialog input blockers pause driving; closing a panel does not resume a stale held key. A valid authorized Cortex camera/frame action exits Drive before taking the camera. Denied or malformed actions leave Drive untouched. The resulting pose persists through the existing `.pxrscene` transaction; reopening does not start simulation. Rest-geometry walking and solid edits are unavailable for skinned or blend-shaped models; unrestricted editing remains available. No AI navigation tool, cloud transmission or permission expansion is added.

### Reference grid behind native surfaces

The reference grid remains visible as a background and retains its collider and Gaussian-shadow receiving. Its material and shadow overlay now skip pixels occupied by opaque native geometry, even when a model is below Y=0. This removes the grid-shaped patch inside a GLB silhouette without hiding a model, changing its materials, moving it, or disabling GS/native depth composition. Actual native mesh floors continue to occlude objects geometrically.

### Cyan collision overlay

The reported cyan statue was reproduced with the editor's **Debug → Visible Collision Shapes** enabled. Godot drew the dense generated collision triangles over the original material. Internal imported-mesh and navigation helpers now use transparent debug drawing while retaining active physics and picking. The global debug setting stays unchanged, so other user-authored collision helpers can still be debugged. Restart Play or reload the imported model to create the corrected helpers. Materials, textures and GS colors are preserved.

## Scope and limits

- Runtime imports in this delivery: **GLB/glTF 2.0, Gaussian PLY, GSRES and PXRSCENE**. Other Godot editor formats such as FBX, OBJ, DAE and Blender files are not runtime import adapters in this delivery. Convert them to GLB first.
- Native opaque mesh depth works with GS in front/behind. Materials and textures stay native. Arbitrary shaded glass/refraction does not join the custom GS fragment interleaving pipeline. The supplied city's transparent surface uses Godot's native fallback. Native picking follows triangles, including transparent/cutout surfaces; it does not sample texture alpha. The model selector remains available for objects behind those surfaces. Existing explicit unshaded Alpha/Mix participant support is unchanged.
- Imported cameras do not take over the viewer. Imported lights are disabled so opening an asset cannot silently replace the viewer's lighting; native scene materials still respond to the existing sky/sun controls. Animation autoplay is disabled. Animation editing, deformed/skinned collision and individual submesh selection are outside this delivery; collision/picking use the imported rest geometry.
- Native mesh shadows stay native. The Gaussian shadow contract and opt-in receiving behavior are unchanged; this work does not add native mesh shadows onto GS.
- No artificial source-file-size limit is introduced. The GS budget remains the complete GS allocation budget, excluding Godot/native geometry/textures, driver overhead and CPU memory. Loading still depends on available physical resources. Main-thread scene/collision preparation can pause a frame on complex files; this is not progressive native mesh streaming.
- No new cloud transmission, multi-user authentication or model-transform AI tool is added. Cortex can describe/select/frame the shared scene through its current capabilities and permissions. Existing external audit gaps remain open.

Original mixed-scene qualification is recorded in `audit/mixed-scenes-qualification.json`. The collision/debug-overlay follow-up is recorded in `audit/mesh-navigation-qualification.json`. Solid editing, preserved bidirectional occlusion and the below-grid correction are recorded in `audit/solid-edit-qualification.json`. Fast/Detailed preparation, persistent caching and measured real-truck timings are recorded in `audit/fast-shapes-qualification.json`. Previous qualified apps are retained separately.

## Reproducing checks

```powershell
python tools/run_checks.py --candidate build/mixed-scene-checks --gpu --resolution 1142x648 --script res://tests/mixed_scene_checks.gd
# Add --test-arg PATH_TO_STATUE_GLB --test-arg PATH_TO_CITY_GLB for the supplied real assets.
```

The portable/dependency/rollback fixture is generated by GDScript in an isolated test user directory. Real user GLBs and datasets are not copied into Git or distributed inside the application package.
