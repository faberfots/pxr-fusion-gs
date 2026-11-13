#[compute]
#version 450
layout(constant_id=0) const uint TILE=16u;
layout(local_size_x=16,local_size_y=16,local_size_x_id=4,local_size_y_id=5) in;
const uint CHUNK=128u;
struct RasterData { vec4 mean_conic; vec4 color; vec4 world_depth; vec4 extra; };
layout(std430,set=0,binding=0) readonly buffer Culled { RasterData splats[]; };
layout(std430,set=0,binding=1) readonly buffer Values { uint values[]; };
layout(std430,set=0,binding=2) readonly buffer Bounds { uvec2 bounds[]; };
layout(rg32f,set=0,binding=3) uniform writeonly image2D shadow_map;
layout(std430,set=0,binding=4) readonly buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(std140,set=0,binding=5) uniform Uniforms { vec4 camera_scale; uvec4 dims_population; vec4 time_options; uvec4 target; mat4 inverse_projection; };
shared RasterData shared_splats[CHUNK];
shared uint active_pixels;
void main() {
	if(overflow!=0u) return; // Preserve the last complete frame on overflow.
	uvec2 pixel=gl_GlobalInvocationID.xy;
	uint lane=gl_LocalInvocationIndex;
	bool inside=all(lessThan(pixel,dims_population.xy));
	uint grid_x=(dims_population.x+TILE-1u)/TILE;
	uint tile=gl_WorkGroupID.y*grid_x+gl_WorkGroupID.x;
	uvec2 range=bounds[tile];
	range=min(range,uvec2(count));
	float last_depth=0.0;
 float depths[16];
 float transmission[16];
 uint event_count=0u;
 for(uint j=0u;j<16u;++j){depths[j]=1e30;transmission[j]=1.0;}
	float transmittance=1.0;
	vec3 color=vec3(0);
	vec3 hit=vec3(0);
	float best_weight=0.0;
	float best_instance=0.0;
	for(uint offset=range.x;offset<range.y;offset+=CHUNK) {
		uint length=min(CHUNK,range.y-offset);
		for(uint i=lane;i<length;i+=gl_WorkGroupSize.x*gl_WorkGroupSize.y) shared_splats[i]=splats[values[offset+i]];
		barrier();
		if(inside && transmittance>1.0/255.0) {
			for(uint i=0u;i<length && transmittance>1.0/255.0;++i) {
				RasterData splat=shared_splats[i];

				vec2 delta=splat.mean_conic.xy-vec2(pixel);
				float power=-0.5*(splat.mean_conic.z*delta.x*delta.x+splat.extra.x*delta.y*delta.y)-splat.mean_conic.w*delta.x*delta.y;
				if(power>0.0) continue;
				float alpha=min(0.999,splat.color.a*exp(power));
				if(alpha<1.0/255.0) continue;
				float weight=alpha*transmittance;
				color+=splat.color.rgb*weight;
				if(weight>best_weight) { best_weight=weight; hit=splat.world_depth.xyz; best_instance=splat.extra.z; }
				transmittance*=1.0-alpha;
    last_depth=splat.world_depth.w;
    while(event_count<15u && (1.0-transmittance)>=float(event_count+1u)/16.0) {
     depths[event_count]=last_depth;transmission[event_count]=transmittance;++event_count;
    }
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
  if(last_depth>0.0) {depths[event_count]=last_depth;transmission[event_count]=transmittance;}
  for(uint j=0u;j<16u;++j) imageStore(shadow_map,ivec2(pixel.x+dims_population.x*j,pixel.y),vec4(depths[j],transmission[j],0,0));
 }
}
