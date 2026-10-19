import socket,json,sys
from pathlib import Path
code=Path(sys.argv[1]).read_text() if len(sys.argv)>1 else sys.stdin.read()
s=socket.create_connection(('127.0.0.1',9876),timeout=20);s.settimeout(600)
s.sendall(json.dumps({'type':'execute_code','params':{'code':code}}).encode())
b=b''
while True:
 c=s.recv(1048576)
 if not c:break
 b+=c
 try:
  r=json.loads(b);print(json.dumps(r,ensure_ascii=False));break
 except json.JSONDecodeError:pass
