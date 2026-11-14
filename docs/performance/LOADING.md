# Gaussian loading performance

The phase-status owner is [loading-phases.json](loading-phases.json). The original P.X.Y findings retain their separate owner in [remediation-status.json](../audit/remediation-status.json). Completing these loading phases does not close provider-account, asset-provenance, signing or untested hardware requirements.

All runtime orchestration, file IO, parsing, scheduling, cache policy and scene transactions use real GDScript. Bounded compute conversion, validation and cache SHA-256 leaves use GLSL through Godot's RenderingDevice, as the existing renderer does. There is no Python, C#, Rust or new native dependency in this loading path. Existing Python commands only launch isolated Godot checks, assemble packages and render the audit report. The measurements below are produced inside Godot by GDScript.

## Measured result

Windows 11, Godot 4.6.2, NVIDIA RTX 4070 Laptop GPU, Ryzen 7 7840HS. Bali is the complete 1,919,480,116-byte PLY containing 7,739,833 Gaussians. No points, SH coefficients, covariance fields or source geometry are removed. Atlas capacity and the existing total GPU budget still decide admission.

| Journey | GDScript elapsed time |
|---|---:|
| Baseline Bali import | 91.561 s |
| CPU-path improvement, before cache/compute work | 41.040 s |
| First import, including preparation-cache creation, two runs | 11.540 s / 7.926 s |
| Verified prepared reloads, both runs | 7.483 s / 6.812 s; 7.149 s / 7.001 s |
| Save full Bali + Suzuki composition | 6.605 s |
| Reopen it while the full old composition is resident | 32.783 s |
| Optimized Windows template, full Bali + Suzuki load | 8.404 s |

The latter journey protects 1,910,348,640 resident bytes before replacement: 11.889 s to reconstruct the exact checkpoint, 6.279 s to verify it, 6.476 s to verify original sources, followed by loading and commit. All 7,959,786 splats, model matrices and the camera pose match after reopen. Checkpoint tests also compare raw GPU bytes, including creation timestamps and instance IDs, rather than just rendered appearance.

These are local elapsed measurements, not guaranteed service levels. **First import means an empty application preparation cache; it does not mean an uncached physical disk.** Windows filesystem caching remained available. The GPU and other applications were not isolated. The previous read-only Python file-read measurements are not Godot loader benchmarks and are not used for these speedup claims. Engine startup, shader import and package extraction are outside the measured model-load interval. Storage speed, GPU pressure and shader-cache state can change results.

## Responsibilities and data flow

1. `GaussianSplattingViewer` owns admission, scene nodes, the load state machine, identities, upload scheduling and final commit. Loading never moves ownership into a cache or a worker.
2. `GSLoadJob` owns one bounded producer, its cancellable original-source SHA-256 task, private conversion buffers and the four-block producer queue. It reports completion only after decoding, source verification and cache work finish. The viewer waits for the upload fence and rejects render-thread transfer errors before marking a node loaded.
3. `PlyDocument` owns the validated schema and typed reader. Gaussian column mapping is resolved once. Common binary float layouts use bounded bulk reads. Other supported ASCII, little-endian and big-endian typed layouts retain the same validation contract.
4. `GSGpuDecoder` owns a worker-local RenderingDevice. It performs finite-value checks, quaternion normalization, covariance/opacity/SH conversion, bounds reduction and optional prepared-data validation. When unavailable or the shared GPU budget cannot reserve its scratch buffers, bounded GDScript worker-pool conversion remains available.
5. `GSPreparedCache` owns rebuildable local payloads, the explicit directory marker, atomic index/payload commits, strong fingerprints, leases and payload-quota eviction. It owns no scene nodes or model transforms.
6. `GSComposition` owns version-one data-only document validation and the replacement transaction. `GSAtlasMigration` owns a temporary verified checkpoint. `GSDiskCheckpointJob` can reconstruct immutable resident data from a matching verified payload and exact captured runtime spans. Missing, stale or corrupt preparation data falls back to the existing raw GPU checkpoint. A second full GPU atlas is never required.

Transforms, selection, visibility, camera state, color settings, Sky3D state and shadow choices remain with their existing owners. No authentication or multi-user permissions are introduced; the existing local capability policy remains authoritative. Named stages, explicit error results and data-only documents keep the path readable to tooling and future LLM clients.

## Controls and bounded behavior

