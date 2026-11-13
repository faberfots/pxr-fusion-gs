# Godot Gaussian Splatting Viewer

Godot 4.6 compute renderer for Gaussian PLY and versioned `.gsres` assets, with model transforms, scene management, asynchronous picking, optional cloud analysis and a separate SpatialOS point-cloud pipeline.

Open `project.godot` in Godot 4.6.2 and use Forward+ with Vulkan. The qualified local device is an NVIDIA RTX 4070 Laptop GPU on Windows. Compatibility rendering, XR, other operating systems and other GPU vendors have not been qualified.

The complete finding-by-finding implementation status is in [REMEDIATION_STATUS.md](docs/audit/REMEDIATION_STATUS.md). It is generated from [remediation-status.json](docs/audit/remediation-status.json). Current architecture and validation commands are in [IMPLEMENTATION.md](docs/IMPLEMENTATION.md). Historical upstream descriptions and attribution remain in [the archive](docs/archive/upstream-README.md).

## Using the viewer

- Load Gaussian PLY or GSRES from the load panel or drop a file. Loading appends by default; explicit Replace clears this viewer's models.
- Right-drag for free look; use WASD/QE to move. Left-drag orbits the focus point. Clicking a visible Gaussian requests an asynchronous world-space pick.
- Click a visible model to select it. Use the Select / Move / Rotate / Scale toolbar (keys 1–4), then drag an XYZ handle or the center handle. Escape cancels a drag. Existing camera navigation remains available away from handles. Scene Manager retains numeric transforms, visibility and deletion.
- The Color button opens Natural, Warm daylight, Soft, Vivid and Architectural presets, fine sliders, tint, original comparison and reset. Edited colors save automatically and remain independent of quality. Selection never tints the splat image.
- Quality settings migrate a populated atlas transactionally, retaining model identity, selection and independent transforms. A progress indicator remains visible; settings that cannot fit all resident splats are rejected without clearing the scene.
- The memory setting is the complete GS buffer/texture budget. It includes atlas, projected records, sorting scratch, palette and targets, with resize headroom. It excludes engine resources and driver overhead. There is no source-file-size limit. Admission uses the combined splat residency of every loaded and queued model. Each model retains independent XYZ position, XYZ rotation and scale.
- High now reserves a 4 GiB complete GS budget with a large atlas and bounded sorting scratch, preserving full-resolution Bali plus additional models on the qualified 8 GiB GPU. Ultra uses a 6 GiB ceiling.
- Serial editor imports are enabled to avoid a reproduced Godot parallel-import crash.

## Optional AI and native ML

Cloud analysis is off by default. The panel identifies the destination and requires an explicit session toggle before sending the 3D image, prompt and model context. Camera/selection actions have a separate local operator capability. This desktop policy does not provide multi-user authentication.

Set `GS_AI_API_KEY`, or the matching `OPENAI_API_KEY`, `GEMINI_API_KEY` or `ANTHROPIC_API_KEY`, in the Godot process environment. Keys are never saved by the application. **The previously embedded credential must still be revoked in its provider account.**

Native MobileSAM is optional. See [native setup](rust/spatial_ml/README.md). Pinned official MobileSAM weights are exported to verified ONNX models in this repository. `python tools/setup_native_ml.py --build` installs the verified Windows CPU runtime and builds the optional extension. Actual GDScript inference and source-free PCK inference pass the deterministic image test.

## Qualification

Run `python tools/run_checks.py --godot PATH_TO_GODOT` for isolated CPU checks. Add `--gpu --script res://tests/gpu_checks.gd` for compute checks. See the implementation guide for lifecycle, rendering, spatial and export checks.

Original project copyright and MIT license are preserved in [LICENSE](LICENSE). Third-party evidence and unresolved redistribution questions are tracked in [dependency-inventory.json](docs/dependency-inventory.json). Historical performance figures are not benchmarks for this revision.
