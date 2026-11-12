#[compute]
#version 450

// ═══════════════════════════════════════════════════════════════════════════
// SPATIAL INDEX COMPUTE SHADER
// ═══════════════════════════════════════════════════════════════════════════
// Implements a GPU-based Spatial Hash Grid construction.
// Stages:
// 1. QUANTIZE: Calculate AABB and assign Cell IDs
// 2. COUNT: Count points per cell (Histogram)
// 3. PREFIX_SUM: Calculate start offsets (Parallel Scan) - CPU simplified for MVP
// 4. REORDER: Sort points into buckets
// ═══════════════════════════════════════════════════════════════════════════

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// ═══════════════════════════════════════════════════════════════════════════
// DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════

// Input Point (packed vec4 for alignment: x, y, z, padding)
struct Point {
    float x, y, z;
    float pad;
};

// Grid Parameters (Push Constant)
layout(push_constant) uniform Params {
    vec3 bounds_min;
    float cell_size;   // Voxel size in meters
    vec3 bounds_max;
    uint point_count;  // Total points
    uvec3 grid_dim;    // Grid dimensions (cells x, y, z)
    uint stage;        // 0=Quantize, 1=Count, 2=(CPU), 3=Reorder
};

// ═══════════════════════════════════════════════════════════════════════════
// BUFFERS
// ═══════════════════════════════════════════════════════════════════════════

// B0: Input Points (Read-Only during construction)
layout(set = 0, binding = 0, std430) readonly buffer InputPoints {
    Point points[];
} input_data;

// B1: Point Cell IDs (Intermediate)
// Stores the calculated linear Cell ID for each point
layout(set = 0, binding = 1, std430) buffer PointCellIDs {
    uint cell_ids[];
} point_cell_ids;

// B2: Grid Cell Count/Offset Table
// - First pass: Stores counts (AtomicAdd)
// - Second pass: Stores start offsets (Calculated via Prefix Sum)
layout(set = 0, binding = 2, std430) buffer GridTable {
    uint cell_data[]; // cell_data[linear_cell_id]
} grid_table;

// B3: Sorted Point Indices (Output)
// Maps: SortedIndex -> OriginalIndex
layout(set = 0, binding = 3, std430) buffer SortedIndices {
    uint indices[];
} sorted_indices;

// B4: Next Write Position (Atomic Counter for Reorder stage)
// Stores the current write text for each cell during reorder
// Initialized to same values as offsets, incremented efficiently
layout(set = 0, binding = 4, std430) buffer WriteCounters {
    uint counters[];
} write_counters;

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

// Get linear cell ID from 3D position
uint get_cell_id(vec3 pos) {
    // Clamp to bounds to prevent out-of-bounds access
    vec3 local_pos = pos - bounds_min;
    uvec3 grid_pos = uvec3(local_pos / cell_size);
    
    // Clamp to grid dimensions
    grid_pos = clamp(grid_pos, uvec3(0), grid_dim - uvec3(1));
    
    // Linearize: x + y*DIM_X + z*DIM_X*DIM_Y
    return grid_pos.x + (grid_pos.y * grid_dim.x) + (grid_pos.z * grid_dim.x * grid_dim.y);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════

void main() {
    uint g_id = gl_GlobalInvocationID.x;
    if (g_id >= point_count) return;

    // ─────────────────────────────────────────────────────────────────────
    // STAGE 0: QUANTIZE & ASSIGN CELL IDs
    // ─────────────────────────────────────────────────────────────────────
    if (stage == 0) {
        Point p = input_data.points[g_id];
        uint cell_id = get_cell_id(vec3(p.x, p.y, p.z));
        point_cell_ids.cell_ids[g_id] = cell_id;
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // STAGE 1: COUNT (HISTOGRAM)
    // ─────────────────────────────────────────────────────────────────────
    else if (stage == 1) {
        uint cell_id = point_cell_ids.cell_ids[g_id];
        atomicAdd(grid_table.cell_data[cell_id], 1);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // STAGE 2: PREFIX SUM (Handled on CPU for MVP simplicity)
    // GPU Parallel Scan is complex to implement correctly without shared memory scan
    // For <1M cells, CPU is fast enough (~1ms)
    // ─────────────────────────────────────────────────────────────────────
    
    // ─────────────────────────────────────────────────────────────────────
    // STAGE 3: REORDER (BUCKET SORT)
    // ─────────────────────────────────────────────────────────────────────
    else if (stage == 3) {
        uint cell_id = point_cell_ids.cell_ids[g_id];
        
        // Get write position for this cell and increment atomically
        // unique_index ensures thread safety
        uint write_pos = atomicAdd(write_counters.counters[cell_id], 1);
        
        // precise mapping: sorted[write_pos] = original_index
        sorted_indices.indices[write_pos] = g_id;
    }
}
