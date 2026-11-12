# Verified MobileSAM artifacts

`manifest.json` owns artifact paths and trusted SHA-256 values. The encoder and decoder were exported from official MobileSAM revision `f706ad9c4eb7f219c00d9050e46328518ffb65d2`, using its official checkpoint. `export-receipt.json` records source hashes, export options and environment. Apache 2.0 license text is included.

Reproduce or repair the artifacts with `python tools/setup_native_ml.py` from the repository root. Add `--build` to install the native extension after verification. Runtime DLLs and generated native builds are ignored by Git. See the [native setup guide](../README.md) for the contract and qualified boundaries.
