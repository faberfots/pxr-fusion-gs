# Godot transform handles in the running application

The app now uses [Gizmo3D](https://github.com/chrisizeful/Gizmo3D), a GDScript port of Godot's editor transform gizmo, rather than the previous screen-drawn approximation. The editor's C++ viewport tool itself is editor-only; this port provides its 3D geometry and ray/plane interaction inside the app and exported templates. It is pinned at `f364d87912482a0ce81a9467c0f3c5e3c82dd385`, with the MIT and Godot notices retained under `addons/Gizmo3DScript`.

## Controls

Selecting a loaded GS or GLB/glTF shows the combined gizmo by default.

**Workspace settings → Gizmo** expands scene-authored Appearance, Snapping and Advanced tabs. Godot Classic preserves the original defaults; Minimal reduces visual clutter; High Visibility enlarges handles and shows the real selection outline. Edits become Custom and save locally in `user://gizmo-preferences.cfg`. Reset restores all Classic values. The controller and UI share one validated `GSGizmoPreferences` owner. Changes safely cancel an active drag; they never change the model's locked state, scene transforms or AI action policy.

Appearance offers size, opacity, X/Y/Z and outline colours, the real combined GS/GLB selection bounds, extended guides while dragging, plane handles, rotation line and angle arc. Snapping intervals use scene units, degrees and scale fraction (`0.25` = 25%). Advanced masks choose available axes per tool; plane handles require both in-plane axes, and free movement/uniform scale require all three axes. Hidden planes are not clickable. These are editing preferences, not additional security permissions.

| Control | Result |
|---|---|
| **5 / XYZ** | Combined translation arrows, rotation rings and scale cubes |
| **1 / Select** | Select objects with no visible transform handles |
| **2 / Move** | Axis arrows, XY/XZ/YZ plane handles and a free screen-plane center handle |
| **3 / Rotate** | Rotation rings in their actual 3D planes |
| **4 / Scale** | Axis/plane scaling; the center cube scales uniformly |
| **Local** off/on | World axes / axes following the active model's orientation |
| Hold **Ctrl** | Native translation, rotation and scale snapping |
| Hold **Shift** with snapping | Finer snapping intervals |
| **Esc** or right-click during a drag | Cancel and restore the exact original matrices |
| **Ctrl+Z / Ctrl+Shift+Z** | Existing transform undo / redo |

The toolbar remains movable, uses the existing Polygonics theme and shared UI scale, and retains model selection, Fast/Detailed Solid policy and framing. Focus loss and selection changes cancel the active drag. Locks apply to every selected member. Multiple selected assets receive one shared transform, retaining the existing collision and undo rules.

A real 3D axis pointing directly into the camera projects to the center, rather than being replaced with an invented screen direction. Orbit the view or use a visible plane/axis. Drag scaling stays positive to avoid sweeping collision shapes through a singular zero scale; loading, undo and scene save still preserve authored matrices, including mirrors.

## Ownership and performance

`ModelTransformControls.gd` retains the existing transaction, temporary snapshots and input ownership. `RuntimeGizmoBridge.gd` redirects the port's candidate transform to `GaussianSplattingViewer.apply_asset_edits`; it never writes a model independently. The existing viewer remains responsible for locks, Solid constraints, group acceptance and undo. The imported Node3D remains the authoritative pose. A temporary proxy holds only the gizmo's proposed/accepted visual frame.

`RuntimeTransformGizmo.tscn` authors the overlay, camera, draw surface and center handles. Its own transparent World3D prevents gizmo geometry from entering GS/native depth composition, model picking, physical collision or Gaussian shadows. Existing scene-only captures hide this UI with the other overlays. The camera lens and pose follow the active scene camera, and updates occur after normal scene processing. The overlay requests one redraw on changes and is explicitly disabled after that frame. An unchanged gizmo starts no continuous second 3D render pass. Selecting/viewing a model starts no collision preparation; the existing shape owner prepares geometry when an edit actually needs it.

No new AI action, provider transmission or authentication role is introduced. Existing local transform locks and AI action permissions keep their original owners. GS buffers, residency budgets, atlas population, file-size policy and transform serialization are unchanged by the gizmo.

## Integration and qualification

The application instantiates the authored scene directly; enabling an editor registration plugin is unnecessary. `addons/Gizmo3DScript/UPSTREAM.json` records original source hashes and the local changes: an authored draw surface, reference-counted temporary data, and Godot's original arrow proportions. The transform mathematics and geometry remain the pinned port, with the app bridge retaining existing uniform/free movement gestures and positive scaling.

Customization additionally corrects upstream live colour/opacity setter ordering and keeps plane rendering and hit tests consistent with visibility and in-plane axis masks. The bridge supplies actual viewer-owned asset bounds to the isolated outline. Appearance changes invalidate the cached overlay once; unchanged idle frames retain redraw suppression. Credits and licensing are described in [the attribution policy](ATTRIBUTION.md).

The Godot 4.7 follow-up also corrected an existing standalone GPU-cache hash binding: the shader declares two uints (8 bytes), while the caller supplied 16. Binding the declared 8 bytes restores GPU hashing without changing the cache format, decoder mathematics, data layout or allocation budget.

Godot 4.7 also introduces a native `VirtualJoystick` class. The unused legacy add-on declaring the same global class is excluded from the export preset and isolated package staging, because an export filter alone leaves its entry in the generated class cache. Its repository source remains available for older projects; the user's newer `virtual_joystick_DX` add-on is unchanged.

Local checks, rendered previews, engine/template identity, preserved user changes and exact qualification boundaries are recorded in `audit/native-gizmo-qualification.json`. Earlier 4.6 qualification remains historical evidence; this follow-up uses the user's installed 4.7.2 engine and its matching official Windows release template.

The optimized Windows candidate retains all **7,959,786** Gaussians from Bali and Suzuki alongside the real Jesus and city GLBs, and passes mixed scene save/reopen, shadows, transparent participants, Solid editing, Drive and native prompt-conditioned segmentation. Its measured `load_ms` is a local cache-available qualification observation, not a cold-load benchmark or cross-machine speed promise. The actual `main.tscn` export starts successfully. The original portable releases remain available; these are separate verification candidates.
