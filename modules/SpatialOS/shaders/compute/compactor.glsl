#[compute]
#version 450
layout(local_size_x=256) in;
struct Cell { uint owner,count; int qx,qy,qz; uint fx,fy,fz,cr,cg,cb,ca; };
layout(std430,set=0,binding=0) readonly buffer Grid { uint overflow;uint pad0,pad1,pad2;Cell cells[]; };
struct Point { vec4 position;vec4 color; };
layout(std430,set=0,binding=1) buffer Output { uint count; uint p0,p1,p2; Point points[]; };
layout(push_constant) uniform Params { vec3 minimum;float size;uint grid_size;uint capacity; };
void main() {
	uint id=gl_GlobalInvocationID.x;
	if(id>=grid_size||overflow!=0u||cells[id].count==0u) return;
	Cell c=cells[id];
	float n=float(c.count);
	uint destination=atomicAdd(count,1u);
	if(destination>=capacity) return;
	vec3 fraction=vec3(uintBitsToFloat(c.fx),uintBitsToFloat(c.fy),uintBitsToFloat(c.fz))/n;
	points[destination].position=vec4(minimum+(vec3(c.qx,c.qy,c.qz)+fraction)*size,1.0);
	points[destination].color=vec4(uintBitsToFloat(c.cr),uintBitsToFloat(c.cg),uintBitsToFloat(c.cb),uintBitsToFloat(c.ca))/n;
}
