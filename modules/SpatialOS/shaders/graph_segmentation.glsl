#[compute]
#version 450

// GRAPH SEGMENTATION COMPUTE SHADER - Multi-Modal Edge Score (Foundation 2.6)
// Implements GPU-parallel connected components using edge-aware region growing.
// Points are connected ONLY if their combined edge score is below threshold.
// Edge score combines: spatial, normal, color, curvature, and height features.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// DATA STRUCTURES

struct Point {
    float x, y, z;
    float pad;
};

// Push Constants - Extended for multi-modal edge scoring
layout(push_constant) uniform Params {
    vec3 bounds_min;
    float cell_size;
    vec3 bounds_max;
    uint point_count;
    uvec3 grid_dim;
    float radius_sq;
    
    // Edge weights (Foundation 2.6)
    float w_spatial;
    float w_normal;
    float w_color;
    float w_curvature;
    float w_height;
    float edge_threshold;
    float height_edge_min;
    uint use_normals;
};

// BUFFERS

// B0: Input Points (Read-Only)
layout(set = 0, binding = 0, std430) readonly buffer InputPoints {
    Point points[];
} input_data;

// B1: Grid Table (Offsets from Spatial Index)
layout(set = 0, binding = 1, std430) readonly buffer GridTable {
    uint offsets[];
} grid_table;

// B2: Sorted Indices (from Spatial Index)
layout(set = 0, binding = 2, std430) readonly buffer SortedIndices {
    uint indices[];
} sorted_indices;

// B3: Labels (Read/Write)
layout(set = 0, binding = 3, std430) readonly buffer Labels {
    uint labels[];
} label_data;

layout(set=0,binding=7,std430) writeonly buffer NextLabels { uint labels[]; } next_labels;

// B4: Changed Flag (Atomic)
layout(set = 0, binding = 4, std430) buffer ChangedFlag {
    uint changed;
} change_flag;

// B5: Input Normals (Read-Only) - vec4: x, y, z, curvature
layout(set = 0, binding = 5, std430) readonly buffer InputNormals {
    vec4 data[];
} normal_data;

// B6: Input Colors (Read-Only) - NEW for multi-modal
layout(set = 0, binding = 6, std430) readonly buffer InputColors {
    vec4 colors[];
} color_data;

// HELPER FUNCTIONS

uvec3 get_cell_coord(vec3 pos) {
    vec3 local_pos = pos - bounds_min;
    uvec3 grid_pos = uvec3(local_pos / cell_size);
    return clamp(grid_pos, uvec3(0), grid_dim - uvec3(1));
}

uint get_linear_cell_id(uvec3 coord) {
    return coord.x + (coord.y * grid_dim.x) + (coord.z * grid_dim.x * grid_dim.y);
}

// Compute edge score between two points
// Returns value in [0, 1+] where lower = more similar = should connect
float compute_edge_score(uint idx_a, uint idx_b) {
    // Get positions
    vec3 pos_a = vec3(input_data.points[idx_a].x, input_data.points[idx_a].y, input_data.points[idx_a].z);
    vec3 pos_b = vec3(input_data.points[idx_b].x, input_data.points[idx_b].y, input_data.points[idx_b].z);
    
    float radius = sqrt(radius_sq);
    
    // 1. Spatial distance (normalized by radius)
    float dist = length(pos_a - pos_b);
    float spatial_score = dist / radius;
    
    // 2. Normal discontinuity
    float normal_score = 0.0;
    float curvature_score = 0.0;
    if (use_normals == 1u) {
        vec3 n_a = normal_data.data[idx_a].xyz;
        vec3 n_b = normal_data.data[idx_b].xyz;
        
        float len_a = length(n_a);
        float len_b = length(n_b);
        
        if (len_a > 0.001 && len_b > 0.001) {
            // Normal discontinuity: 0 = same direction, 1 = perpendicular
            float alignment = abs(dot(n_a, n_b));
            normal_score = 1.0 - alignment;
        }
        
        // Curvature difference
        float curv_a = normal_data.data[idx_a].w;
        float curv_b = normal_data.data[idx_b].w;
        curvature_score = abs(curv_a - curv_b) * 5.0; // Scale up for visibility
    }
    
    // 3. Color difference (RGB Euclidean in [0,1] space)
    vec3 c_a = color_data.colors[idx_a].rgb;
    vec3 c_b = color_data.colors[idx_b].rgb;
    float color_score = length(c_a - c_b) / 1.732; // Normalize by max RGB distance
    
    // 4. Height discontinuity (Y-axis vertical separation)
    float height_diff = abs(pos_a.y - pos_b.y);
    float height_score = 0.0;
    if (height_diff > height_edge_min) {
        height_score = height_diff / (radius * 2.0);
    }
    
    // Combined weighted edge score
    float edge_score = w_spatial * spatial_score
                     + w_normal * normal_score
                     + w_color * color_score
                     + w_curvature * curvature_score
                     + w_height * height_score;
    
    return edge_score;
}

