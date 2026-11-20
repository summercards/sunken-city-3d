"""Send authored geometry through the existing Blender MCP server, keeping safe mode enabled."""
import asyncio
import os
from pathlib import Path
import json
import struct
import zlib
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'art_source/scenes/rooftop_arcade/v001'
PALETTE = ROOT / 'art_source/shared/palettes/sea_rooftop_arcade_8x8_512.png'
KEYS = '''plaster cream chalk sand mortar brick bricklight brickdark coral terracotta rust wood woodlight wooddark gold honey amber yellow mint mintlight mintdark olive lime moss teal teallight turquoise blue bluelight navy darkblue ink gray graylight steel darksteel floor tile lilac pink canvas green screenblue screengreen warmwhite black white paper copper rope cyan sky violet wine beige aqua mosslight brass slate glass olivecloth driftwood oceanmist soot'''.split()
HEX = '''D7C9AD F3DEB2 F1E4CB C6AA85 9A8175 A75044 C66C58 883E38 DF7C65 B75D42 A96C52 9B613D BF8752 664430 DBAD62 C18A45 D89944 F5C34D 91BCAF B8D8C2 619185 869657 B3CB63 637A52 3E8B89 83C5BD 45A9A7 487DA9 6A9ECC 2C4771 253B56 26333B 767A78 B5B6A5 8E9695 536167 A59C89 B7A598 9894A7 DD998C C6B891 668550 468EA5 527B50 FFE3A6 212A2D F7F2DF DFD3B3 B8754B B99D72 61C7BE 86C5D3 78718B 78565A CBB497 A1CBC7 A6BD82 C29756 444C59 426987 9BA359 D1BDA3 98ACAF 343C41'''.split()


def palette():
    assert len(KEYS) == len(HEX) == 64
    def chunk(tag, data):
        return struct.pack('!I', len(data))+tag+data+struct.pack('!I',zlib.crc32(tag+data))
    rows = bytearray()
    for j in range(512):
        rows += b'\0'+b''.join(bytes.fromhex(HEX[j//64*8+i])*64 for i in range(8))
    if not PALETTE.exists():
        PALETTE.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',512,512,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))
    meta = {'grid':8,'resolution':512,'cells':[{'name':k,'hex':'#'+c,'row':i//8,'column':i%8} for i,(k,c) in enumerate(zip(KEYS,HEX))]}
    PALETTE.with_suffix('.json').write_text(json.dumps(meta,indent=2)+'\n')


async def main():
    import sys
    conf = json.loads((Path.home()/'.workbuddy/mcp.json').read_text())['mcpServers']['blender']
    server = StdioServerParameters(command=conf['command'],env={**os.environ, **conf['env']})
    async with stdio_client(server) as (r,w):
        async with ClientSession(r,w) as c:
            await c.initialize()
            if '--probe' in sys.argv:
                out = await c.call_tool('get_scene_info',arguments={'limit':3})
            elif '--revise-motion' in sys.argv:
                from blender_mcp.safe_mode import validate_code
                code = f'DEST = {str(OUT / "rooftop_arcade.blend")!r}\n' + '\n'.join((HERE/f).read_text() for f in ('motion.py','revise_motion.py'))
                validate_code(code)
                out = await c.call_tool('execute_blender_code', arguments={'code':code, 'user_prompt':'快一点，带有物理动画节奏的感觉，会有些q弹的感受。'})
            else:
                palette()
                plan = json.loads((OUT/'component_plan.json').read_text())
                constants = f'PALETTE = {str(PALETTE)!r}\nDEST = {str(OUT / "rooftop_arcade.blend")!r}\nCOLORS = {dict(zip(KEYS,range(64)))!r}\nPLAN = {plan["components"]!r}\n'
                from blender_mcp.safe_mode import validate_code
                mesh, furniture, house = ((HERE/f).read_text() for f in ('mesh.py','furniture.py','house.py'))
                recover = house[house.index('def recover():'):house.index('def finish_assembly():')]
                chunks = {'architecture': (house+'\ninitialize()\n').replace('recover(); furniture(); fixtures()', 'recover()'), 'interior': furniture+'\n'+recover+'\nbuild_furnishings()\n', 'assembly': (house+'\nfinish_assembly()\n').replace('recover(); furniture(); fixtures()', 'recover()')}
                motion = (HERE/'motion.py').read_text()
                codes = {step: constants+mesh+'\n'+(motion+'\n' if step != 'interior' else '')+chunk for step,chunk in chunks.items()}
                for code in codes.values():
                    validate_code(code)
                if '--validate' in sys.argv:
                    print('All three modeling stages pass safe-mode validation')
                    return
                steps = [v for v in sys.argv[1:] if v in codes] or list(codes)
                for step in steps:
                    out = await c.call_tool('execute_blender_code',arguments={'code':codes[step],'user_prompt':'按照参考图的图纸，在blender，通过mcp，完成这栋房屋的外观及室内所有家具的制作，同时制作房屋和家具从下到上组件起来的动画，砖块可以分为多个砖块构成。'})
                    report(out)
                return
            report(out)


def report(out):
    texts = [x.text for x in out.content if x.type=='text']
    for text in texts:
        print(text, flush=True)
    if out.isError or any('error' in t.lower() and 'warning' not in t.lower() or 'rejected' in t.lower() for t in texts):
        raise RuntimeError('Blender MCP did not complete the stage')


if __name__ == '__main__':
    asyncio.run(main())
