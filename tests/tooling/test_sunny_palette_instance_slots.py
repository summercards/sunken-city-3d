"""Q03：仅按文本核对共享 shader 的显式实例槽位，无引擎或资源写入。"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAIN_SLOTS = {
    'sea_material_role': 0,
    'sea_matte_controls': 1,
    'sea_metal_controls': 2,
    'sea_gloss_controls': 3,
    'sea_emission_controls': 4,
    'sea_matte_emission_energy': 5,
    'sea_metal_emission_energy': 6,
    'sea_gloss_emission_energy': 7,
    'sea_emission_emission_energy': 8,
}
GLOSS_SLOTS = {name: MAIN_SLOTS[name] for name in (
    'sea_material_role', 'sea_gloss_controls', 'sea_gloss_emission_energy')}
INDEX = re.compile(r'\binstance_index\s*\(\s*(\d+)\s*\)')
DECLARATION = re.compile(r'\binstance\s+uniform\s+\w+\s+(\w+)\b([^;]*);')


def instance_slots(source):
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    slots = {}
    for name, declaration in DECLARATION.findall(source):
        indices = INDEX.findall(declaration)
        if len(indices) != 1 or ':' not in declaration.split('=', 1)[0]:
            raise ValueError(f'{name} 缺少唯一显式 instance_index')
        index = int(indices[0])
        if name in slots or index in slots.values():
            raise ValueError(f'{name} 的名称或槽位重复')
        slots[name] = index
    return slots


class SunnyPaletteInstanceSlots(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = [(ROOT / 'godot/shaders' / name).read_text(encoding='utf-8')
                       for name in ('sunny_palette.gdshader', 'sunny_palette_gloss.gdshader')]

    def check_pair(self, sources):
        main, gloss = map(instance_slots, sources)
        self.assertEqual(main, MAIN_SLOTS, '主 shader 保留原声明顺序的 0–8 槽位')
        self.assertEqual(gloss, GLOSS_SLOTS, 'Gloss 必须使用主 shader 的对应槽位')
        for name in main.keys() & gloss.keys():
            self.assertEqual(main[name], gloss[name], name)

    def test_current_shaders_have_unique_explicit_matching_slots(self):
        self.check_pair(self.sources)

    def test_each_missing_index_is_rejected(self):
        for shader, source in enumerate(self.sources):
            for match in INDEX.finditer(source):
                with self.subTest(shader=shader, index=match.group(1)):
                    broken = source[:match.start()] + source[match.end():]
                    with self.assertRaises(ValueError):
                        instance_slots(broken)

    def test_duplicate_slot_is_rejected_in_each_shader(self):
        for shader, source in enumerate(self.sources):
            matches = list(INDEX.finditer(source))
            first, second = matches[:2]
            broken = source[:second.start()] + first.group() + source[second.end():]
            with self.subTest(shader=shader), self.assertRaises(ValueError):
                instance_slots(broken)

    def test_unique_but_mismatched_shared_slot_is_rejected(self):
        for shader, source in enumerate(self.sources):
            broken = list(self.sources)
            broken[shader] = source.replace('instance_index(3)', 'instance_index(9)')
            with self.subTest(shader=shader), self.assertRaises(AssertionError):
                self.check_pair(broken)

    def test_legacy_implicit_declarations_are_rejected(self):
        for shader, source in enumerate(self.sources):
            legacy = re.sub(r'\s*:\s*instance_index\s*\(\s*\d+\s*\)', '', source)
            with self.subTest(shader=shader), self.assertRaises(ValueError):
                instance_slots(legacy)


if __name__ == '__main__':
    unittest.main()
