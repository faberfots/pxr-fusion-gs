#[compute]
#version 450
layout(local_size_x=256) in;
layout(std430,set=0,binding=0) readonly buffer Input { float source[]; };
layout(std430,set=0,binding=1) writeonly buffer Output { float result_data[]; };
layout(std430,set=0,binding=2) readonly buffer Parameters { float p[]; };
layout(std430,set=0,binding=3) buffer Status { uint invalid; };
layout(std430,set=0,binding=4) writeonly buffer Summary { vec4 summary[]; };
struct TimeSpan { uint start; uint end; float created; uint reserved; };
layout(std430,set=0,binding=5) readonly buffer Times { TimeSpan times[]; };
shared vec4 lows[256];
shared vec4 highs[256];
shared vec4 sums[256];
bool finite_value(float value) { return !isnan(value)&&!isinf(value); }
void main() {
 uint id=gl_GlobalInvocationID.x, lane=gl_LocalInvocationID.x;
 uint count=uint(p[20]), properties=uint(p[19]);
 bool binary=p[71]>0.5;
 vec3 position=vec3(0);
 bool valid=id<count;
 if(valid) {
  uint v=id*properties,b=id*60u;
  for(uint j=0u;j<properties;++j) valid=finite_value(source[v+j])&&valid;
  if(binary) {
   valid=valid&&source[v+10u]>=0.0&&source[v+10u]<=1.0;
   if(valid) { for(uint j=0u;j<60u;++j) result_data[b+j]=source[v+j];position=vec3(source[v],source[v+1u],source[v+2u]); }
  } else {
   vec3 scale=vec3(source[v+uint(p[3])],source[v+uint(p[4])],source[v+uint(p[5])]);
   vec4 q=vec4(source[v+uint(p[7])],source[v+uint(p[8])],source[v+uint(p[9])],source[v+uint(p[6])]);
   float length_squared=dot(q,q);
   valid=valid&&all(lessThanEqual(scale,vec3(44.0)))&&length_squared>=1e-8&&finite_value(length_squared);
   if(valid) {
    q*=inversesqrt(length_squared);
    float x=q.x,y=q.y,z=q.z,w=q.w;
    mat3 rotation=mat3(vec3(1.0-2.0*(y*y+z*z),2.0*(x*y+w*z),2.0*(x*z-w*y)),
                       vec3(2.0*(x*y-w*z),1.0-2.0*(x*x+z*z),2.0*(y*z+w*x)),
                       vec3(2.0*(x*z+w*y),2.0*(y*z-w*x),1.0-2.0*(x*x+y*y)));
    vec3 sigma=exp(scale);
    mat3 matrix=rotation*mat3(vec3(sigma.x,0,0),vec3(0,sigma.y,0),vec3(0,0,sigma.z));
    mat3 covariance=matrix*transpose(matrix);
    for(uint j=0u;j<60u;++j) result_data[b+j]=0.0;
    position=vec3(source[v+uint(p[0])],source[v+uint(p[1])],source[v+uint(p[2])]);
    result_data[b]=position.x;result_data[b+1u]=position.y;result_data[b+2u]=position.z;
    result_data[b+4u]=covariance[0][0];result_data[b+5u]=covariance[1][0];result_data[b+6u]=covariance[2][0];
    result_data[b+7u]=covariance[1][1];result_data[b+8u]=covariance[2][1];result_data[b+9u]=covariance[2][2];
    result_data[b+10u]=1.0/(1.0+exp(-clamp(source[v+uint(p[10])],-80.0,80.0)));
    for(uint channel=0u;channel<3u;++channel) {
     result_data[b+12u+channel]=p[17]>0.5?source[v+uint(p[11u+channel])]:(clamp(source[v+uint(p[14u+channel])]/p[23u+channel],0.0,1.0)-0.5)/0.28209479177387814;
    }
    uint coefficients=uint(p[18]);
    for(uint j=0u;j<coefficients;++j) for(uint channel=0u;channel<3u;++channel) result_data[b+15u+j*3u+channel]=source[v+uint(p[26u+channel*coefficients+j])];
   }
  }
  if(valid) {
   float created=p[22];
   if(binary&&p[17]>0.5) {
    uint index=id+floatBitsToUint(p[0]);int lo=0,hi=int(p[18])-1;bool found=false;
    while(lo<=hi) { int middle=(lo+hi)/2;if(index<times[middle].start)hi=middle-1;else if(index>=times[middle].end)lo=middle+1;else {created=times[middle].created;found=true;break;} }
    if(!found)atomicOr(invalid,2u);
   }
   result_data[b+3u]=created;result_data[b+11u]=p[21];
  }
  else atomicOr(invalid,1u);
 }
 lows[lane]=vec4(valid?position:vec3(3.402823e38),0);
 highs[lane]=vec4(valid?position:vec3(-3.402823e38),0);
 sums[lane]=vec4(valid?position:vec3(0),0);
 barrier();
 for(uint stride=128u;stride>0u;stride>>=1u) {
  if(lane<stride) { lows[lane]=min(lows[lane],lows[lane+stride]);highs[lane]=max(highs[lane],highs[lane+stride]);sums[lane]+=sums[lane+stride]; }
  barrier();
 }
 if(lane==0u) { uint out_index=gl_WorkGroupID.x*3u;summary[out_index]=lows[0];summary[out_index+1u]=highs[0];summary[out_index+2u]=sums[0]; }
}
