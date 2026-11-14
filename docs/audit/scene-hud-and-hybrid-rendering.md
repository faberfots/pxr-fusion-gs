# Scene HUD and hybrid rendering

The 2026-11-13 follow-up adds an original Polygonics-red game HUD, directional Gaussian opacity shadows and an explicit transparent-material bridge to official Godot 4.6.2. The existing atlas, sort, model identities, color settings and camera controller remain their owners. It uses real GDScript, imported GLSL and authored Godot scenes; no engine fork or additional plugin is required.

## Capability status

| Capability | Status | Exact scope |
|---|---|---|
| Transparent mesh/Gaussian depth interleaving | Fully implemented in the participant contract | `GSAlphaMesh3D`, rigid triangle geometry, unshaded StandardMaterial3D Alpha/Mix, albedo texture/color, UVs, vertex colors and culling. Intersecting surfaces exchange order per pixel. |
| Arbitrary transparent custom shaders, refraction and animated geometry | Not yet implemented | Unsupported materials retain ordinary Godot rendering and a support reason; they are never silently replaced. |
| Gaussian shadow casting | Fully implemented in the directional contract | Actual Gaussian covariance/opacity from the existing atlas; per-model casting; transform/visibility invalidation; cached deep opacity maps. |
| Shadow receiving | Fully implemented in the receiver contract | Explicit `GSShadowReceiver3D` on ordinary BaseMaterial3D receivers, plus opt-in receiving on Gaussian models. Original materials and next passes are retained. |
| Additional light types / native mesh shadows onto GS | Not yet implemented | One directional light; no spot/omni lights, engine shadow-map injection or arbitrary vertex-deformation adapters. |
| Orbital HUD and scene-authored controls | Fully implemented | Expand/collapse, title dragging, saved layout, tooltips, original depth-styled SVGs, metallic theme, hover/reveal animation, selection navigator and non-overlapping tool placement. |
| Multi-model transform interaction | Fully implemented | Ctrl-click selection, group move/rotate/scale, one undo transaction per drag, redo/cancel, numeric XYZ translation/rotation/scale and per-row framing. |
| Starting view and camera safety | Fully implemented in the desktop contract | Elevated home view, frame selected/all, sphere sweeps against physical colliders, independent horizontal floor guard, explicit unrestricted flight. Scan imagery itself is not collision geometry. |
| XR multiview / headset qualification | Not yet implemented | Explicitly unsupported; the user has no headset. |

The overall P.3.6 finding remains partially implemented because its historical scope includes arbitrary transparency and XR. The supported transparency and directional-shadow features above are implemented; this report does not relabel unimplemented contracts as complete.

## Using the workspace

Open the PXRFusion medallion to expand the command orbit. Drag its title strip to move it. Choose Import, Scene, Image, Light, Camera, System or Assist; opening a tool collapses the orbit. Scene and inspector panels retain separate responsibilities. System offers quality, diagnostics, layout reset and scene clear. Ctrl+O, the existing file drop path and recent files still append models. The medallion reuses the exact infinite diamond from `assets/logo/PNG_Logo_white.png` through an AtlasTexture, with a white PXR/red Fusion wordmark. Red ornamental accents are shared across the orbit, frames, controls and sliders. Floating panel faces use 33% opacity; text, controls and red borders remain opaque, with text shadows for contrast. Every panel/control hierarchy is in a `.tscn`; scripts only bind behavior or instantiate authored list-item scenes.

Scene navigator uses stable model IDs, full-path tooltips and search. Ctrl-click adds/removes selection. The viewport supports Select/Move/Rotate/Scale and axis handles; 1–4 select modes, Escape cancels, Ctrl+Z undoes and Ctrl+Shift+Z redoes. Numeric inspector edits target the active model. Visibility and deletion retain the existing registry/residency behavior. Image studio keeps the existing presets, source comparison and saved color preferences.

Camera offers Home, Frame selected, Frame all, Protected flight and Orbit. Protection uses the authored ground node as the horizontal floor owner and the configured physics mask for collider sweeps. It is independent of the visible reference grid. Add physical collision proxies where scanned walls need collision; unrestricted flight is an explicit option. It does not infer collision from Gaussian bounding boxes.

