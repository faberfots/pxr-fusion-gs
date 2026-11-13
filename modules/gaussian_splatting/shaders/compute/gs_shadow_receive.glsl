#[compute]
#version 450
layout(local_size_x=256) in;
struct RasterData { vec4 mean_conic; vec4 color; vec4 world_depth; vec4 extra; };
layout(std430,set=0,binding=0) buffer Culled { RasterData splats[]; };
layout(std430,set=0,binding=1) readonly buffer Flags { uint flags[]; };
layout(set=0,binding=2) uniform sampler2D shadow_map;
layout(std140,set=0,binding=3) uniform Shadow { mat4 view; mat4 projection; vec4 options; uvec4 population; };
float visibility(vec2 uv,float depth) {
 ivec2 pixel=clamp(ivec2(uv*options.z),ivec2(0),ivec2(int(options.z)-1));
 float transmission=1.0;
 for(int i=0;i<16;++i) {
  vec2 event=texelFetch(shadow_map,ivec2(pixel.x+i*int(options.z),pixel.y),0).rg;
  if(event.x>depth-options.y)break;
  transmission=event.y;
 }
 return transmission;
}
void main() {
 uint id=gl_GlobalInvocationID.x;
 if(id>=population.x || id>=splats.length())return;
 uint model=uint(splats[id].extra.z);
 if(model>=flags.length() || (flags[model]&2u)==0u)return;
 vec4 position=view*vec4(splats[id].world_depth.xyz,1.0);
 vec4 clip=projection*position;
 vec2 uv=vec2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
 if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1))))return;
 float t=0.0;
 for(int y=-1;y<=1;++y)for(int x=-1;x<=1;++x)t+=visibility(uv+vec2(x,y)/options.z,-position.z);
 splats[id].color.rgb*=mix(1.0,t/9.0,options.x);
}
