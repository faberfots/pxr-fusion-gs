# Godot Gaussian Splatting Viewer

Godot 4.6 compute renderer for Gaussian PLY and versioned `.gsres` assets, with model transforms, scene management, asynchronous picking, optional cloud analysis and a separate SpatialOS point-cloud pipeline.

**Mixed scenes:** import native GLB/glTF models beside GS, then select and edit either with the existing gizmo and numeric controls. Save exact mixed compositions as `.pxrscene`; **Include asset files** creates an adjacent portable bundle. See [mixed-scene usage and limits](docs/MIXED_SCENES.md).

**Mutual GS/mesh occlusion:** a GLB can hide behind a scanned GS tree, with its exposed parts still visible. Opaque GLBs also hide GS behind them. This is a supported hybrid-scene feature in perspective and orthographic views, using Gaussian opacity and native depth.

Open `project.godot` in Godot 4.6.2 and use Forward+ with Vulkan. The qualified local device is an NVIDIA RTX 4070 Laptop GPU on Windows. Compatibility rendering, XR, other operating systems and other GPU vendors have not been qualified.

The complete finding-by-finding implementation status is in [REMEDIATION_STATUS.md](docs/audit/REMEDIATION_STATUS.md). It is generated from [remediation-status.json](docs/audit/remediation-status.json). Current architecture and validation commands are in [IMPLEMENTATION.md](docs/IMPLEMENTATION.md). Historical upstream descriptions and attribution remain in [the archive](docs/archive/upstream-README.md).

## Using the viewer

- Load Gaussian PLY/GSRES or native GLB/glTF from the load panel or drop a file. Loading appends by default; the explicit Clear scene option replaces this viewer's models.
- Right-drag for free look; use WASD/QE to move. Left-drag orbits the focus point. Clicking a visible Gaussian requests an asynchronous world-space pick.
- Click a visible model to select it. Use the Select / Move / Rotate / Scale toolbar (keys 1–4), then drag an XYZ handle or the center handle. Escape cancels a drag. Existing camera navigation remains available away from handles. Scene Manager retains numeric transforms, visibility and deletion.
- **Solid** defaults on for rigid GLB model edits: gizmo and numerical movement/rotation/scale stop at floors and other native meshes. **Fast** uses Godot QuickHull per mesh part; **Detailed** retains concave decomposition for precision-sensitive edits. Prepared shapes are cached across runs. Drive retains Detailed shapes for passable openings. Switch Solid off for intentional overlaps. Imported/saved poses restore exactly; environments remain freely alignable.
- For solid movement, select an imported rigid GLB/glTF **model**, open **Camera → Drive selected GLB**, then use WASD, Shift for speed, Space to jump and right-drag to look. Escape returns to editing. GLB environments use their triangle floors/walls; moving models use compound shapes derived from their mesh. One undo restores the walk. See [collision behavior and limits](docs/MIXED_SCENES.md#solid-navigation).
- The Color button opens Natural, Warm daylight, Soft, Vivid and Architectural presets, fine sliders, tint, original comparison and reset. Edited colors save automatically and remain independent of quality. Selection never tints the splat image.
- Quality settings migrate a populated atlas transactionally, retaining model identity, selection and independent transforms. A progress indicator remains visible; settings that cannot fit all resident splats are rejected without clearing the scene.
- The memory setting is the complete GS buffer/texture budget. It includes atlas, projected records, sorting scratch, palette and targets, with resize headroom. It excludes engine resources and driver overhead. There is no source-file-size limit. Admission uses the combined splat residency of every loaded and queued model. Each model retains independent XYZ position, XYZ rotation and scale.
- High now reserves a 4 GiB complete GS budget with a large atlas and bounded sorting scratch, preserving full-resolution Bali plus additional models on the qualified 8 GiB GPU. Ultra uses a 6 GiB ceiling.
- Serial editor imports are enabled to avoid a reproduced Godot parallel-import crash.

## Optional AI and native ML

Open **Cortex Intelligence** and choose your goal. **Select with a click** is the default; local selection and private scene questions need no account. **How it works** explains each preset in plain language. Your advanced settings remain available through the gear button. See [the preset guide](docs/CORTEX.md#start-with-your-goal).

Cloud analysis is off by default. The panel identifies the destination and requires an explicit session toggle before sending the 3D image, prompt and model context. Camera/selection actions have a separate local operator capability. This desktop policy does not provide multi-user authentication.

Use the existing **Cortex → Setup** panel to configure OpenAI, Anthropic, Gemini, Ollama, bundled Qwen or an OpenAI-compatible connection. Keys can stay in memory, refer to an environment variable or use Windows Credential Manager. Non-secret settings persist separately. **The previously embedded credential must still be revoked in its provider account.**

Native MobileSAM is optional. See [native setup](rust/spatial_ml/README.md). Pinned official MobileSAM weights are exported to verified ONNX models in this repository. `python tools/setup_native_ml.py --build` installs the verified Windows CPU runtime and builds the optional extension. Actual GDScript inference and source-free PCK inference pass the deterministic image test.

The portable local model tree now contains MobileSAM, the verified SAM3 pack and official Qwen3 1.7B Q8, with their Windows CPU runtimes and licenses. **Copy the whole project folder, including ignored `resources/cortex/models` and `resources/cortex/runtimes`; Git alone does not carry those large files.** See [portable Cortex instructions](resources/cortex/README.md). Models start on request, preserving the existing GS loading/rendering path. Cortex **Select** captures a clean view and supports local masks and selection of existing models without altering their transforms.

## Qualification

Run `python tools/run_checks.py --godot PATH_TO_GODOT` for isolated CPU checks. Add `--gpu --script res://tests/gpu_checks.gd` for compute checks. See the implementation guide for lifecycle, rendering, spatial and export checks.

Original project copyright and MIT license are preserved in [LICENSE](LICENSE). Third-party evidence and unresolved redistribution questions are tracked in [dependency-inventory.json](docs/dependency-inventory.json). Historical performance figures are not benchmarks for this revision.

The normal main-scene color-panel startup crash and optimized-template startup failure are fixed. The color panel waits for viewer initialization, and the camera add-on no longer leaves orphan visualization nodes during export inspection. The Windows optimized-template package is unsigned. Use tools/qualify_release.py for a separate GPU/native qualification package and tools/check_packaged_startup.py for the actual main entry point. llvmpipe selects its qualified native 4x MSAA when unsupported 2x/8x was requested; hardware GPU settings are retained.

For local exports and test workspaces, see [build cleanup and retention](docs/BUILD_CLEANUP.md). The cleanup helper previews changes by default and archives evidence before removing reviewed obsolete outputs.
