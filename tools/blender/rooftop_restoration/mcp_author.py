import json
from pathlib import Path
import socket


script = Path(__file__).with_name("assemble.py").resolve()
code = (
    "import sys\n"
    "sys.modules.pop('components', None)\n"
    "sys.modules.pop('geometry', None)\n"
    f"exec(compile(open({str(script)!r}).read(), {str(script)!r}, 'exec'), "
    f"{{'__file__': {str(script)!r}}})"
)
with socket.create_connection(("127.0.0.1", 9876), timeout=5) as connection:
    connection.settimeout(180)
    connection.sendall(json.dumps({"type": "execute_code", "params": {"code": code}}).encode())
    data = bytearray()
    while chunk := connection.recv(65536):
        data.extend(chunk)
        try:
            result = json.loads(data)
        except ValueError:
            continue
        if result["status"] != "success":
            raise SystemExit(result.get("message", result))
        print(result["result"]["result"])
        break
    else:
        raise SystemExit("Blender MCP closed the connection without a complete response")
