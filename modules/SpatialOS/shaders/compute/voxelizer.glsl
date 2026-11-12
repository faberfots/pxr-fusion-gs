#[compute]
#version 450
layout(local_size_x=256) in;
struct InputPoint { float x,y,z; uint color; };
struct Cell { uint owner,count; int qx,qy,qz; uint fx,fy,fz,cr,cg,cb,ca; };
layout(std430,set=0,binding=0) readonly buffer Input { InputPoint points[]; };
layout(std430,set=0,binding=1) buffer Grid { uint overflow; uint pad0,pad1,pad2; Cell cells[]; };
layout(push_constant) uniform Params { vec3 minimum; float size; uint count; uint capacity; };
uint hash(uvec3 p) { return (p.x*73856093u ^ p.y*19349663u ^ p.z*83492791u)%capacity; }
#define ADD_FLOAT(member,value) { uint old=member; for(;;) { uint assumed=old; old=atomicCompSwap(member,assumed,floatBitsToUint(uintBitsToFloat(assumed)+(value))); if(old==assumed) break; } }
void main() {
	uint id=gl_GlobalInvocationID.x;
	if(id>=count) return;
	vec3 pos=vec3(points[id].x,points[id].y,points[id].z);
	vec3 local=(pos-minimum)/size;
	if(any(isnan(local))||any(isinf(local))||any(greaterThan(abs(local),vec3(2147483000.0)))) { atomicOr(overflow,1u);return; }
	ivec3 q=ivec3(floor(local));
	uint start=hash(uvec3(q));
	for(uint probe=0u;probe<min(capacity,1024u);++probe) {
		uint slot=(start+probe)%capacity;
		uint owner=atomicCompSwap(cells[slot].owner,0u,id+1u);
		if(owner!=0u) {
			InputPoint existing=points[owner-1u];
			ivec3 other=ivec3(floor((vec3(existing.x,existing.y,existing.z)-minimum)/size));
			if(any(notEqual(q,other))) continue;
		} else { cells[slot].qx=q.x;cells[slot].qy=q.y;cells[slot].qz=q.z; }
		vec3 fraction=local-vec3(q);
		atomicAdd(cells[slot].count,1u);
		ADD_FLOAT(cells[slot].fx,fraction.x)
		ADD_FLOAT(cells[slot].fy,fraction.y)
		ADD_FLOAT(cells[slot].fz,fraction.z)
		uint color=points[id].color;
		ADD_FLOAT(cells[slot].cr,float((color>>24u)&255u)/255.0)
		ADD_FLOAT(cells[slot].cg,float((color>>16u)&255u)/255.0)
		ADD_FLOAT(cells[slot].cb,float((color>>8u)&255u)/255.0)
		ADD_FLOAT(cells[slot].ca,float(color&255u)/255.0)
		return;
	}
	atomicOr(overflow,1u);
}
