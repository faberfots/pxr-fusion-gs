# Implementation and qualification

## Ownership and contracts

| Owner | Responsibility |
|---|---|
| GaussianSplattingViewer | Model registry, stable model IDs, selection, admission, lifecycle state and batch outcomes |
| GSStateMachine | Valid lifecycle transitions; the viewer exposes its state rather than maintaining another state field |
| GSLoadJob | Pure CPU decoding, four-chunk backpressure, cancellation and joined worker lifetime |
| PLYDocument | Bounded header/row reading, scalar types, byte order and property mapping for both pipelines |
| GaussianSplatResource | Versioned binary layout and checksum |
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

Compute colors are linear premultiplied RGBA. The display shader recovers straight RGB once and Godot applies scene tone mapping. A PRE_TRANSPARENT compositor supplies resolved opaque depth. Correct interleaving with arbitrary transparent meshes, shadow casting, collision geometry and XR multiview are outside the implemented renderer contract.

Selection is owned by the viewer. UI and AI use stable model IDs; the selected instance is tinted by the renderer. AI output is untrusted: tool schemas are advertised only for an allowed role, and arguments and permissions are checked again before mutation. The policy applies to a local desktop session; a future multi-user service must supply authenticated roles.

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

Use `--candidate PATH --skip-import` to reuse an already imported isolated candidate after source synchronization. The runner treats script/runtime errors as failures even when Godot exits zero. GPU checks require a real compute-capable device. Cloud tests use response fixtures and do not transmit scene data.

Local checks cover allocator reuse, malformed input, mixed scalar big-endian decoding, GSRES corruption, worker cancellation, policy denial, provider parsing, geometry invalidation, initialization/reset, queued loads, deletion, resize, camera ownership, stable selection, sort partitions, wide tile IDs, overflow, compositing, pixel termination, opaque depth and spatial components.

The native crate supports `cargo check --locked`, `cargo test --locked` and `cargo build --locked`. Preprocessing tests confirm pixel-dependent tensors and aspect-ratio padding. These are distinct from inference validation against approved model artifacts.

The export preset is versioned. Raw PLY, GSRES and ONNX files outside the excluded private resources folder are included explicitly. PCK validation runs the GPU suite with only packaged resources and required native add-on binaries, without raw GLSL files. A PCK must be distributed with its GDExtension libraries; use a full Godot export for shipping. Local export-template executables, remote CI execution, release signing and large-scene performance baselines are not qualified here.

## Evidence and limits

The SSOT for each audit finding, local evidence and remaining work is `docs/audit/remediation-status.json`. A finding is fully implemented only when its relevant local checks pass. Cross-platform support is not inferred from local results.

SpatialOS loading is bounded and cancellable. Progressive visualization is prepared before chunks arrive and yields during final instance population. Some geometry preparation, dense-grid prefix scanning and analysis work still runs on the main thread; multi-million-point responsiveness remains a qualification boundary.

Geometric labels and support relationships are hypotheses, not calibrated recognition or verified physical contact. Missing normals remain unknown. Cloud provider compatibility has fixture coverage; live provider execution requires credentials and explicit cloud consent.

No previously published release was replaced or deployed. Source was backed up before remediation. The workspace arrived without Git history; no historical provenance or remote CI run can be reconstructed from that snapshot.

## Large scenes and per-model transforms

Source-file byte size is not a loading limit. The shared atlas admits loaded and queued populations together, while each GaussianSplat owns its Transform3D and palette identity. Legacy file-size parameters are accepted for compatibility and ignored. Source data is streamed through the bounded worker queue. Valid very thin Gaussians are preserved; only float32 covariance representability is constrained.

The High preset uses a 4 GiB complete GPU allocation ceiling and reserves fewer speculative tile pairs per atlas splat, retaining enough full-resolution atlas space for Bali and a second model. This changes scratch reservation, not SH degree or source population.

Perspective covariance uses a bounded off-axis linearization while retaining the true projected mean for footprint culling. Without this guard, near-plane Gaussians far outside the view can expand across the image and obscure an otherwise valid full scene. Pair admission uses one bounded reservation per workgroup to avoid per-Gaussian compare/exchange contention.

The main scene's prototype grid is a reference background: it draws before Gaussian presentation and does not write opaque depth. Ordinary opaque Godot geometry still occludes Gaussians through the compositor. This preserves the original grid behaviour without disabling scene-depth integration.
