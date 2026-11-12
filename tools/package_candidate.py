"""Build an unsigned Windows development package, including external native libraries."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--engine', type=Path, help='Optional official Windows engine executable to copy as GSViewer.exe.')
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT.is_relative_to(output):
    raise SystemExit('Choose a dedicated package directory.')
output.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(prefix='gs-package-source-'))
for directory in ('modules', 'addons', 'assets', 'tests', 'rust/spatial_ml/models', 'rust/spatial_ml/bin'):
    source = ROOT / directory
    if source.exists():
        shutil.copytree(source, work / directory, ignore=shutil.ignore_patterns('~*', '*.TMP', '__pycache__'))
for name in ('main.tscn', 'icon.svg', 'export_presets.cfg', 'rust/spatial_ml/spatial_ml.gdextension'):
    source = ROOT / name
    if source.exists():
        (work / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, work / name)
project = (ROOT / 'project.godot').read_text(encoding='utf-8')
project = re.sub(r'config/name="[^"]*"', 'config/name="GS Packaged Qualification"', project)
project = re.sub(r'run/main_scene=.*', 'run/main_scene="res://main.tscn"', project)
project = re.sub(r'ImGuiRoot=.*', 'ImGuiRoot="*res://addons/imgui-godot/data/ImGuiRoot.tscn"', project)
(work / 'project.godot').write_text(project, encoding='utf-8')
startup = None
if __import__('os').name == 'nt':
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
logs = []
for command in (['--headless', '--editor', '--import', '--single-threaded-scene'],
                ['--headless', '--editor', '--export-pack', 'Windows Desktop', str(output / 'GSViewer.pck')]):
    result = subprocess.run([str(args.godot), '--path', str(work), *command], capture_output=True,
                            text=True, encoding='utf-8', errors='replace', startupinfo=startup, timeout=180)
    log = result.stdout + result.stderr
    logs.append(log)
    fatal_errors = [line for line in log.splitlines() if 'ERROR:' in line
                    and "2 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit." not in line]
    if result.returncode or fatal_errors:
        (output / 'export.log').write_text('\n'.join(logs), encoding='utf-8')
        raise SystemExit('Godot package creation failed; inspect export.log.')
# --export-pack does not copy the libraries referenced by GDExtension descriptors.
for descriptor in work.rglob('*.gdextension'):
    for value in re.findall(r'^windows\.[^=]+?=\s*"([^"]+)"', descriptor.read_text(), re.M):
        source = work / value.removeprefix('res://') if value.startswith('res://') else descriptor.parent / value
        if not source.is_file():
            raise SystemExit('Missing Windows extension library: ' + str(source))
        destination = output / source.relative_to(work)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
for folder in ('addons', 'assets', 'rust/spatial_ml/models', 'rust/spatial_ml/bin/windows/runtime'):
    for source in (ROOT / folder).rglob('*'):
        if source.is_file() and any(word in source.name.lower() for word in ('license', 'notices', 'attribution', 'ofl.')):
            destination = output / 'licenses' / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
if (ROOT / 'LICENSE').exists():
    shutil.copy2(ROOT / 'LICENSE', output / 'LICENSE')
if (ROOT / 'docs/provenance/rust-licenses').exists():
    shutil.copytree(ROOT / 'docs/provenance/rust-licenses', output / 'licenses/rust', dirs_exist_ok=True)
if (ROOT / 'docs/provenance/Godot-LICENSE.txt').exists():
    shutil.copy2(ROOT / 'docs/provenance/Godot-LICENSE.txt', output / 'licenses/Godot-LICENSE.txt')
if args.engine:
    shutil.copy2(args.engine.resolve(), output / 'GSViewer.exe')
(output / 'export.log').write_text('\n'.join(logs), encoding='utf-8')
receipt = {'type': 'unsigned development candidate', 'source_free': True,
           'known_export_warnings': [line for log in logs for line in log.splitlines() if 'ERROR:' in line or 'WARNING:' in line],
           'files': {str(path.relative_to(output)).replace('\\', '/'): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted(output.rglob('*')) if path.is_file() and path.name != 'package-receipt.json'}}
(output / 'package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print('Development package:', output)
print('Export warning lines:', len(receipt['known_export_warnings']))
print('Isolated export source retained for diagnostics:', work)
