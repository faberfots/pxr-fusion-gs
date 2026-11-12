"""Check staged source without logging secret values or uploading file contents."""
from pathlib import Path
import argparse,re,subprocess,sys
parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);args=parser.parse_args()
root=args.root.resolve()
names=subprocess.check_output(['git','-C',str(root),'ls-files','-z']).decode().split('\0')
patterns=[re.compile(rb'sk-ant-[A-Za-z0-9_-]{20,}'),re.compile(rb'(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{30,}'),re.compile(rb'gh[pousr]_[A-Za-z0-9]{20,}'),re.compile(rb'AIza[A-Za-z0-9_-]{30,}'),re.compile(rb'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----')]
problems=[];total=0;largest=[]
for name in names:
 if not name:continue
 path=root/name
 if not path.is_file():continue
 size=path.stat().st_size;total+=size
 if size>100*1024*1024:problems.append((name,'exceeds GitHub file limit'))
 data=path.read_bytes()
 if b'\0' in data[:8192]:continue
 if any(p.search(data) for p in patterns):problems.append((name,'potential embedded credential/private key'))
for name,reason in problems:print(reason+': '+name)
print('Tracked source files:',len([n for n in names if n]),'bytes:',total,'findings:',len(problems))
raise SystemExit(1 if problems else 0)
