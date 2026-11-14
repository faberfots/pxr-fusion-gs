shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform bool shadow_enabled=false;
// Match the receiving material: back=0, front=1, disabled=2.
uniform int receiver_cull_mode=0;
uniform sampler2D gaussian_shadow_map : filter_nearest, repeat_disable;
uniform mat4 shadow_view;
uniform mat4 shadow_projection;
uniform int shadow_resolution=512;
uniform float shadow_strength=0.65;
uniform float shadow_bias=0.02;
varying vec3 world_position;
void vertex(){
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 // Receiver overlay stays depth tested, with a small normal offset to pass
 // Forward+'s strict transparent-depth comparison against its own base pass.
 VERTEX+=NORMAL*0.001;
}
float visibility(vec2 uv,float depth){
 ivec2 pixel=clamp(ivec2(uv*float(shadow_resolution)),ivec2(0),ivec2(shadow_resolution-1));
 float transmission=1.0;
 for(int i=0;i<16;++i){
  vec2 event=texelFetch(gaussian_shadow_map,ivec2(pixel.x+i*shadow_resolution,pixel.y),0).rg;
  if(event.x>depth-shadow_bias)break;
  transmission=event.y;
 }
 return transmission;
}
void fragment(){
 if((receiver_cull_mode==0 && !FRONT_FACING)||(receiver_cull_mode==1 && FRONT_FACING))discard;
 if(!shadow_enabled)discard;
 vec4 view_position=shadow_view*vec4(world_position,1.0);
 vec4 clip=shadow_projection*view_position;
 vec2 uv=vec2(clip.x/clip.w*0.5+0.5,0.5-clip.y/clip.w*0.5);
 if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1))))discard;
 float transmission=0.0;
 for(int y=-1;y<=1;++y)for(int x=-1;x<=1;++x)
  transmission+=visibility(uv+vec2(float(x),float(y))/float(shadow_resolution),-view_position.z);
 ALBEDO=vec3(0);
 ALPHA=clamp((1.0-transmission/9.0)*shadow_strength,0.0,1.0);
}
