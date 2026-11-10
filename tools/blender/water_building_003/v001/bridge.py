"""Minimal BlenderMCP socket bridge. Usage: python bridge.py <script.py>  |  python bridge.py --info
Only stdout of the script is returned (print results)."""
import json, socket, sys

def call(cmd, params=None, timeout=600):
    s = socket.create_connection(('127.0.0.1', 9876), timeout=timeout)
    s.sendall(json.dumps({'type': cmd, 'params': params or {}}).encode('utf-8'))
    buf = b''
    while True:
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        buf += chunk
        try:
            return json.loads(buf.decode('utf-8'))
        except ValueError:
            continue
    return json.loads(buf.decode('utf-8'))

if __name__ == '__main__':
    if sys.argv[1] == '--info':
        r = call('get_scene_info')
    else:
        code = open(sys.argv[1], encoding='utf-8').read()
        r = call('execute_code', {'code': code})
    out = json.dumps(r, ensure_ascii=False, indent=1)
    sys.stdout.buffer.write(out.encode('utf-8', 'replace') + b'\n')
    sys.exit(0 if r.get('status') != 'error' else 1)
