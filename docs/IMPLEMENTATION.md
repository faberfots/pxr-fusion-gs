# Implementation and qualification

## Ownership and contracts

| Owner | Responsibility |
|---|---|
| GaussianSplattingViewer | Model registry, stable model IDs, selection, admission, lifecycle state and batch outcomes |
| GSStateMachine | Valid lifecycle transitions; the viewer exposes its state rather than maintaining another state field |
| GSLoadJob | Pure CPU decoding, four-chunk backpressure, cancellation and joined worker lifetime |
| PLYDocument | Bounded header/row reading, scalar types, byte order and property mapping for both pipelines |
| GaussianSplatResource | Versioned binary layout and checksum |
| GSAtlasMigration | Verified chunked atlas checkpoint and restore; the viewer owns commit/rollback and model identities |
| SpatialProcessingJob | Private worker-owned preparation, index and graph compute; CPU-only publication after GPU teardown |
| GaussianSplattingRasterizer / RenderingContext | Rendering-thread device operations, complete storage plan, shaders, palette and teardown |
| CameraController | Active camera and independently named movement blockers |
| AIAccessPolicy | Local session cloud consent and analyst/operator action capabilities |
| SceneContext | JSON snapshot from viewer and registered spatial providers |
| PointCloudResource | Authoritative geometry, revision, bounds and invalidation of derived graph/index data |
| SpatialPipeline / SpatialIndex / SpatialGraph | Optional point-cloud ingestion, exact queries and geometric graph hypotheses |

A model's source coordinates remain unchanged. `GaussianSplattingConfig.source_basis()` owns the source-to-Godot rotation. World bounds use that basis and the node transform exactly once. SH view directions are transformed back into local coordinates. SpatialOS uses the same basis for recognized Gaussian schemas; filenames do not determine coordinates.

The GPU record is 240 bytes: position/time, six covariance scalars, opacity, instance identity and 48 interleaved RGB SH scalars. PLY supports complete SH degrees 0–3. Integer RGB values use their declared scalar range; floating RGB values use 0–1.

GSRES version 2 uses a 128-byte header, magic/version/stride, 64-bit count, raw-local AABB and a SHA-256 payload digest. Packed data is activated only after the complete load succeeds.

Sorting uses a stable eight-pass radix sort over a 32-bit float depth word and a full 32-bit tile word. Metadata and histograms are sized from actual capacity. Projection reserves complete tile footprints atomically and reports overflow instead of writing beyond capacity. A failed frame preserves the previous complete image.

Compute colors are linear premultiplied RGBA. The display shader recovers straight RGB once and Godot applies scene tone mapping. A PRE_TRANSPARENT compositor supplies resolved opaque depth. The implemented transparency/shadow contract is documented in `scene-hud-and-hybrid-rendering.md`; arbitrary shaded transparency and XR multiview remain outside it. Runtime GLB/glTF scene roots now supply native geometry and collision through the existing viewer workflows; see `MIXED_SCENES.md`.

Selection is owned by the viewer. UI and AI use stable model IDs for GS and native mesh roots; selection is indicated by the shared model toolbar and transform handles without tinting radiance. The existing GS-specific snapshot/access APIs remain compatible, and generic asset APIs extend those references to native scenes. AI output is untrusted: tool schemas are advertised only for an allowed role, and arguments and permissions are checked again before mutation. The policy applies to a local desktop session; a future multi-user service must supply authenticated roles.

## Checks

All generated data and user history live in a disposable project with a separate application name.

```powershell
python tools/run_checks.py --godot C:/path/to/Godot_console.exe
python tools/run_checks.py --godot C:/path/to/Godot_console.exe --gpu --script res://tests/gpu_checks.gd
python tools/run_checks.py --godot C:/path/to/Godot_console.exe --gpu --script res://tests/lifecycle_checks.gd
python tools/run_checks.py --godot C:/path/to/Godot_console.exe --gpu --script res://tests/rendering_checks.gd
python tools/run_checks.py --godot C:/path/to/Godot_console.exe --gpu --script res://tests/spatial_checks.gd
python tools/audit_status.py --check
```

Use `--candidate PATH --skip-import` to reuse an already imported isolated candidate after source synchronization. The runner treats script/runtime errors as failures even when Godot exits zero. GPU checks require a compute-capable Vulkan device; software Vulkan qualification is a separate CI scope. `tools/check_provider_network.py --godot PATH --project IMPORTED_CANDIDATE` exercises actual Godot HTTP requests against a localhost synthetic server. It never uses provider credentials or scene data.

Local checks cover allocator reuse, malformed input, mixed scalar big-endian decoding, GSRES corruption, worker cancellation, policy denial, provider parsing, geometry invalidation, initialization/reset, queued loads, deletion, resize, camera ownership, stable selection, sort partitions, wide tile IDs, overflow, compositing, pixel termination, opaque depth and spatial components.

