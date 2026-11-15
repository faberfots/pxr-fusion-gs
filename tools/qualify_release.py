"""Qualify a separate source-free package under a real Windows release template.

Official templates disable --script/--path overrides. A dedicated exported scene
therefore exercises main.tscn without changing the application package entry point.
"""
from pathlib import Path
import argparse, json, os, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--godot', type=Path, required=True)
parser.add_argument('--template', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--dataset', type=Path, action='append', default=[])
parser.add_argument('--timeout', type=int, default=420)
parser.add_argument('--include-cortex', action='store_true')
parser.add_argument('--cortex-image', type=Path)
args = parser.parse_args()
if os.name != 'nt':
    parser.error('This helper qualifies Windows x86_64 templates on Windows.')
output = args.output.resolve()
subprocess.run([sys.executable, str(ROOT / 'tools/package_candidate.py'),
                '--godot', str(args.godot.resolve()), '--engine', str(args.template.resolve()),
                '--output', str(output), '--engine-kind', 'release-template', '--qualification'] +
               (['--include-cortex'] if args.include_cortex else []), check=True)
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
command = [str(output / 'GSViewer.exe'), '--audio-driver', 'Dummy',
           '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan',
           '--resolution', '1142x648', '--position', '-32000,-32000']
if args.dataset or args.include_cortex:
    command += ['--']
    for path in args.dataset:
        command += ['--dataset', str(path.resolve())]
    if args.include_cortex: command += ['--cortex']
    if args.cortex_image: command += ['--cortex-image', str(args.cortex_image.resolve())]
result = subprocess.run(command, cwd=output, capture_output=True, text=True,
                        encoding='utf-8', errors='replace', startupinfo=startup, timeout=args.timeout)
log = result.stdout + result.stderr
(output / 'release-checks.log').write_text(log, encoding='utf-8')
passed = (result.returncode == 0 and 'RELEASE CHECKS COMPLETE: 0 failures' in log
          and 'FAIL ' not in log and 'ERROR:' not in log)
receipt = json.loads((output / 'package-receipt.json').read_text())
qualification = {'passed': passed, 'process_exit': result.returncode,
                 'engine_sha256': receipt['engine_sha256'],
                 'entry_point': receipt['entry_point'], 'datasets': [str(p.resolve()) for p in args.dataset],
                 'scope': 'Windows x86_64, local Vulkan GPU, unsigned optimized-template package'}
(output / 'qualification.json').write_text(json.dumps(qualification, indent=2) + '\n')
print(log)
sys.exit(0 if passed else 1)
