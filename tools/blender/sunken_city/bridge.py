"""Send one request to the running BlenderMCP TCP service (no extra dependencies)."""
import argparse
import json
import socket
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--code-file')
p.add_argument('--code')
p.add_argument('--command', default='execute_code')
p.add_argument('--timeout', type=float, default=600)
p.add_argument('--params', default='{}')
a = p.parse_args()
params = json.loads(a.params)
if a.code_file:
    params['code'] = "import runpy; runpy.run_path(" + repr(str(Path(a.code_file).resolve())) + ", run_name='__main__')"
elif a.code:
    params['code'] = a.code
with socket.create_connection(('127.0.0.1', 9876), 10) as s:
    s.settimeout(a.timeout)
    s.sendall(json.dumps({'type': a.command, 'params': params}).encode('utf-8'))
    data = b''
    while True:
        part = s.recv(1048576)
        if not part:
            raise RuntimeError('BlenderMCP closed before a complete response')
        data += part
        try:
            result = json.loads(data)
            break
        except json.JSONDecodeError:
            pass
print(json.dumps(result, ensure_ascii=True, indent=2))
if result.get('status') != 'success':
    raise SystemExit(1)