The native crate supports `cargo check --locked`, `cargo test --locked` and `cargo build --locked`. Preprocessing tests confirm pixel-dependent tensors and aspect-ratio padding. Actual native inference additionally runs the qualified official MobileSAM encoder/decoder through GDScript against a deterministic two-object RGB fixture. The source-free package passes the same mask-quality and prompt-selection tests.

The export preset is versioned. Raw PLY, GSRES and ONNX files outside the excluded private resources folder are included explicitly. PCK validation runs the GPU suite with only packaged resources and required native add-on binaries, without raw GLSL files. A PCK must be distributed with its external GDExtension libraries. `tools/package_candidate.py --godot PATH --output DEDICATED_DIRECTORY --engine OFFICIAL_WINDOWS_EXE` creates an unsigned development candidate with external libraries, notices and an artifact hash receipt. It exports from a separate source directory and retains export diagnostics. The default candidate uses the ordinary Godot executable; --engine-kind release-template records an official optimized-template executable. Optimized Windows startup and GPU/native qualification now pass; signing and additional physical platforms remain unqualified. The repository CI covers Linux source/software-Vulkan checks and a Windows native build/inference job; consult the verification record for actual results.

## Evidence and limits

The SSOT for each audit finding, local evidence and remaining work is `docs/audit/remediation-status.json`. A finding is fully implemented only when its relevant local checks pass. Cross-platform support is not inferred from local results.

SpatialOS loading is bounded and cancellable. Progressive visualization is prepared before chunks arrive and yields during final instance population. Geometry preparation, dense-grid prefix scanning, index creation and analysis execute in a private worker with its own local RenderingDevice. No device/RID crosses the publication boundary; the published exact spatial index retains CPU query data. Graph/geometry results commit only against the matching geometry revision. The full 2-million-point ingest/visualization test passed with a maximum observed UI frame gap of 98 ms on the qualified local device. This is a local observation, not a universal frame-time guarantee.

Geometric labels and support relationships are hypotheses, not calibrated recognition or verified physical contact. Missing normals remain unknown. Cloud provider compatibility has fixture coverage; live provider execution requires credentials and explicit cloud consent.

No previously published release was replaced or deployed. Source was backed up before remediation. The workspace arrived without Git history. A new private repository preserves the sanitized qualified Bali baseline and subsequent remediation commits; earlier upstream history cannot be reconstructed from the snapshot.

## Large scenes and per-model transforms

Source-file byte size is not a loading limit. The shared atlas admits loaded and queued populations together, while each GaussianSplat owns its Transform3D and palette identity. Legacy file-size parameters are accepted for compatibility and ignored. Source data is streamed through the bounded worker queue. Valid very thin Gaussians are preserved; only float32 covariance representability is constrained.

The High preset uses a 4 GiB complete GPU allocation ceiling and reserves fewer speculative tile pairs per atlas splat, retaining enough full-resolution atlas space for Bali and a second model. This changes scratch reservation, not SH degree or source population.

Perspective covariance uses a bounded off-axis linearization while retaining the true projected mean for footprint culling. Without this guard, near-plane Gaussians far outside the view can expand across the image and obscure an otherwise valid full scene. Pair admission uses one bounded reservation per workgroup to avoid per-Gaussian compare/exchange contention.

The main scene's prototype grid is a reference background: it draws before Gaussian presentation and does not write opaque depth. Ordinary opaque Godot geometry still occludes Gaussians through the compositor. This preserves the original grid behaviour without disabling scene-depth integration.

## Populated atlas transactions

Changing a GPU layout now queues until an active loading batch completes. Before releasing any working residency, the viewer checks the requested capacity and creates a chunked async GPU checkpoint, writes per-model SHA-256 values and verifies the complete checkpoint. A frozen rendered frame and progress indicator remain visible while GPU allocations are replaced within the configured budget. Stable model IDs, selection, source radiance/geometry, visibility and node Transform3D values survive migration; internal palette IDs/offsets may compact. New loading is deferred during the transaction. Clear/deletion requests are handled without dropping unrelated models.

A failed replacement initialization rolls back to the previous layout using the verified checkpoint. If GPU recovery itself fails, the checkpoint is retained and its path is reported. Disk-full/read/capacity errors leave the existing atlas intact. The full Bali + Suzuki test retained 7,959,786 splats without downsampling and migrated in 16.809 seconds locally; chunked fault-injection tests also cover rollback and deletion during migration.

## Native artifact ownership

`rust/spatial_ml/models/manifest.json` owns model/runtime paths and SHA-256 values. Source/export receipts and the official model license live beside the ONNX models. The setup tool verifies the official runtime archive and installs its notices. The GDScript bridge verifies and materializes packaged artifacts to a local cache before native loading; runtime telemetry is disabled. Windows x86_64 CPU is the qualified native target. Restart Godot to activate a newly installed nonreloadable native DLL.

## Software Vulkan qualification

