#[compute]
#version 450
layout(local_size_x=256,local_size_x_id=1) in;
layout(std430,set=0,binding=0) readonly buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(std430,set=0,binding=1) readonly buffer Keys { uvec2 keys[]; };
layout(std430,set=0,binding=2) writeonly buffer Bounds { uvec2 bounds[]; };
void main() {
	uint index=gl_GlobalInvocationID.x;
	if(index>=count) return;
	uint tile=keys[index].y;
	if(tile>=bounds.length()) return;
	if(index==0u || keys[index-1u].y!=tile) bounds[tile].x=index;
	if(index+1u==count || keys[index+1u].y!=tile) bounds[tile].y=index+1u;
}
