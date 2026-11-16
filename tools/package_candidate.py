"""Build an unsigned Windows development package, including external native libraries."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--engine', type=Path, help='Optional official Windows engine executable to copy as GSViewer.exe.')
parser.add_argument('--engine-kind', choices=('ordinary', 'release-template'), default='ordinary')
parser.add_argument('--qualification', action='store_true', help='Export the dedicated release-check scene instead of the application entry point.')
parser.add_argument('--include-cortex', action='store_true', help='Verify and copy the external portable Cortex models and CPU runtimes beside the executable.')
parser.add_argument('--user-data-name', default='GS Packaged Qualification', help='Separate app-data identity for an isolated qualification package.')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9 _-]{1,80}', args.user_data_name):
    parser.error('--user-data-name must be a simple app-data directory name.')
def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()
if args.include_cortex:
    subprocess.run(['powershell.exe', '-NoProfile', '-File', str(ROOT / 'tools/verify_cortex_bundle.ps1')], check=True)
native_descriptor = ROOT / 'rust/spatial_ml/spatial_ml.gdextension'
if (ROOT / 'rust/spatial_ml/bin/windows').exists() and not native_descriptor.is_file():
    raise SystemExit('Native binaries exist without their generated GDExtension descriptor. Run tools/setup_native_ml.py before packaging.')
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
project = re.sub(r'config/name="[^"]*"', 'config/name="' + args.user_data_name + '"', project)
entry = 'res://tests/release_checks.tscn' if args.qualification else 'res://main.tscn'
project = re.sub(r'run/main_scene=.*', 'run/main_scene="' + entry + '"', project)
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
                    or 'ObjectDB instances leaked at exit' in line]
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
for folder in ('addons', 'assets', 'rust/spatial_ml/models', 'rust/spatial_ml/bin/windows/runtime', 'modules/spatial_intelligence/models'):
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
if args.include_cortex:
    def copy_verified_asset(source, destination):
        destination = Path(destination)
        if destination.is_file() and Path(source).stat().st_size == destination.stat().st_size and sha256(Path(source)) == sha256(destination):
            return str(destination)
        return shutil.copy2(source, destination)
    shutil.copytree(ROOT / 'resources/cortex', output / 'resources/cortex', dirs_exist_ok=True, copy_function=copy_verified_asset)
(output / 'export.log').write_text('\n'.join(logs), encoding='utf-8')
receipt = {'type': 'unsigned optimized-template candidate' if args.engine_kind == 'release-template' else 'unsigned development candidate', 'source_free': True,
           'engine_kind': args.engine_kind,
           'user_data_name': args.user_data_name,
           'entry_point': entry,
           'engine_sha256': sha256(args.engine) if args.engine else None,
           'portable_cortex': args.include_cortex,
           'known_export_warnings': [line for log in logs for line in log.splitlines() if 'ERROR:' in line or 'WARNING:' in line],
           'files': {str(path.relative_to(output)).replace('\\', '/'): sha256(path)
                     for path in sorted(output.rglob('*')) if path.is_file() and path.name not in {'package-receipt.json', 'qualification.json', 'release-checks.log', 'main-startup.log'}}}
(output / 'package-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print('Development package:', output)
print('Export warning lines:', len(receipt['known_export_warnings']))
print('Isolated export source retained for diagnostics:', work)