The existing configuration resource is the single owner of loading policy. Quality presets do not silently alter loading batch size, prepared-cache policy, preview choice or scheduling budgets.

| Setting | Default | Purpose |
|---|---:|---|
| `loading_gpu_conversion_enabled` | true | Use bounded GLSL preparation when supported and affordable |
| `loading_gpu_block_splats` | 131072 | Compute preparation block; legacy CPU batches do not force tiny GPU dispatches |
| `loading_batch_size` | 131072 | Requested CPU block, clamped by staging ownership |
| `loading_cpu_workers` | 2 | CPU fallback parallelism, validated range 1–4 |
| `loading_staging_budget_mb` | 256 | Conservative block/queue/task ownership budget |
| `loading_upload_budget_mb` | 32 | Per-process scheduling budget; individual uploads are at most 32768 splats |
| `loading_schedule_budget_ms` | 2 | Main-thread scheduling deadline with existing resident models; an empty scene may schedule for 8 ms |
| `loading_cache_enabled` | true | Read/write rebuildable preparation payloads |
| `loading_cache_directory` | `user://gs-prepared-cache-v1` | Explicitly application-owned local directory |
| `loading_cache_budget_mb` | 8192 | Payload quota; metadata and live leased payloads may exceed the eviction target |
| `loading_progressive_preview` | false | Show eligible unverified prefixes before full completion |

The queued renderer upload high-water mark is bounded. Import scratch is reserved against the renderer's existing tracked GPU budget, capped at 128 MiB and half the remaining budget; it is released after worker cleanup. Compute buffers have explicit maximum sizes. Upload scheduling is a CPU deadline, not a promise that a GPU transfer cannot stall a driver. Timings distinguish producer work sums, wall time, enqueue/flush time and first rendered frame; they do not pretend to be hardware GPU timestamp queries.

The Settings panel contains the scene-authored progressive-preview checkbox. During preview, the status strip says verification is pending. Resident and committed counts are separate; preview never marks a node loaded or emits final success. Clear/cancel removes the uncommitted prefix. Placement imports remain hidden until ready, and composition replacement remains transactional. Keeping preview off preserves the previous full-commit presentation. Existing Polygonics branding, floating controls, 0.67 UI density and 33% panel opacity remain.

## Cache and integrity

The original PLY remains authoritative. Its complete SHA-256 is checked, including on a cache hit; an equal-length source edit is not accepted. Cache payload length, schema, population, finite bounds/sample metadata and strong block digests are validated. SHA-256 leaves match Godot `HashingContext` byte for byte. Invalid preparation data is discarded and the original source is decoded again. The application does not overwrite original datasets, create a sidecar next to them or treat arbitrary selected directories as owned caches.

Writes use unique temporary files followed by atomic replacement. Cancellation joins owners, closes handles and removes the operation's temporary files. Eviction only removes validated cache-owned payload names, skips active leases, and never deletes source files. Resident records hold leases so checkpoint reconstruction remains available while models are loaded. If that proof is unavailable, GPU recovery remains available even when an old original source has been removed.

The compute decoder is checked against the reference GDScript packer across all 60 output fields. Observed maximum absolute numeric difference is 0.00000005960464 on the qualification fixture; relative tolerance is 0.00003 with absolute floor 0.000002. Prepared copies and checkpoint recovery preserve all resident bytes except deliberate identity remapping during atlas compaction. No claim of formal cryptographic certification or universal cross-GPU numerical identity is made.

## Reproduce

Use the existing isolated `tools/run_checks.py` runner with Godot 4.6.2. `tests/loading_benchmark.gd` takes a full source path and repeat count, plus optional `fresh` (empty preparation cache) or `cpu` (CPU conversion, no preparation cache) arguments. It prints `GDSCRIPT LOAD PROFILE` JSON and writes `user://loading-benchmark.json` in the isolated test application's directory. `tests/loading_composition_benchmark.gd` takes local Bali and Suzuki paths and exercises save plus occupied reopen. Datasets are not redistributed.

Focused suites cover scheduling/backpressure, CPU fallback, compute numeric/SHA parity, source edits, corrupt caches, directory ownership, cancellation, progressive preview, exact disk checkpoints and GPU fallback. Existing composition, migration, teardown, rendering, shadow, transparency, placement, environment, Sky3D, camera, color, transform and actual-input UI suites remain the preservation checks. Local qualification is not a claim that the new CI workflow has run remotely or that other GPUs, operating systems or XR headsets were tested.
