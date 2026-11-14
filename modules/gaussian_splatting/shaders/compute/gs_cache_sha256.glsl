#[compute]
#version 450
// FIPS 180-4 SHA-256, independent bounded leaves. Bytes remain fully verified.
layout(local_size_x=64) in;
layout(std430,set=0,binding=0) readonly buffer Input { uint words[]; };
layout(std430,set=0,binding=1) writeonly buffer Output { uint hashes[]; };
layout(push_constant) uniform Push { uint bytes; uint leaf_bytes; };
const uint K[64]=uint[64](
0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u);
uint rotate(uint x,uint n) { return (x>>n)|(x<<(32u-n)); }
uint swap_bytes(uint x) { return ((x&255u)<<24u)|((x&65280u)<<8u)|((x>>8u)&65280u)|(x>>24u); }
void main() {
 uint leaf=gl_GlobalInvocationID.x,start=leaf*leaf_bytes;
 if(start>=bytes)return;
 uint length=min(leaf_bytes,bytes-start),n=length/4u,blocks=(length+72u)/64u;
 uint H[8]=uint[8](0x6a09e667u,0xbb67ae85u,0x3c6ef372u,0xa54ff53au,0x510e527fu,0x9b05688cu,0x1f83d9abu,0x5be0cd19u);
 for(uint block=0u;block<blocks;++block) {
  uint W[16];
  for(uint j=0u;j<16u;++j) {
   uint index=block*16u+j;
   if(index<n)W[j]=swap_bytes(words[start/4u+index]);
   else if(index==n)W[j]=0x80000000u;
   else if(index==blocks*16u-1u)W[j]=length*8u;
   else W[j]=0u;
  }
  uint a=H[0],b=H[1],c=H[2],d=H[3],e=H[4],f=H[5],g=H[6],h=H[7];
  for(uint j=0u;j<64u;++j) {
   if(j>=16u) {
    uint x=W[(j+1u)&15u],y=W[(j+14u)&15u];
    W[j&15u]+=(rotate(x,7u)^rotate(x,18u)^(x>>3u))+W[(j+9u)&15u]+(rotate(y,17u)^rotate(y,19u)^(y>>10u));
   }
   uint t1=h+(rotate(e,6u)^rotate(e,11u)^rotate(e,25u))+((e&f)^((~e)&g))+K[j]+W[j&15u];
   uint t2=(rotate(a,2u)^rotate(a,13u)^rotate(a,22u))+((a&b)^(a&c)^(b&c));
   h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
  }
  H[0]+=a;H[1]+=b;H[2]+=c;H[3]+=d;H[4]+=e;H[5]+=f;H[6]+=g;H[7]+=h;
 }
 for(uint j=0u;j<8u;++j)hashes[leaf*8u+j]=swap_bytes(H[j]);
}
