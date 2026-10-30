"""Execute a script in the active Blender MCP GUI session."""
import json, socket, sys
from pathlib import Path
code = Path(sys.argv[1]).read_text(encoding='utf-8')
wrapped = 'import traceback\ntry:\n exec(' + repr(code) + ')\nexcept Exception:\n traceback.print_exc()\n raise'
with socket.create_connection(('127.0.0.1', 9876), 15) as s:
    s.settimeout(1200)
    s.sendall(json.dumps({'type': 'execute_code', 'params': {'code': wrapped}}).encode())
    data = b''
    while True:
        chunk = s.recv(65536)
        if not chunk:
            raise RuntimeError('MCP closed before response')
        data += chunk
        try:
            result = json.loads(data)
            break
        except json.JSONDecodeError:
            pass
print(json.dumps(result, ensure_ascii=False, indent=2))
if result.get('status') != 'success':
    raise SystemExit(1)
