"""Run checks in a disposable, isolated Godot project; never change scene history."""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile, sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', r'C:\Users\User\Downloads\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe'))
parser.add_argument('--gpu', action='store_true')
parser.add_argument('--resolution', default='64x64', help='Physical GPU review viewport, for example 1142x648.')
parser.add_argument('--disable-msaa', action='store_true', help='Exercise the explicit MSAA-disabled rendering configuration.')
parser.add_argument('--candidate', type=Path)
parser.add_argument('--skip-import', action='store_true')
parser.add_argument('--import-timeout', type=int, default=90)
parser.add_argument('--skip-native', action='store_true', help='Qualify rendering without copying platform-specific optional native ML libraries.')
parser.add_argument('--script', default='res://tests/core_checks.gd')
parser.add_argument('--timeout', type=int, default=180)
parser.add_argument('--test-arg', action='append', default=[])
args = parser.parse_args()
resolved_godot = shutil.which(args.godot)
if not resolved_godot and args.godot == 'godot':
    resolved_godot = os.environ.get('GODOT')
args.godot = str(Path(resolved_godot or args.godot).resolve())
candidate = args.candidate or Path(tempfile.mkdtemp(prefix='gs-checks-'))
for directory in ('modules', 'addons', 'assets', 'tests'):
    source = ROOT / directory
    if source.exists():
        shutil.copytree(source, candidate / directory, dirs_exist_ok=True, ignore=shutil.ignore_patterns('*.backup', '*.boundaries', '__pycache__'))
native = ROOT / 'rust/spatial_ml'
if not args.skip_native and (native / 'spatial_ml.gdextension').exists() and (native / 'bin').exists():
    shutil.copytree(native / 'bin', candidate / 'rust/spatial_ml/bin', dirs_exist_ok=True)
    shutil.copytree(native / 'models', candidate / 'rust/spatial_ml/models', dirs_exist_ok=True)
    shutil.copy2(native / 'spatial_ml.gdextension', candidate / 'rust/spatial_ml/spatial_ml.gdextension')
shutil.copy2(ROOT / 'main.tscn', candidate / 'main.tscn')
shutil.copy2(ROOT / 'icon.svg', candidate / 'icon.svg')
project = (ROOT / 'project.godot').read_text(encoding='utf-8')
import re
project = re.sub(r'config/name="[^"]*"', 'config/name="GS Qualification '+candidate.name+'"', project)
project = re.sub(r'run/main_scene=.*', 'run/main_scene=""', project)
project = re.sub(r'enabled=PackedStringArray\([^\n]*\)', 'enabled=PackedStringArray()', project)
project = re.sub(r'ImGuiRoot=.*', 'ImGuiRoot="*res://addons/imgui-godot/scripts/ImGuiRoot.gd"', project)
if args.disable_msaa:
    project = re.sub(r'anti_aliasing/quality/msaa_3d=\d+', 'anti_aliasing/quality/msaa_3d=0', project)
    print('Qualification scope: software Vulkan with MSAA disabled.', flush=True)
(candidate / 'project.godot').write_text(project, encoding='utf-8')
print('Isolated project:', candidate, flush=True)
startup = None
if os.name == 'nt':
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
def run(extra, timeout):
    command = [args.godot, '--path', str(candidate), '--audio-driver', 'Dummy'] + extra
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout, startupinfo=startup)
    print(result.stdout, result.stderr, flush=True)
    print("Process exit:", result.returncode, flush=True)
    if "SCRIPT ERROR:" in result.stderr or "ERROR:" in result.stderr: return 1
    return result.returncode
code = 0 if args.skip_import else run(['--headless', '--editor', '--import', '--single-threaded-scene'], args.import_timeout)
if code:
    sys.exit(code)
code = run(['--headless', '--script', 'res://tests/script_checks.gd'], 60)
if code:
    sys.exit(code)
flags = ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--resolution', args.resolution, '--position', '-32000,-32000'] if args.gpu else ['--headless']
sys.exit(run(flags + ['--script', args.script] + (['--'] + args.test_arg if args.test_arg else []), args.timeout))
