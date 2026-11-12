#[compute]
#version 450

// GEOMETRIC ANALYSIS COMPUTE SHADER (Foundation 2.5)
// Implements Covariance Matrix Analysis (PCA) to extract surface features.
//
// Algorithm:
// 1. Neighborhood Collection: Find K-nearest neighbors via Spatial Index
// 2. Covariance Matrix: Compute 3x3 symmetric matrix of neighborhood variance
// 3. Eigen-Decomposition: Solve for eigenvalues (L1, L2, L3) and eigenvectors
// 4. Feature Extraction:
//    - Normal = Eigenvector corresponding to smallest eigenvalue (L3)
//    - Curvature = L3 / (L1 + L2 + L3)

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// DATA STRUCTURES

struct Point {
    float x, y, z;
    float pad;
};

layout(push_constant) uniform Params {
    vec3 bounds_min;
    float cell_size;
    vec3 bounds_max;
    uint point_count;
    uvec3 grid_dim;
    float radius_sq;
};

// BUFFERS

// Input Points (Read-Only)
layout(set = 0, binding = 0, std430) readonly buffer InputPoints {
    Point points[];
} input_data;

// Grid Table (Spatial Index)
layout(set = 0, binding = 1, std430) readonly buffer GridTable {
    uint offsets[];
} grid_table;

// Sorted Indices (Spatial Index)
layout(set = 0, binding = 2, std430) readonly buffer SortedIndices {
    uint indices[];
} sorted_indices;

// OUTPUT: Normals (vec4: x, y, z, curvature)
layout(set = 0, binding = 3, std430) buffer OutputNormals {
    vec4 data[];
} output_data;

// HELPER FUNCTIONS

uvec3 get_cell_coord(vec3 pos) {
    vec3 local_pos = pos - bounds_min;
    uvec3 grid_pos = uvec3(local_pos / cell_size);
    return clamp(grid_pos, uvec3(0), grid_dim - uvec3(1));
}

uint get_linear_cell_id(uvec3 coord) {
    return coord.x + (coord.y * grid_dim.x) + (coord.z * grid_dim.x * grid_dim.y);
}

// EIGEN SOLVER (3x3 Symmetric Matrix)
// Solves for the smallest eigenvalue and corresponding eigenvector (Normal)
// Uses Jacobi iteration (3 sweeps for 3x3 matrix)

void solve_eigen(mat3 cov, out vec3 normal, out float curvature) {
    mat3 A = cov;
    mat3 V = mat3(1.0);
    
    // 3 sweeps of Jacobi rotation - MANUALLY UNROLLED for compatibility
    for (int sweep = 0; sweep < 3; sweep++) {
        // Pair (0, 1)
        {
            float app = A[0][0];
            float aqq = A[1][1];
            float apq = A[0][1];
            
            if (abs(apq) > 1e-6) {
                float theta = 0.5 * atan(2.0 * apq, aqq - app);
                float c = cos(theta);
                float s = sin(theta);
                
                // Update A diagonal and eliminator
                A[0][0] = c*c*app - 2.0*s*c*apq + s*s*aqq;
                A[1][1] = s*s*app + 2.0*s*c*apq + c*c*aqq;
                A[0][1] = 0.0;
                A[1][0] = 0.0;
                
                // Update row/col k=2
                float a02 = A[0][2];
                float a12 = A[1][2];
                A[0][2] = c*a02 - s*a12;
                A[1][2] = s*a02 + c*a12;
                A[2][0] = A[0][2];
                A[2][1] = A[1][2]; // Symmetric
                
                // Update V
                vec3 v0 = V[0];
                vec3 v1 = V[1];
                V[0] = c*v0 - s*v1;
                V[1] = s*v0 + c*v1;
            }
        }
        
        // Pair (0, 2)
        {
            float app = A[0][0];
            float aqq = A[2][2];
            float apq = A[0][2];
            
            if (abs(apq) > 1e-6) {
                float theta = 0.5 * atan(2.0 * apq, aqq - app);
                float c = cos(theta);
                float s = sin(theta);
                
                A[0][0] = c*c*app - 2.0*s*c*apq + s*s*aqq;
                A[2][2] = s*s*app + 2.0*s*c*apq + c*c*aqq;
                A[0][2] = 0.0;
                A[2][0] = 0.0;
                
                // k=1
                float a01 = A[0][1];
                float a21 = A[2][1];
                A[0][1] = c*a01 - s*a21;
                A[2][1] = s*a01 + c*a21;
                A[1][0] = A[0][1];
                A[1][2] = A[2][1];
                
                vec3 v0 = V[0];
                vec3 v2 = V[2];
                V[0] = c*v0 - s*v2;
                V[2] = s*v0 + c*v2;
            }
        }
        
        // Pair (1, 2)
        {
            float app = A[1][1];
            float aqq = A[2][2];
            float apq = A[1][2];
            
            if (abs(apq) > 1e-6) {
                float theta = 0.5 * atan(2.0 * apq, aqq - app);
                float c = cos(theta);
                float s = sin(theta);
                
                A[1][1] = c*c*app - 2.0*s*c*apq + s*s*aqq;
                A[2][2] = s*s*app + 2.0*s*c*apq + c*c*aqq;
                A[1][2] = 0.0;
                A[2][1] = 0.0;
                
                // k=0
                float a10 = A[1][0];
                float a20 = A[2][0];
                A[1][0] = c*a10 - s*a20;
                A[2][0] = s*a10 + c*a20;
                A[0][1] = A[1][0];
                A[0][2] = A[2][0];
                
                vec3 v1 = V[1];
                vec3 v2 = V[2];
                V[1] = c*v1 - s*v2;
                V[2] = s*v1 + c*v2;
            }
        }
    }
    
    // Eigenvalues are now on diagonal of A
    float l1 = A[0][0];
    float l2 = A[1][1];
    float l3 = A[2][2];
    
    // Find min eigenvalue index
    int min_idx = 0;
    float min_l = l1;
    if (l2 < min_l) { min_l = l2; min_idx = 1; }
    if (l3 < min_l) { min_l = l3; min_idx = 2; }
    
    float largest=max(l1,max(l2,l3));
    float smallest=min(l1,min(l2,l3));
    float middle=l1+l2+l3-largest-smallest;
    if(largest<=1e-12 || middle<=largest*1e-5) { normal=vec3(0);curvature=1.0;return; }
    // Normal is eigenvector of MIN eigenvalue
    normal = normalize(V[min_idx]);
    
    // Curvature = min / sum
    float sum_l = l1 + l2 + l3;
    curvature = (sum_l > 1e-9) ? min_l / sum_l : 0.0;
}

