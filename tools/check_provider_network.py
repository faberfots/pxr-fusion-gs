from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import threading,json,time,subprocess,argparse
from pathlib import Path
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  path=self.path[1:];status=200
  data={'choices':[{'message':{'content':'network-ok'}}]}
  if path=='anthropic':data={'content':[{'type':'text','text':'network-ok'}]}
  if path=='google':data={'candidates':[{'content':{'parts':[{'text':'network-ok'}]}}]}
  if path=='slow':time.sleep(.3)
  if path=='unauthorized':status=401
  if path=='redirect':status=302
  raw=json.dumps(data).encode()
  if path=='malformed':raw=b'not json'
  if path=='oversized':raw=b'x'*2097153
  try:
   self.send_response(status)
   if path=='redirect':self.send_header('Location','/openai')
   self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
  except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True)
parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[1]);args=parser.parse_args()
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 result=subprocess.run([args.godot,'--path',str(args.project),'--headless','--script','res://tests/provider_network_checks.gd','--','http://127.0.0.1:'+str(server.server_port)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=45)
 print(result.stdout,result.stderr)
 raise SystemExit(result.returncode or int('ERROR:' in result.stderr))
finally:server.shutdown()
