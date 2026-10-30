import socket,json,sys
from pathlib import Path
code='import traceback\ntry:\n exec('+repr(Path(sys.argv[1]).read_text(encoding='utf-8'))+')\nexcept Exception:\n traceback.print_exc()\n raise'
s=socket.socket();s.settimeout(180);s.connect(('127.0.0.1',9876));s.sendall(json.dumps({'type':'execute_code','params':{'code':code}},ensure_ascii=False).encode('utf-8'));data=b''
while True:
 try:chunk=s.recv(65536)
 except socket.timeout:raise SystemExit('MCP timeout')
 if not chunk:break
 data+=chunk
 try:r=json.loads(data);break
 except json.JSONDecodeError:pass
print(json.dumps(r,ensure_ascii=False,indent=2))
if r.get('status')!='success':raise SystemExit(1)