// MAIN

void main() {
    uint g_id = gl_GlobalInvocationID.x;
    if (g_id >= point_count) return;
    
    // Get my position and current label
    float px = input_data.points[g_id].x;
    float py = input_data.points[g_id].y;
    float pz = input_data.points[g_id].z;
    vec3 my_pos = vec3(px, py, pz);
    
    uint my_label = label_data.labels[g_id];
    uint min_label = my_label;
    
    // Calculate cell search range based on radius
    float radius = sqrt(radius_sq);
    int cells_dim = int(ceil(radius / cell_size));
    uvec3 my_cell = get_cell_coord(my_pos);
    
    // Search neighboring cells
    for (int dz = -cells_dim; dz <= cells_dim; dz++) {
        for (int dy = -cells_dim; dy <= cells_dim; dy++) {
            for (int dx = -cells_dim; dx <= cells_dim; dx++) {
                
                ivec3 neighbor_cell = ivec3(my_cell) + ivec3(dx, dy, dz);
                
                // Bounds check
                if (neighbor_cell.x < 0 || neighbor_cell.x >= int(grid_dim.x) ||
                    neighbor_cell.y < 0 || neighbor_cell.y >= int(grid_dim.y) ||
                    neighbor_cell.z < 0 || neighbor_cell.z >= int(grid_dim.z)) {
                    continue;
                }
                
                uint cell_id = get_linear_cell_id(uvec3(neighbor_cell));
                uint start = grid_table.offsets[cell_id];
                uint end = grid_table.offsets[cell_id + 1u];
                
                // Iterate points in this cell
                for (uint i = start; i < end; i++) {
                    uint neighbor_idx = sorted_indices.indices[i];
                    
                    if (neighbor_idx == g_id) continue;
                    if (neighbor_idx >= point_count) continue;
                    
                    // Distance check (quick rejection)
                    float npx = input_data.points[neighbor_idx].x;
                    float npy = input_data.points[neighbor_idx].y;
                    float npz = input_data.points[neighbor_idx].z;
                    vec3 neighbor_pos = vec3(npx, npy, npz);
                    
                    vec3 diff = my_pos - neighbor_pos;
                    float dist_sq = dot(diff, diff);
                    
                    if (dist_sq <= radius_sq) {
                        // Compute multi-modal edge score
                        float edge_score = compute_edge_score(g_id, neighbor_idx);
                        
                        // Connect ONLY if edge score is below threshold
                        if (edge_score < edge_threshold) {
                            uint neighbor_label = label_data.labels[neighbor_idx];
                            min_label = min(min_label, neighbor_label);
                        }
                    }
                }
            }
        }
    }
    
    min_label = min(min_label, label_data.labels[min_label]);
    next_labels.labels[g_id] = min_label;
    // Update label if changed
    if (min_label < my_label) {
        atomicOr(change_flag.changed, 1u);
        atomicOr(change_flag.changed, 1u);
    }
}
