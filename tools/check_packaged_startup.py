"""Start the actual exported application entry point, including its autoloads/UI.

The headless CI route expects the renderer's explicit unavailable warning. Local
Vulkan qualification also verifies the visible renderer and controls separately.
"""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys

parser = argparse.ArgumentParser()
parser.add_argument('--package', type=Path, required=True)
parser.add_argument('--gpu', action='store_true')
args = parser.parse_args()
package = args.package.resolve()
receipt = json.loads((package / 'package-receipt.json').read_text())
if receipt.get('entry_point') != 'res://main.tscn':
    raise SystemExit('Application startup must use the real main scene.')
exe = package / 'GSViewer.exe'
if hashlib.sha256(exe.read_bytes()).hexdigest() != receipt['engine_sha256']:
    raise SystemExit('The packaged executable does not match its receipt.')
startup = None
if os.name == 'nt':
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
flags = ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan',
         '--resolution', '1142x648', '--position', '-32000,-32000'] if args.gpu else ['--headless']
result = subprocess.run([str(exe), '--audio-driver', 'Dummy', '--quit-after', '120', *flags],
                        cwd=package, capture_output=True, text=True, encoding='utf-8',
                        errors='replace', startupinfo=startup, timeout=90)
log = result.stdout + result.stderr
(package / 'main-startup.log').write_text(log, encoding='utf-8')
passed = result.returncode == 0 and 'ERROR:' not in log and 'ObjectDB instances leaked' not in log
print(log)
print('PACKAGED MAIN STARTUP:', 'PASS' if passed else 'FAIL', 'exit', result.returncode)
sys.exit(0 if passed else 1)
