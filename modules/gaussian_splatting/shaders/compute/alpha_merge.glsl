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
layout(std430,set=0,binding=8) readonly buffer Heads { uint heads[]; };
struct MeshFragment { vec4 color; uvec4 link; };
layout(std430,set=0,binding=9) readonly buffer MeshFragments { MeshFragment mesh_fragments[]; };
layout(std430,set=0,binding=10) readonly buffer MeshMeta { uint mesh_count; uint mesh_overflow; uint mesh_capacity; uint mesh_pad; };
layout(set=0,binding=11) uniform sampler2D source_gaussians;
layout(std140,set=0,binding=12) uniform Grade { vec4 exposure_contrast_saturation_temperature; vec4 black_white_sharpness_pad; vec4 tint; } grade;
vec3 straight(vec4 value) { return value.a>0.00001?value.rgb/value.a:vec3(0); }
vec3 color_correction(vec2 pixel) {
 vec2 uv=(pixel+0.5)/vec2(dims_population.xy);
 vec3 raw=straight(textureLod(source_gaussians,uv,0));
 vec3 color=raw;
 vec2 texel=1.0/vec2(dims_population.xy);
 vec3 sum=straight(textureLod(source_gaussians,uv+vec2(texel.x,0),0));
 sum+=straight(textureLod(source_gaussians,uv-vec2(texel.x,0),0));
 sum+=straight(textureLod(source_gaussians,uv+vec2(0,texel.y),0));
 sum+=straight(textureLod(source_gaussians,uv-vec2(0,texel.y),0));
 color+=grade.black_white_sharpness_pad.z*(color-sum*0.25);
 color=max(vec3(0),(color-grade.black_white_sharpness_pad.x)/max(grade.black_white_sharpness_pad.y-grade.black_white_sharpness_pad.x,0.001));
 color*=grade.exposure_contrast_saturation_temperature.x;
 color=mix(vec3(0.18),color,grade.exposure_contrast_saturation_temperature.y);
 color=mix(vec3(dot(color,vec3(0.2126,0.7152,0.0722))),color,grade.exposure_contrast_saturation_temperature.z);
 color=(color+grade.exposure_contrast_saturation_temperature.w*vec3(0.08,0.02,-0.08))*grade.tint.rgb;
 return max(vec3(0),color)-raw;
}
uint next_fragment(uint head,uvec2 previous) {
 uint result=0xffffffffu;
 uvec2 best=uvec2(0xffffffffu);
 uint visited=0u;
 while(head!=0u && head<=mesh_capacity && visited++<min(mesh_count,mesh_capacity)) {
  uint index=head-1u;
  uvec2 key=uvec2(mesh_fragments[index].link.x,index);
  if((key.x>previous.x || (key.x==previous.x && key.y>previous.y)) && (key.x<best.x || (key.x==best.x && key.y<best.y))) { best=key;result=index; }
  head=mesh_fragments[index].link.y;
 }
 return result;
}
void composite_meshes(uint head,float limit,inout uint current,inout vec3 color,inout float transmittance) {
 while(current!=0xffffffffu && uintBitsToFloat(mesh_fragments[current].link.x)<=limit && transmittance>1.0/255.0) {
  MeshFragment fragment=mesh_fragments[current];
  color+=fragment.color.rgb*fragment.color.a*transmittance;
  transmittance*=1.0-fragment.color.a;
  current=next_fragment(head,uvec2(fragment.link.x,current));
 }
}
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
	if(overflow!=0u || mesh_overflow!=0u) return; // Preserve the last complete frame on overflow.
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
	float best_instance=0.0;
 uint head=inside?heads[pixel.y*dims_population.x+pixel.x]:0u;
 uint current=inside?next_fragment(head,uvec2(0)):0xffffffffu;
 vec3 correction=inside?color_correction(vec2(pixel)):vec3(0);
	for(uint offset=range.x;offset<range.y;offset+=CHUNK) {
		uint length=min(CHUNK,range.y-offset);
		for(uint i=lane;i<length;i+=gl_WorkGroupSize.x*gl_WorkGroupSize.y) shared_splats[i]=splats[values[offset+i]];
		barrier();
		if(inside && transmittance>1.0/255.0) {
			for(uint i=0u;i<length && transmittance>1.0/255.0;++i) {
				RasterData splat=shared_splats[i];
				composite_meshes(head,min(splat.world_depth.w,limit),current,color,transmittance);
				if(splat.world_depth.w>limit+0.001) continue;
				vec2 delta=splat.mean_conic.xy-vec2(pixel);
				float power=-0.5*(splat.mean_conic.z*delta.x*delta.x+splat.extra.x*delta.y*delta.y)-splat.mean_conic.w*delta.x*delta.y;
				if(power>0.0) continue;
				float alpha=min(0.999,splat.color.a*exp(power));
				if(alpha<1.0/255.0) continue;
				float weight=alpha*transmittance;
				color+=max(vec3(0),splat.color.rgb+correction)*weight;
				if(weight>best_weight) { best_weight=weight; hit=splat.world_depth.xyz; best_instance=splat.extra.z; }
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
		composite_meshes(head,limit,current,color,transmittance);
		float alpha=1.0-transmittance;
		if(time_options.y>0.0) color+=mix(vec3(0,0,1),vec3(1,0.2,0.2),clamp(float(range.y-range.x)*0.0005,0.0,1.0))*alpha*time_options.y;
		imageStore(output_image,ivec2(pixel),vec4(color,alpha));
		if(all(equal(pixel,target.xy))) picked=vec4(hit,best_weight>0.0?best_instance:0.0);
	}
}
