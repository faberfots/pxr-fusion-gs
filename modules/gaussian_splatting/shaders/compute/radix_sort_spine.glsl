#[compute]
#version 450
layout(constant_id=2) const uint WG=256u;
layout(constant_id=3) const uint DIV=4u;
const uint PART=WG*DIV;
layout(local_size_x=256,local_size_x_id=2) in;
layout(std430,set=0,binding=0) buffer Meta { uint count; uint overflow; uint projected; uint reserved; uint histogram[]; };
layout(push_constant) uniform Push { uint pass; uint input_offset; uint output_offset; uint capacity; };
shared uint totals[256];
void main() {
	uint lane=gl_LocalInvocationID.x;
	uint partitions=(count+PART-1u)/PART;
	for(uint digit=lane;digit<256u;digit+=WG) {
		uint sum=0u;
		for(uint p=0u;p<partitions;++p) sum+=histogram[p*256u+digit];
		totals[digit]=sum;
	}
	barrier();
	for(uint digit=lane;digit<256u;digit+=WG) {
		uint offset=0u;
		for(uint d=0u;d<digit;++d) offset+=totals[d];
		for(uint p=0u;p<partitions;++p) {
			uint address=p*256u+digit;
			uint value=histogram[address];
			histogram[address]=offset;
			offset+=value;
		}
	}
}
