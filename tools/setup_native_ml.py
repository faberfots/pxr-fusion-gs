"""Reproduce the verified Windows CPU inference artifacts from pinned upstream data."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,sys,time,urllib.request,venv,zipfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--cache',type=Path,default=ROOT/'.native-cache')
parser.add_argument('--build',action='store_true',help='Also build/install the native GDExtension.')
args=parser.parse_args()
manifest=json.loads((ROOT/'rust/spatial_ml/models/manifest.json').read_text())
receipt=json.loads((ROOT/'rust/spatial_ml/models/export-receipt.json').read_text())
assert receipt['source']['revision']==manifest['source_revision']
cache=args.cache.resolve();cache.mkdir(parents=True,exist_ok=True)
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  while block:=f.read(1048576):h.update(block)
 return h.hexdigest()
def fetch(url,path,expected):
 if path.exists() and sha(path)==expected:return
 path.parent.mkdir(parents=True,exist_ok=True)
 temporary=path.with_name(path.name+'.part')
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'GS-native-setup'}),timeout=60) as response,temporary.open('wb') as output:
  while data:=response.read(1048576):output.write(data)
 if sha(temporary)!=expected:raise RuntimeError('Upstream checksum mismatch: '+path.name)
 temporary.replace(path)
def local(key):return ROOT/manifest['artifacts'][key]['path'].removeprefix('res://')
if any(not local(k).exists() or sha(local(k))!=manifest['artifacts'][k]['sha256'] for k in ['encoder','decoder']):
 source=cache/'source'
 for entry in receipt['source']['files']:
  fetch('https://raw.githubusercontent.com/ChaoningZhang/MobileSAM/'+manifest['source_revision']+'/'+entry['path'],source/entry['path'],entry['sha256'])
 python=cache/'env/Scripts/python.exe'
 if not python.exists():venv.EnvBuilder(with_pip=True).create(cache/'env')
 subprocess.check_call([str(python),'-m','pip','install','--only-binary=:all:','--extra-index-url','https://download.pytorch.org/whl/cpu','-r',str(ROOT/'tools/native_ml_requirements.txt')])
 subprocess.check_call([str(python),str(ROOT/'tools/export_native_ml.py'),'--source',str(source),'--output',str(ROOT/'rust/spatial_ml/models')])
 for key in ['encoder','decoder']:
  if sha(local(key))!=manifest['artifacts'][key]['sha256']:raise RuntimeError('Export differs from the qualified artifact: '+key)
archive=cache/'onnxruntime-win-x64-1.23.2.zip'
fetch(manifest['runtime_archive']['url'],archive,manifest['runtime_archive']['sha256'])
with zipfile.ZipFile(archive) as source:
 for entry in ['lib/onnxruntime.dll','lib/onnxruntime_providers_shared.dll','LICENSE','ThirdPartyNotices.txt']:
  members=[name for name in source.namelist() if name.endswith('/'+entry)]
  if not members:continue
  output=local('windows_runtime').parent/Path(entry).name
  if entry=='LICENSE':output=output.with_name('LICENSE-ONNXRuntime.txt')
  output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(source.read(members[0]))
if sha(local('windows_runtime'))!=manifest['artifacts']['windows_runtime']['sha256']:raise RuntimeError('Runtime checksum mismatch')
if args.build:subprocess.check_call(['powershell.exe','-NoProfile','-File',str(ROOT/'rust/spatial_ml/build.ps1')])
print('Verified MobileSAM models and Windows CPU runtime are installed.')
