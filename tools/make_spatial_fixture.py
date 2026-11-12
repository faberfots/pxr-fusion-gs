from pathlib import Path
import argparse,struct
parser=argparse.ArgumentParser();parser.add_argument('path',type=Path);parser.add_argument('--count',type=int,default=2000000);args=parser.parse_args()
args.path.parent.mkdir(parents=True,exist_ok=True)
with args.path.open('wb') as f:
 f.write(('ply\nformat binary_little_endian 1.0\nelement vertex %d\n'%args.count+'\n'.join('property float '+x for x in ['x','y','z','red','green','blue'])+'\nend_header\n').encode())
 for i in range(args.count):f.write(struct.pack('<6f',(i%2000)*.01,(i//2000)*.01,0.,.7,.4,.2))
