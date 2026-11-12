#[compute]
#version 450
layout(constant_id=2) const uint WG=256u;
layout(constant_id=3) const uint DIV=4u;
const uint PART=WG*DIV;
layout(local_size_x=256,local_size_x_id=2) in;
layout(std430,set=0,binding=0) readonly buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(std430,set=0,binding=1) buffer Keys { uvec2 keys[]; };
layout(std430,set=0,binding=2) buffer Values { uint values[]; };
layout(push_constant) uniform Push { uint pass; uint input_offset; uint output_offset; uint capacity; };
shared uvec2 local_keys[PART];
shared uint local_values[PART];
shared uint scan[PART];
shared uvec2 temp_keys[PART];
shared uint temp_values[PART];
shared uint bin_start[256];
uint digit(uvec2 key) {
	uint word=pass<4u?key.x:key.y;
	return (word>>((pass%4u)*8u))&255u;
}
void main() {
	uint lane=gl_LocalInvocationID.x;
	uint block_index=gl_WorkGroupID.x;
	uint start=block_index*PART;
	if(start>=count) return;
	uint length=min(PART,count-start);
	for(uint i=lane;i<PART;i+=WG) {
		local_keys[i]=i<length?keys[input_offset+start+i]:uvec2(0xffffffffu);
		local_values[i]=i<length?values[input_offset+start+i]:0u;
	}
	barrier();
	// Stable local binary partitions produce stable byte ordering on every subgroup width.
	for(uint bit=0u;bit<8u;++bit) {
		for(uint i=lane;i<PART;i+=WG) scan[i]=((digit(local_keys[i])>>bit)&1u)==0u?1u:0u;
		barrier();
		for(uint distance=1u;distance<PART;distance*=2u) {
			for(uint i=lane;i<PART;i+=WG) {
				uint index=(i+1u)*distance*2u-1u;
				if(index<PART) scan[index]+=scan[index-distance];
			}
			barrier();
		}
		uint zeros=scan[PART-1u];
		barrier();
		if(lane==0u) scan[PART-1u]=0u;
		barrier();
		for(uint distance=PART/2u;distance>0u;distance/=2u) {
			for(uint i=lane;i<PART;i+=WG) {
				uint index=(i+1u)*distance*2u-1u;
				if(index<PART) {
					uint left=scan[index-distance];
					scan[index-distance]=scan[index];
					scan[index]+=left;
				}
			}
			barrier();
		}
		for(uint i=lane;i<PART;i+=WG) {
			bool zero=((digit(local_keys[i])>>bit)&1u)==0u;
			uint destination=zero?scan[i]:zeros+i-scan[i];
			temp_keys[destination]=local_keys[i];
			temp_values[destination]=local_values[i];
		}
		barrier();
		for(uint i=lane;i<PART;i+=WG) {
			local_keys[i]=temp_keys[i];
			local_values[i]=temp_values[i];
		}
		barrier();
	}
	for(uint i=lane;i<PART;i+=WG) {
		uint d=digit(local_keys[i]);
		if(i==0u || d!=digit(local_keys[i-1u])) bin_start[d]=i;
	}
	barrier();
	for(uint i=lane;i<length;i+=WG) {
		uint d=digit(local_keys[i]);
		uint destination=histogram[block_index*256u+d]+i-bin_start[d];
		if(destination<count && destination<capacity) {
			keys[output_offset+destination]=local_keys[i];
			values[output_offset+destination]=local_values[i];
		}
	}
}