Linux CI qualifies Mesa llvmpipe with MSAA disabled and adds an opaque-depth check with native 4x MSAA. On Godot 4.6.2 the requested 2x/8x modes fail on llvmpipe; the viewer negotiates its qualified native 4x mode in that case. Disabled AA, hardware GPU modes and project settings are preserved. No additional atlas/render-target allocation is introduced by that workaround. Supported alpha participants and directional Gaussian shadows have separate fixtures; arbitrary transparent shaders and XR remain outside the implemented contract.

The release preset keeps ImGui enabled because the viewer panel depends on its native class. The portable helper canonicalizes its scene-path autoload before a fresh import and rejects unexpected export errors. The camera add-on now creates visualization nodes only inside its ready-owned path, removing the reproduced detached-constructor/export RID leak. Packaging rejects all export errors and ObjectDB leak reports. The normal color panel waits for viewer readiness; startup tests no longer inject a configuration before main-scene initialization.

## Color and direct manipulation

GaussianSplattingConfig owns all live post-processing values. GSColorSettings owns only preset definitions and the validated preference codec. GSColorAdjustmentPanel edits that configuration, saves only color fields to user://gs-color-settings.cfg and provides a reversible neutral comparison. An edited grade survives quality changes. Color-only configuration changes update material uniforms without resetting live renderer controls, camera FOV, atlas resources or model poses.

The former selection highlight blended 25 percent blue into every selected splat. Scene Manager selected the first loaded model automatically; earlier screenshot qualification explicitly cleared selection and missed the user's normal selected appearance. The regression test now fails on the old shader and passes on the corrected one. Selection uses the existing stable model ID; visible-pixel picking supplies the contributing palette identity without physics bounding boxes.

GSModelTransformControls writes the selected Node3D global_transform directly. Its drag snapshot is temporary undo state. The viewer maps renderer basis/scale overrides, and existing Scene Manager controls read the same selected node. Camera movement has a named model_transform blocker. Cancellation restores the original matrix and releases that blocker. Pointer events are consumed only by active handles, and camera navigation continues elsewhere.

## Optimized Windows release qualification

Native mixed-scene collision follows the existing pose/selection owners. GSSceneMesh supplies exact rest triangles for static picking, placement and camera collision. Optional GSModelNavigation prepares compound convex pieces on demand, then uses CharacterBody3D walking against those triangles, a reference floor where applicable, and the physical camera volume. The temporary physics body never becomes a second persistent transform store. Drive exits through the same viewer transform-undo transaction and stops before composition transactions. A visible native environment supplies the physical floor in place of the prototype reference plane. Generated debug collision drawing is transparent, preserving imported materials when Visible Collision Shapes is enabled. Usage, ownership and approximation limits: [mixed scenes](MIXED_SCENES.md#solid-navigation).

Ordinary native model editing now defaults to Solid. The same scene-authored gizmo and numerical controls submit desired poses to the viewer; compound-shape sweeps and bounded rotation/scale overlap checks run during physics. GSMeshEditGuard owns only temporary query bodies, and GSSceneMesh owns the one on-demand shape job/cache shared with Drive. A shared accepted fraction preserves mixed-selection translation. Solid off retains unrestricted authoring, including exact affine endpoints; scene restore/undo retain authored matrices. The optional `.pxrscene` view.editing.solid_meshes field persists the policy and defaults on for older documents. The reference-grid shader and its explicit Gaussian-shadow adapter skip native opaque pixels, preserving geometry below the reference plane and the existing mutual GS/mesh occlusion contract. Native placement previews use reversible instance transparency to avoid self-occluding their GS target. No GS atlas, decoder, splat shader or loading budget is changed.

The official Godot 4.6.2 Windows x86_64 optimized release template now starts the real application and passes a separate source-free qualification scene with full Bali + Suzuki, independent model transforms and native ML initialization. tools/qualify_release.py exports that separate scene because official templates disable --script/--path overrides. tools/check_packaged_startup.py checks the actual main entry point. Package receipts identify entry point, engine kind and executable SHA-256. The ordinary-engine development package is retained. Current limits are unsigned Windows delivery and unqualified additional physical GPUs/OS/XR targets; see the audit SSOT for each remaining gap.

Solid editing now defaults to native QuickHull per source mesh (`create_convex_shape(true, false)`). The scene-authored Fast/Detailed selector edits the viewer's single quality policy; `.pxrscene` saves that policy. Drive explicitly retains Detailed geometry for existing passable concavities. GSSceneMesh owns one worker and prepared sets per quality; GSMeshMotionJob uses the unchanged Detailed settings, deduplicates repeated mesh resources and atomically caches plain shape points/local transforms under source-content/engine/algorithm/quality identities. Cached data is checksum-validated and decoded without object deserialization; invalid data regenerates from source. GSMeshEditGuard rebuilds its query shapes when quality changes, even if the model basis is unchanged. Cancelling Drive no longer blocks on the native worker; model teardown still joins it. No GS loading/rendering code, source materials or transform authorization has changed in this follow-up.
