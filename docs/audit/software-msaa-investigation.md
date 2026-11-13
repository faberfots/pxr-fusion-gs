# Software Vulkan MSAA investigation

2026-11-13: the existing llvmpipe opaque-depth failure reproduces with MSAA enabled. An isolated explicit sampler2DMS reverse-Z resolve was tried with both depth-retention modes; Windows passed, llvmpipe still failed. The experiment was removed before promotion. The qualified Windows pipeline and memory plan remain unchanged. Linux CI retains its explicit no-MSAA scope. This does not close P.3.6; arbitrary transparent interleaving, Gaussian shadows and XR remain unsupported.
