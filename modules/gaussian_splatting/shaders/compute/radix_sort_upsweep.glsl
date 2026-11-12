#[compute]
#version 450
// Portable stable 64-bit-key radix sort. No subgroup-width assumptions.
layout(constant_id=2) const uint WG = 256u;
layout(constant_id=3) const uint DIV = 4u;
const uint PART = WG * DIV;
layout(local_size_x=256, local_size_x_id=2) in;
layout(std430,set=0,binding=0) buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(std430,set=0,binding=1) readonly buffer Keys { uvec2 keys[]; };
layout(push_constant) uniform Push { uint pass; uint input_offset; uint output_offset; uint capacity; };
shared uint bins[256];
void main() {
	uint lane=gl_LocalInvocationID.x;
	uint block_index=gl_WorkGroupID.x;
	uint partitions=(count+PART-1u)/PART;
	// Grid is reset every frame; this uniform exit is safe for the whole workgroup.
	if(block_index>=partitions) return;
	for(uint b=lane;b<256u;b+=WG) bins[b]=0u;
	barrier();
	for(uint i=lane;i<PART;i+=WG) {
		uint index=block_index*PART+i;
		if(index<count) {
			uvec2 key=keys[input_offset+index];
			uint word=pass<4u?key.x:key.y;
			atomicAdd(bins[(word>>((pass%4u)*8u))&255u],1u);
		}
	}
	barrier();
	for(uint b=lane;b<256u;b+=WG) histogram[block_index*256u+b]=bins[b];
}
