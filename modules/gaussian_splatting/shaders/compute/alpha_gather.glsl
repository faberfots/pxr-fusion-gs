#[vertex]
#version 450
layout(std430,set=0,binding=0) readonly buffer Vertices { vec4 vertices[]; };
layout(std140,set=0,binding=1) uniform Camera { mat4 view; mat4 projection; };
layout(push_constant,std430) uniform Draw { mat4 model; vec4 base_color; uvec4 options; } draw;
layout(location=0) out vec2 uv;
layout(location=1) out vec4 vertex_color;
layout(location=2) out float linear_depth;
void main() {
 uint v=uint(gl_VertexIndex)*3u;
 vec4 camera_position=view*draw.model*vec4(vertices[v].xyz,1);
 vec4 clip=projection*camera_position;
 gl_Position=vec4(clip.x,-clip.y,(clip.w-clip.z)*0.5,clip.w);
 uv=vertices[v+1u].xy;
 vertex_color=vec4(vertices[v+1u].zw,vertices[v+2u].xy);
 linear_depth=-camera_position.z;
}
#[fragment]
#version 450
layout(early_fragment_tests) in;
layout(location=0) in vec2 uv;
layout(location=1) in vec4 vertex_color;
layout(location=2) in float linear_depth;
layout(std430,set=0,binding=2) buffer Heads { uint heads[]; };
struct Fragment { vec4 color; uvec4 link; };
layout(std430,set=0,binding=3) writeonly buffer Fragments { Fragment fragments[]; };
layout(std430,set=0,binding=4) buffer Meta { uint count; uint overflow; uint unused; uint unused2; };
layout(set=0,binding=5) uniform sampler2D albedo_texture;
layout(push_constant,std430) uniform Draw { mat4 model; vec4 base_color; uvec4 options; } draw;
void main() {
 if(draw.options.z==0u && !gl_FrontFacing) discard;
 if(draw.options.z==1u && gl_FrontFacing) discard;
 vec4 color=draw.base_color*vertex_color*texture(albedo_texture,uv);
 if(color.a<=1.0/255.0) discard;
 uint index=atomicAdd(count,1u);
 if(index>=draw.options.y) { atomicOr(overflow,2u);discard; }
 uint pixel=uint(gl_FragCoord.y)*draw.options.x+uint(gl_FragCoord.x);
 uint previous=atomicExchange(heads[pixel],index+1u);
 fragments[index].color=vec4(color.rgb,clamp(color.a,0,0.999));
 fragments[index].link=uvec4(floatBitsToUint(linear_depth),previous,0,0);
}
