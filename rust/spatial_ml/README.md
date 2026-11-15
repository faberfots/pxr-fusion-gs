# Optional SpatialML extension

The Rust extension implements the MobileSAM encoder/prompt decoder contract with actual RGB preprocessing. It uses pinned gdext/ort dependencies, verified MobileSAM ONNX artifacts and ONNX Runtime 1.23.2 CPU. Inference runs only when requested; runtime telemetry is disabled.

On Windows x86_64 with Python, Rust GNU and MinGW installed, run from the repository root:

```powershell
python tools/setup_native_ml.py --build
python tools/run_checks.py --godot PATH_TO_GODOT --script res://tests/native_inference_checks.gd
```

`models/manifest.json` is the single source of truth for artifact paths, upstream revision and trusted SHA-256 values. `models/export-receipt.json` records the official source files, checkpoint, export settings and pinned Python environment. The setup tool verifies existing model files, reproduces them if needed, verifies the official runtime archive and then optionally builds the extension. Model export requires the pinned Windows Python 3.12 environment. The official model license is retained alongside the artifacts; runtime notices are downloaded from its verified official archive.

The installer generates the descriptor only after a successful DLL build. The current extension is version 0.4.2, with `godot/experimental-threads` enabled for private inference workers and safe app-local runtime dependency loading. Previous DLLs remain available to an editor already using them. Restart Godot after installing this version; the extension is deliberately nonreloadable.

The existing CognitivePanel now exposes MobileSAM and a separately verified SAM3 image/language/decoder contract. GDScript owns settings, permissions, prompts, cancellation and UI; Rust and ONNX Runtime own native CPU inference. Cortex also has a bounded native Windows Credential Manager bridge and an owned CPU-only llama.cpp process host. There is no Python application dependency. The optional Python scripts above provision/build artifacts only.

The portable asset catalog under `resources/cortex/catalog.json` supplies relative overrides for the packaged MobileSAM artifacts. See `resources/cortex/README.md` for the model tree, local Qwen lifecycle and copying instructions. The original manifest and export receipt continue to define reproducible MobileSAM provisioning.

Call `NativeMLBridge.load_default_segmenter()` from GDScript. It verifies the encoder, decoder and runtime, materializes PCK resources to the user cache and supplies absolute paths to `load_model_with_runtime`. It does not mutate the process environment. The legacy `load_model` API still accepts `ORT_DYLIB_PATH`.

Encoder input: RGB NCHW [1,3,1024,1024], SAM normalization, aspect-preserving resize and zero padding. Output: `image_embeddings` [1,256,64,64]. Decoder inputs: `image_embeddings`, `point_coords`, `point_labels`, `mask_input`, `has_mask_input`, `orig_im_size`. Point coordinates use original-image pixels. Labels are 0/1. Output includes original-size `masks`; multiple mask channels require `iou_predictions`. The best mask uses a zero logit threshold. `get_mask_size()` reports output dimensions.

Only uncompressed RGB8/RGBA8 images are accepted. Invalid counts, labels, coordinates, shapes and non-finite values fail explicitly. Tests run the actual encoder and decoder through GDScript, check original 640x384 dimensions, >95% fixture-mask IoU and prompt selection of separate objects. The same checks pass without a source tree using the exported PCK and external GDExtension DLLs. This is functional inference qualification, not a general segmentation quality benchmark. Native delivery remains qualified only for Windows x86_64 CPU.