## Compact HUD follow-up

The application UI now renders at 67% of its previous size through one `GSUiScale.FACTOR`. This applies to the command orbit, floating panels, scene navigator, assistant, diagnostics, model toolbar, load dialog, status strip and viewport handles. Background opacity remains 33%. Pointer hit areas, saved layout clamping and obstacle avoidance follow the rendered bounds. Preset menus inherit the scale. Native OS file dialogs retain OS scaling. Scene hierarchies and the user's current theme/scene customizations are preserved.

The model-gizmo overlay remains in full viewport coordinates; only handle lengths, drawing and hit areas shrink. Its pivot continues to use the camera projection, and dragging preserves the existing Node3D transform and camera input owners. Panel dragging uses event coordinates rather than polling the desktop cursor, supporting precise movement and deterministic input tests.

## Material integration

Attach `gs_alpha_mesh.gd` to a rigid MeshInstance3D, or instantiate `tests/scenes/hybrid_lab.tscn` as a small example. Set an unshaded StandardMaterial3D with Alpha/Mix. The opt-in participant caches geometry independently from transforms and borrows the existing albedo texture. Skinning, blend shapes, custom shaders, emission/detail/triplanar materials, UV transforms and material effects outside the contract keep their native path. The native draw is hidden only after a complete integrated frame is available; opt-out restores its layers and releases its cache.

Instance `scenes/gs_shadow_receiver.tscn` and assign its receiver. Material overrides and MeshInstance3D surface materials are supported. The helper adds an owned shadow pass and restores the original override on teardown. Custom vertex shaders require a matching receiver adapter. The main reference floor is already connected. Receiver culling follows its native BaseMaterial3D cull mode, including live changes. This prevents the hidden underside of the transparent, depth-write-disabled reference-floor box from adding a second, displaced shadow. Floor thickness and collision stay intact. Explicit double-sided receiving remains opt-in through the material. Baked shadows are part of captured Gaussian radiance; disabling generated shadows or a model's Cast toggle leaves only the capture's own shadows. There is no automatic baked-shadow removal or physical relighting.

Enable Gaussian shadows in Light. Select each model in Scene navigator to set Cast and Receive. Casting defaults on; receiving defaults off to preserve captured radiance. Shadows globally default off for the same reason. Resolution choices are 256, 512 or 1024; strength is live. The opacity shadow uses 16 transmission events per light-space pixel and a 3×3 filter. This is an approximate deep-opacity shadow, not physical relighting of a reconstructed mesh. Bias avoids same-depth self-shadowing; thin geometry and extreme scene scale may need tuning through the lighting resource.

## Ownership and boundaries

| Fact or command | Existing/new owner |
|---|---|
| Model identity, selection, undo transactions | GaussianSplattingViewer |
| Model transform and shadow participation | Each GaussianSplat Node3D |
| Resident Gaussian data and GPU resources | Rasterizer + RenderingContext deletion queue |
| Color settings and presets | Existing config + GSColorSettings |
| Lighting preferences | Viewer-owned GSLightingSettings resource |
| Camera motion and protection | CameraController + GSCameraSafetySettings |
| Serialized UI hierarchy / shared appearance | Authored scenes / ViewerTheme |
| Cloud consent and AI action capability | Existing local AIAccessPolicy |
| Overall P.X.Y status | remediation-status.json; Markdown generated by audit_status.py |

The application remains a local desktop session. RBAC governs AI actions through the existing local capability policy; this is not multi-user authentication. Opening the assistant preserves denied-by-default cloud and action permissions. AI scene context uses renderer capability metadata and does not gain filesystem paths from the new local tooltips.

## Budget and failure behavior

No file-size rejection or import downsampling is added. Residency remains subject to the existing total GPU allocation and contiguous atlas admission. Shadow maps borrow atlas/sort scratch and add two 16-event RG32F caches (64 MiB at 512²), flags and small status/uniform buffers. Transparency reserves a bounded fragment pool from remaining budget, up to eight fragments per output pixel on average, and tracks geometry/targets in the same deletion queue. This is allocation capacity, not a file-size limit.

