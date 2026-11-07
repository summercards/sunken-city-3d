"""Task-owned Blender MCP GUI connection; separate port avoids stale GUI sockets."""
import argparse,json,socket,traceback
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--code-file');p.add_argument('--code');p.add_argument('--port',type=int,default=9877);p.add_argument('--timeout',type=float,default=1200);a=p.parse_args()
code=Path(a.code_file).read_text(encoding='utf-8') if a.code_file else a.code
wrapped='import traceback\ntry:\n exec('+repr(code)+')\nexcept Exception:\n traceback.print_exc()\n raise'
with socket.create_connection(('127.0.0.1',a.port),15) as s:
 s.settimeout(a.timeout);s.sendall(json.dumps({'type':'execute_code','params':{'code':wrapped}}).encode());data=b''
 while True:
  part=s.recv(1048576)
  if not part:raise RuntimeError('MCP closed before complete response')
  data+=part
  try:result=json.loads(data);break
  except json.JSONDecodeError:pass
print(json.dumps(result,ensure_ascii=False,indent=2))
if result.get('status')!='success':raise SystemExit(1)
