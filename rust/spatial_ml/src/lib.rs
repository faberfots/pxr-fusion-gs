//! SpatialML - MobileSAM Segmentation for SpatialOS
//!
//! This GDExtension provides ML-powered segmentation using MobileSAM
//! via ONNX Runtime. It exposes a `MobileSamSegmenter` class to GDScript.

use godot::prelude::*;

mod mobile_sam;
mod credential_vault;
mod sam3;
mod text_tools;
mod local_model_host;

/// GDExtension entry point
struct SpatialMlExtension;

#[gdextension]
unsafe impl ExtensionLibrary for SpatialMlExtension {}
mod runtime_loader;
