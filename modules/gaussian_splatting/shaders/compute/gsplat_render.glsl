#[compute]
#version 450
layout(constant_id=0) const uint TILE=16u;
layout(local_size_x=16,local_size_y=16,local_size_x_id=4,local_size_y_id=5) in;
const uint CHUNK=128u;
struct RasterData { vec4 mean_conic; vec4 color; vec4 world_depth; vec4 extra; };
layout(std430,set=0,binding=0) readonly buffer Culled { RasterData splats[]; };
layout(std430,set=0,binding=1) readonly buffer Values { uint values[]; };
layout(std430,set=0,binding=2) readonly buffer Bounds { uvec2 bounds[]; };
layout(std430,set=0,binding=3) writeonly buffer Pick { vec4 picked; };
layout(rgba32f,set=0,binding=4) uniform writeonly image2D output_image;
layout(std430,set=0,binding=5) readonly buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(std140,set=0,binding=6) uniform Uniforms { vec4 camera_scale; uvec4 dims_population; vec4 time_options; uvec4 target; mat4 inverse_projection; };
layout(set=0,binding=7) uniform sampler2D scene_depth;
shared RasterData shared_splats[CHUNK];
shared uint active_pixels;
float occluder_depth(vec2 pixel) {
	if(time_options.z<0.5) return 1e30;
	vec2 uv=(pixel+0.5)/vec2(dims_population.xy);
	float raw=textureLod(scene_depth,uv,0.0).r;
	if(raw<=0.0) return 1e30;
	// Godot RD depth is reversed [0,1]; Camera3D projection uses OpenGL [-1,1].
	vec4 position=inverse_projection*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,1.0-raw*2.0,1.0);
	return -position.z/position.w;
}
void main() {
	if(overflow!=0u) return; // Preserve the last complete frame on overflow.
	uvec2 pixel=gl_GlobalInvocationID.xy;
	uint lane=gl_LocalInvocationIndex;
	bool inside=all(lessThan(pixel,dims_population.xy));
	uint grid_x=(dims_population.x+TILE-1u)/TILE;
	uint tile=gl_WorkGroupID.y*grid_x+gl_WorkGroupID.x;
	uvec2 range=bounds[tile];
	range=min(range,uvec2(count));
	float limit=inside?occluder_depth(vec2(pixel)):0.0;
	float transmittance=1.0;
	vec3 color=vec3(0);
	vec3 hit=vec3(0);
	float best_weight=0.0;
	for(uint offset=range.x;offset<range.y;offset+=CHUNK) {
		uint length=min(CHUNK,range.y-offset);
		for(uint i=lane;i<length;i+=gl_WorkGroupSize.x*gl_WorkGroupSize.y) shared_splats[i]=splats[values[offset+i]];
		barrier();
		if(inside && transmittance>1.0/255.0) {
			for(uint i=0u;i<length && transmittance>1.0/255.0;++i) {
				RasterData splat=shared_splats[i];
				if(splat.world_depth.w>limit+0.001) continue;
				vec2 delta=splat.mean_conic.xy-vec2(pixel);
				float power=-0.5*(splat.mean_conic.z*delta.x*delta.x+splat.extra.x*delta.y*delta.y)-splat.mean_conic.w*delta.x*delta.y;
				if(power>0.0) continue;
				float alpha=min(0.999,splat.color.a*exp(power));
				if(alpha<1.0/255.0) continue;
				float weight=alpha*transmittance;
				color+=mix(splat.color.rgb,vec3(0.1,0.6,1.0),splat.extra.y*0.25)*weight;
				if(weight>best_weight) { best_weight=weight; hit=splat.world_depth.xyz; }
				transmittance*=1.0-alpha;
			}
		}
		barrier();
		if(lane==0u) active_pixels=0u;
		barrier();
		if(inside && transmittance>1.0/255.0) atomicAdd(active_pixels,1u);
		barrier();
		if(active_pixels==0u) break;
	}
	if(inside) {
		float alpha=1.0-transmittance;
		if(time_options.y>0.0) color+=mix(vec3(0,0,1),vec3(1,0.2,0.2),clamp(float(range.y-range.x)*0.0005,0.0,1.0))*alpha*time_options.y;
		imageStore(output_image,ivec2(pixel),vec4(color,alpha));
		if(all(equal(pixel,target.xy))) picked=vec4(hit,best_weight>0.0?1.0:0.0);
	}
}
