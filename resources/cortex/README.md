# Portable Cortex resources

Copy this **entire directory**, including `models/` and `runtimes/`, with the project. These large assets are intentionally ignored by Git; a Git clone alone does not contain them. No Python installation, Ollama installation, model download or cloud key is needed for bundled local inference on a compatible Windows x86_64 computer.

```
resources/cortex/
  catalog.json                            # versioned relative paths, sizes and SHA-256
  models/
    segmentation/mobilesam/vit_t/         # point-prompt encoder and decoder
    segmentation/sam3/vit_h_20260220/      # image/language encoders, decoder and external weights
    language/qwen3/1.7b-q8_0/             # official Qwen3 1.7B Q8_0 GGUF
  runtimes/
    onnxruntime/1.23.2/windows-x86_64/      # CPU segmentation runtime and notices
    llama.cpp/b12387/windows-x86_64/      # CPU language runner and notices
```

The editor resolves this location from `res://`; the exported application resolves it next to `GSViewer.exe`. Paths are independent of the Windows username, Downloads folder, drive letter and original checkout. `.gdignore` prevents model weights from being imported by Godot. Models remain external to the PCK. Keep every ONNX `.data` file with its graph.

Both runtime folders include the required, signed Microsoft C++ x64 redistributable DLLs from Visual Studio's `VC/Redist/MSVC/14.44.35112` distribution. The ONNX bridge verifies and stages those dependencies together, then loads that directory using safe Windows loader flags without changing PATH or global DLL search settings. Qwen uses its own executable directory. Original Microsoft redistribution references and notices travel with both folders. Windows system components, graphics drivers and adequate hardware remain machine prerequisites.

On the next application run, open **Cortex Intelligence** and choose your goal. **Select with a click** is the recommended default; **How it works** explains the steps. **Understand my scene · private** and **Explain my selected model · private** prepare the included assistant from **Start & ask privately**, without an account or manual server setup. Selecting a preset alone starts no model.

Advanced settings retain **Setup → Connections → Start bundled Qwen** and **Stop · release memory**. Qwen is text-only in this bundle; guided requests share scene information without pictures or scene commands. Starting Qwen uses four CPU threads, a 2,048-token context and no GPU offload. It listens only on `127.0.0.1:18081`.

For segmentation, use **Setup → Vision**, choose MobileSAM or SAM3, apply, then **Select → Capture view**. MobileSAM accepts foreground/background points. SAM3 accepts a concept such as `motorcycle`, with an optional box. Inference starts only on request. A mask can select a visible existing model; it does not extract Gaussians from that model. Recapture after moving the camera or changing scene geometry.

Models and runtimes are verified before first use, on a private worker. They are not initialized at startup or when simply opening Cortex. SAM3 is substantially heavier than MobileSAM. Active inference still competes for CPU/RAM, so release its sessions or stop Qwen when maximum GS performance is needed. The bundle cannot guarantee every computer has enough memory or supports the same CPU/runtime; macOS, Linux and ARM are not qualified by these Windows binaries.

Verify a copied tree without inference:

```powershell
powershell -NoProfile -File tools/verify_cortex_bundle.ps1
```

Build tooling can include it in a new application package with `tools/package_candidate.py --include-cortex ...`. Existing qualified packages are preserved.

The SAM3 files supplied locally match the published exporter manifest byte for byte. Source revisions and expected hashes are recorded in `catalog.json` and `modules/spatial_intelligence/models/sam3-pack-manifest.json`. MobileSAM's original export receipt, all applicable model licenses, ONNX Runtime notices, Qwen's Apache license and llama.cpp/OpenMP licenses travel with the assets. SAM3 uses the Meta SAM license; it is not MIT.

Credentials deliberately do **not** travel with the bundle. Session keys disappear on exit, environment keys belong to the new machine, and Windows Credential Manager entries belong to its OS account. Configure cloud credentials on each computer through Cortex; never add them to this directory or Git. Application settings live under `user://cortex/settings.json` and store references, not secrets.
