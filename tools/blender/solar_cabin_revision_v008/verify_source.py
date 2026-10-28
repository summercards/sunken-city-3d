from pathlib import Path
R=Path(__file__).resolve().parents[3]
s=(R/'tools/blender/solar_cabin_revision_v007/verify_source.py').read_text(encoding='utf-8').replace('v007','v008').replace('sea_cabin_muted_8x8_512.png','sea_cabin_timber_8x8_512.png')
exec(compile(s,__file__,'exec'))
