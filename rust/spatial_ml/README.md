# Optional SpatialML extension

The Rust source implements the MobileSAM image encoder / prompt decoder contract with actual RGB preprocessing. It uses pinned gdext and ort dependencies and a dynamically supplied ONNX Runtime. Native inference is optional and does not run at application startup.

On this Windows checkout, `.cargo/config.toml` selects the GNU toolchain. From this directory:

```powershell
cargo check --locked
cargo test --locked
./build.ps1 -Configuration release
```

The installer activates the descriptor only after a DLL exists. Required runtime libraries and approved model files are not fetched implicitly. Set `ORT_DYLIB_PATH` to a compatible ONNX Runtime library. Initialization reports failure when the runtime is absent.

Use `NativeMLBridge.materialize_model(source, trusted_sha256)` to copy and verify packaged or local ONNX files into the user cache. Pass the returned absolute OS paths to `load_model`. Raw `res://` paths inside a PCK cannot be opened by ONNX Runtime.

Encoder inputs: `image` float NCHW [1,3,1024,1024], RGB normalized with SAM mean/std after an aspect-preserving resize and zero padding. Encoder output: `image_embeddings` [1,256,64,64].

Decoder inputs: `image_embeddings`, `point_coords`, `point_labels`, `mask_input`, `has_mask_input`, `orig_im_size`. Point coordinates use original-image pixels; the extension rescales them and appends the no-point sentinel. Labels must be 0 or 1. Outputs must include original-size `masks`; multiple channels require `iou_predictions`. The best mask uses a zero logit threshold. `get_mask_size()` supplies output dimensions.

Only RGB8/RGBA8 uncompressed images are accepted. Invalid counts, labels, coordinates, shapes and non-finite values fail explicitly. There are no placeholder image tensors.

The source and preprocessing tests are locally qualified. End-to-end inference, model artifact integrity/rights, platform deployment and performance require approved models and ONNX Runtime. Linux/macOS descriptor entries remain unqualified templates.
