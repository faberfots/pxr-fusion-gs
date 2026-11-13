#[compute]
#version 450
layout(constant_id=0) const uint TILE=16u;
layout(constant_id=2) const uint SORT_WG=256u;
layout(constant_id=3) const uint SORT_DIV=4u;
layout(local_size_x=256,local_size_x_id=1) in;
struct Splat { vec3 position; float time; float covariance[6]; float opacity; float instance_id; float sh[48]; };
struct RasterData { vec4 mean_conic; vec4 color; vec4 world_depth; vec4 extra; };
layout(std430,set=0,binding=0) readonly buffer Splats { Splat splats[]; };
layout(std430,set=0,binding=1) writeonly buffer Culled { RasterData projected_splats[]; };
layout(std430,set=0,binding=2) buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(std430,set=0,binding=3) writeonly buffer Keys { uvec2 keys[]; };
layout(std430,set=0,binding=4) writeonly buffer Values { uint values[]; };
layout(std430,set=0,binding=5) buffer Grid { uint grid[]; };
layout(std140,set=0,binding=6) uniform Uniforms { vec4 camera_scale; uvec4 dims_population; vec4 time_options; uvec4 target; mat4 inverse_projection; };
layout(std430,set=0,binding=7) readonly buffer Instances { mat4 transforms[]; };
layout(std430,set=0,binding=8) readonly buffer ModelFlags { uint model_flags[]; };
layout(push_constant) uniform Push { mat4 view; mat4 projection; };
vec3 sh_color(vec3 d, float coefficients[48]) {
	float x=d.x,y=d.y,z=d.z,xx=x*x,yy=y*y,zz=z*z;
	float basis[16]=float[16](0.28209479177387814,-0.4886025119029199*y,0.4886025119029199*z,-0.4886025119029199*x,
		1.0925484305920792*x*y,-1.0925484305920792*y*z,0.31539156525252005*(2.0*zz-xx-yy),-1.0925484305920792*x*z,0.5462742152960396*(xx-yy),
		-0.5900435899266435*y*(3.0*xx-yy),2.890611442640554*x*y*z,-0.4570457994644658*y*(4.0*zz-xx-yy),0.3731763325901154*z*(2.0*zz-3.0*xx-3.0*yy),-0.4570457994644658*x*(4.0*zz-xx-yy),1.445305721320277*z*(xx-yy),-0.5900435899266435*x*(xx-3.0*yy));
	vec3 color=vec3(0.5);
	for(int i=0;i<16;++i) color+=basis[i]*vec3(coefficients[i*3],coefficients[i*3+1],coefficients[i*3+2]);
	color=max(color,vec3(0));
	if(time_options.w>0.5) color=mix(color/12.92,pow((color+0.055)/1.055,vec3(2.4)),greaterThan(color,vec3(0.04045)));
	return color;
}
bool reserve_pairs(uint amount, out uint offset) {
	uint capacity=dims_population.w;
	uint old=atomicAdd(count,0u);
	for(;;) {
		if(amount>capacity || old>capacity-amount) { atomicOr(overflow,1u); return false; }
		uint previous=atomicCompSwap(count,old,old+amount);
		if(previous==old) { offset=old; return true; }
		old=previous;
	}
}
uint project_splat(uint id, out RasterData data, out ivec2 low, out ivec2 high) {
	if(id>=dims_population.z || id>=splats.length()) return 0u;
	Splat splat=splats[id];
	if(splat.opacity<=0.0 || isnan(splat.opacity)) return 0u;
	uint instance=uint(splat.instance_id);
	if(instance>=transforms.length() || instance>=model_flags.length() || (model_flags[instance]&1u)==0u) return 0u;
	mat4 model=transforms[instance];
	if(model[3].w==0.0) return 0u;
	mat3 linear=mat3(model)*camera_scale.w;
	if(abs(determinant(linear))<1e-20) return 0u;
	vec3 world=(model*vec4(splat.position,1.0)).xyz*camera_scale.w;
	vec4 mean=view*vec4(world,1.0);
	vec4 clip=projection*mean;
	if(clip.w<=0.0 || mean.z>=-0.0001 || any(isnan(clip)) || any(isinf(clip))) return 0u;
	// Only depth planes reject the mean; screen culling uses the complete Gaussian footprint.
	if(clip.z < -clip.w || clip.z > clip.w) return 0u;
	mat3 local_cov=mat3(splat.covariance[0],splat.covariance[1],splat.covariance[2],splat.covariance[1],splat.covariance[3],splat.covariance[4],splat.covariance[2],splat.covariance[4],splat.covariance[5]);
	mat3 world_cov=linear*local_cov*transpose(linear);
	mat3 camera_cov=mat3(view)*world_cov*transpose(mat3(view));
	vec3 dw=vec3(projection[0][3],projection[1][3],projection[2][3]);
	vec3 dx=vec3(projection[0][0],projection[1][0],projection[2][0]);
	vec3 dy=vec3(projection[0][1],projection[1][1],projection[2][1]);
	// Bound only the covariance linearization outside the perspective field of view.
	// Keep the true mean for screen placement and footprint intersection.
	vec4 covariance_clip=clip;
	if(abs(projection[2][3])>0.5) covariance_clip.xy=clamp(clip.xy,vec2(-1.3*clip.w),vec2(1.3*clip.w));
	vec3 jx=(dx*clip.w-covariance_clip.x*dw)/(clip.w*clip.w)*(float(dims_population.x)*0.5);
	vec3 jy=-(dy*clip.w-covariance_clip.y*dw)/(clip.w*clip.w)*(float(dims_population.y)*0.5);
	float a=dot(jx,camera_cov*jx)+0.3;
	float b=dot(jx,camera_cov*jy);
	float c=dot(jy,camera_cov*jy)+0.3;
	float det=a*c-b*b;
	if(det<=1e-12 || isnan(det) || isinf(det)) return 0u;
	// Lighting caches use source opacity, independent of the viewport load reveal.
	float opacity=splat.opacity;
	if(opacity<1.0/255.0) return 0u;
	float radius=ceil(sqrt(max(0.0,-2.0*log((1.0/255.0)/opacity)))*sqrt(max(a,c)+abs(b)));
	vec2 image=vec2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5)*vec2(dims_population.xy)-0.5;
	uvec2 grid_size=(dims_population.xy+TILE-1u)/TILE;
	low=clamp(ivec2(floor((image-radius)/float(TILE))),ivec2(0),ivec2(grid_size));
	high=clamp(ivec2(ceil((image+radius+1.0)/float(TILE))),ivec2(0),ivec2(grid_size));
	uint amount=uint(high.x-low.x)*uint(high.y-low.y);
	if(amount==0u) return 0u;
	vec3 direction=normalize(inverse(linear)*(world-camera_scale.xyz));
	data.mean_conic=vec4(image,c/det,-b/det);
	data.color=vec4(0,0,0,opacity);
	data.world_depth=vec4(world,-mean.z);
	data.extra=vec4(a/det,instance==target.w && target.w>0u?1.0:0.0,float(instance),0.0);
	return amount;
}
// Reserve once per workgroup. Per-Gaussian compare/exchange loops serialize
// millions of visible splats against one global counter on large environments.
shared uint prefix[256];
shared uint group_offset;
shared uint group_accepted;
shared uint group_projected;
void main() {
	uint id=gl_GlobalInvocationID.x;
	uint lane=gl_LocalInvocationID.x;
	RasterData data;
	ivec2 low, high;
	uint amount=project_splat(id,data,low,high);
	prefix[lane]=amount;
	if(lane==0u) group_projected=0u;
	barrier();
	if(amount>0u) atomicAdd(group_projected,1u);
	for(uint distance=1u;distance<gl_WorkGroupSize.x;distance*=2u) {
		uint addend=lane>=distance?prefix[lane-distance]:0u;
		barrier();
		prefix[lane]+=addend;
		barrier();
	}
	if(lane==0u) {
		uint total=prefix[gl_WorkGroupSize.x-1u];
		group_accepted=total>0u && reserve_pairs(total,group_offset)?1u:0u;
		if(group_accepted!=0u) {
			uint end=group_offset+total;
			atomicMax(grid[0],(end+SORT_WG*SORT_DIV-1u)/(SORT_WG*SORT_DIV));
			atomicMax(grid[3],(end+gl_WorkGroupSize.x-1u)/gl_WorkGroupSize.x);
			atomicAdd(projected,group_projected);
		}
	}
	barrier();
	if(amount==0u || group_accepted==0u) return;
	projected_splats[id]=data;
	uint offset=group_offset+prefix[lane]-amount;
	uint grid_x=(dims_population.x+TILE-1u)/TILE;
	for(int y=low.y;y<high.y;++y) for(int x=low.x;x<high.x;++x) {
		keys[offset]=uvec2(floatBitsToUint(data.world_depth.w),uint(y)*grid_x+uint(x));
		values[offset]=id;
		++offset;
	}
}
