import socket, json, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text(encoding='utf-8')
code = 'import traceback\ntry:\n exec(' + repr(source) + ')\nexcept Exception:\n print(traceback.format_exc())'
s = socket.socket()
s.settimeout(300)
s.connect(('127.0.0.1', 9876))
s.sendall(json.dumps({'type': 'execute_code', 'params': {'code': code}}, ensure_ascii=False).encode('utf-8'))
data = b''
while True:
    chunk = s.recv(65536)
    if not chunk:
        break
    data += chunk
    try:
        response = json.loads(data)
        break
    except json.JSONDecodeError:
        pass
print(json.dumps(response, ensure_ascii=False, indent=2))
if response.get('status') != 'success':
    raise SystemExit(1)
