# Approved model artifacts

This directory has no model weights. Supply an approved encoder and decoder with trusted SHA-256 values and record their origin, export settings and redistribution terms.

The supported decoder contract follows the [official MobileSAM ONNX exporter](https://github.com/ChaoningZhang/MobileSAM/blob/master/scripts/export_onnx_model.py). A compatible encoder must be exported separately from the matching checkpoint. Arbitrary third-party conversions may use different preprocessing or input/output names.

Use the verified extraction helper described in [the native setup guide](../README.md). A successful preprocessing unit test is not proof of model inference quality.
