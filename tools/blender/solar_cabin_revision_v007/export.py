"""Reuse reviewed cleanup/export algorithms against the current protected revision."""
from pathlib import Path
R=Path(__file__).resolve().parents[3]
s=(R/'tools/blender/solar_cabin_revision_v006/export.py').read_text(encoding='utf-8')
s=s.replace('v006','v007').replace("version='1.3'","version='1.4'").replace('sea_cozy_8x8_512.png','sea_cabin_muted_8x8_512.png')
# Exported paths are resource IDs, independent of the host OS.
s=s.replace('str(p.relative_to(R))','p.relative_to(R).as_posix()').replace('str(source.relative_to(R))','source.relative_to(R).as_posix()').replace('str(optimized.relative_to(R))','optimized.relative_to(R).as_posix()').replace('str(palette.relative_to(R))','palette.relative_to(R).as_posix()')
exec(compile(s,__file__,'exec'))
