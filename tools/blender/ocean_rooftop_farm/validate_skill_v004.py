from pathlib import Path
code=Path('D:/projects/sea/tools/blender/ocean_rooftop_farm/validate_skill_v002.py').read_text(encoding='utf-8').replace('/v002','/v004').replace('ORF2_SKILL_VERIFY','ORF4_SKILL_VERIFY')
exec(compile(code,'validate_skill_v004','exec'))