// MAIN

void main() {
    uint g_id = gl_GlobalInvocationID.x;
    if (g_id >= point_count) return;
    
    // Use strictly aligned struct access
    float px = input_data.points[g_id].x;
    float py = input_data.points[g_id].y;
    float pz = input_data.points[g_id].z;
    vec3 center_pos = vec3(px, py, pz);
    
    // 1. GATHER NEIGHBORS
    float radius = sqrt(radius_sq);
    int grid_radius = int(ceil(radius / cell_size));
    uvec3 center_cell = get_cell_coord(center_pos);
    
    vec3 center_mass = vec3(0.0);
    int count = 0;
    
    // Pass 1: Compute Center of Mass
    for (int dz = -grid_radius; dz <= grid_radius; dz++) {
        for (int dy = -grid_radius; dy <= grid_radius; dy++) {
            for (int dx = -grid_radius; dx <= grid_radius; dx++) {
                // Ensure uvec3/ivec3 conversion is explicit
                ivec3 cell_idx = ivec3(center_cell) + ivec3(dx, dy, dz);
                
                if (any(lessThan(cell_idx, ivec3(0))) || any(greaterThanEqual(cell_idx, ivec3(grid_dim)))) continue;
                
                uint cell_id = get_linear_cell_id(uvec3(cell_idx));
                uint start = grid_table.offsets[cell_id];
                uint end = grid_table.offsets[cell_id + 1];
                
                for (uint i = start; i < end; i++) {
                    uint idx = sorted_indices.indices[i];
                    if (idx >= point_count) continue; // Safety check
                    
                    float nx = input_data.points[idx].x;
                    float ny = input_data.points[idx].y;
                    float nz = input_data.points[idx].z;
                    vec3 n_pos = vec3(nx, ny, nz);
                    
                    vec3 diff = n_pos - center_pos;
                    if (dot(diff, diff) <= radius_sq) {
                        center_mass += n_pos;
                        count++;
                    }
                }
            }
        }
    }
    
    if (count < 3) {
        // Not enough neighbors for plane fitting
        output_data.data[g_id] = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    
    center_mass /= float(count);
    
    // Pass 2: Compute Covariance Matrix
    mat3 cov = mat3(0.0);
    
    for (int dz = -grid_radius; dz <= grid_radius; dz++) {
        for (int dy = -grid_radius; dy <= grid_radius; dy++) {
            for (int dx = -grid_radius; dx <= grid_radius; dx++) {
                ivec3 cell_idx = ivec3(center_cell) + ivec3(dx, dy, dz);
                
                if (any(lessThan(cell_idx, ivec3(0))) || any(greaterThanEqual(cell_idx, ivec3(grid_dim)))) continue;
                
                uint cell_id = get_linear_cell_id(uvec3(cell_idx));
                uint start = grid_table.offsets[cell_id];
                uint end = grid_table.offsets[cell_id + 1];
                
                for (uint i = start; i < end; i++) {
                    uint idx = sorted_indices.indices[i];
                    if (idx >= point_count) continue;
                    
                    float nx = input_data.points[idx].x;
                    float ny = input_data.points[idx].y;
                    float nz = input_data.points[idx].z;
                    vec3 n_pos = vec3(nx, ny, nz);
                    
                    vec3 diff = n_pos - center_pos;
                    if (dot(diff, diff) <= radius_sq) {
                        vec3 d = n_pos - center_mass;
                        // Outer Product d * d^T
                        cov[0][0] += d.x * d.x;
                        cov[0][1] += d.x * d.y;
                        cov[0][2] += d.x * d.z;
                        cov[1][1] += d.y * d.y;
                        cov[1][2] += d.y * d.z;
                        cov[2][2] += d.z * d.z;
                    }
                }
            }
        }
    }
    
    // Fill symmetric parts
    cov[1][0] = cov[0][1];
    cov[2][0] = cov[0][2];
    cov[2][1] = cov[1][2];
    
    cov /= float(count - 1);
    
    // 3. SOLVE EIGEN-DECOMPOSITION
    vec3 normal;
    float curvature;
    solve_eigen(cov, normal, curvature);
    
    // Enforce consistency: Normal points up (Y > 0)
    if (dot(normal, vec3(0.0, 1.0, 0.0)) < 0.0) normal = -normal;
    
    output_data.data[g_id] = vec4(normal, curvature);
}