Projection/fragment overflow preserves the last complete output and reports failure. Initial incomplete alpha frames do not hide the native mesh. Resize rebuilds dependent alpha targets; disabling participants/shadows releases their caches. Quality migration keeps the authoritative atlas checkpoint/rollback path. All new capabilities are optional; scenes without participants and with shadows disabled use the original Gaussian rendering path.

Godot API references: [RenderingDevice](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html), [spatial shader render modes](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html). In particular, Forward+ rejects equal-depth transparent fragments; the receiver overlay uses a small normal offset while keeping depth testing enabled.

## Qualification

Evidence is recorded in the remediation status and `evidence/hud-*` logs/receipts. Tests cover actual GPU pixels, source color, transparent textures, intersecting surfaces, unsupported-material fallback, resizing, resource release, shadow movement/cast/receive toggles, camera floor/collider behavior, UI initialization, rendered layouts and existing regressions. The optimized Windows template also qualifies complete Bali + Suzuki population, independent transforms and actual CPU ML inference. Dataset-derived screenshots remain local build review artifacts; newly authored HUD ornaments have no dependency on the reference game screenshots. The existing Polygonics diamond is reused at the user’s explicit request; historical provenance gaps are not relabelled as resolved.

Follow-up evidence: `evidence/shadow-scale-*` records the transparent closed-floor regression, scaled actual-input/layout checks, existing renderer/transform/lifecycle suites and an optimized real-main startup. The first broad renderer run at 1142x648 exceeded the shadow fixture's deliberately small 160 MiB budget for combined alpha capture; its native-fallback warning and two contract assertions are retained in `shadow-scale-large-fixture-budget.log`. At the fixture's intended 64x64 launch size those checks pass. UI and the dedicated closed-grid regression are separately qualified at their documented larger resolutions; no runtime budget or admission policy was weakened.

## Composition persistence and movable model tools

The 2026-11-14 follow-up adds a saved drag-grip position for the model toolbar and data-only `.pxrscene` compositions. Scene Navigator offers Save Scene; the existing Import picker, file-drop and recent-file paths recognize the new extension. Full per-model world matrices, identities and view settings restore without flattening the original sources. Source fingerprints, atomic file replacement and the existing resident-atlas checkpoint protect fidelity and failure recovery. Operation IO stays independently owned until teardown cancellation drains. See [scene file workflow](../scene-files.md) and `evidence/composition-*` for exact scope and qualification.

## Point placement and main-control drag

The next 2026-11-14 follow-up adds a held-left-click drag directly on the main PXRFusion medallion and a scene-authored placement HUD for individual interactive imports. The viewer owns the single pending model; the existing atlas, registry, world-transform mapping and pick channel stay authoritative. Reference-floor fallback follows the existing non-occluding grid policy, including visible scans below that floor. Exact scope, controls and ownership are documented in [the scene guide](../scene-files.md); `evidence/placement-*` records the checks and separate package.

## Environment import regression

The 2026-11-14 environment follow-up separates object point placement from environment loading. Auto uses the existing per-scan bounds threshold; explicit Object/Environment overrides are scene-authored controls. Environments retain their source pose and enter the established eye-level free-look view using only that environment's samples. Home and Frame selected recover this view. The GS node owns import intent and the existing composition codec persists it as an optional, validated version-one field. Old scene documents retain their exact poses/camera, with no automatic migration or repositioning. Existing local action permissions and atlas admission remain unchanged. See `evidence/environment-*` and the scene guide for qualification and the heuristic's limits.

## Sky3D atmosphere controls

A scene-authored Sky & time tab now shares the existing Light & integration floating panel. Sky3D's own setters remain authoritative; the UI synchronizes external changes without feedback signals. Time presets/manual scrubbing, visibility, animation, light energy, frame exposure, night and celestial-grid controls use one explicit whitelist. Original scene settings remain the reset target. Optional atmosphere/calendar data round-trips through the composition codec while old version-one documents remain compatible. Captured GS lighting remains baked; world/frame exposure and opt-in dynamic shadows have their documented effect. Local controls add no multi-user role or broader AI capability. Tests cover actual scaled pointer input, state restoration, invalid-data rejection and missing-Sky3D fallback.
