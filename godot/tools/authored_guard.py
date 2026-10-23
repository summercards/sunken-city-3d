"""Legacy generators may write only into a disposable candidate checkout."""
from pathlib import Path
import json


def require_candidate(script_file):
    root = Path(script_file).resolve().parents[1]
    marker = root / '.sea-generation-candidate'
    if marker.is_file():
        source = Path(json.loads(marker.read_text())['source_project']).resolve()
        if root != source and source.parent not in root.parents:
            return
    raise SystemExit('Refusing to overwrite authored resources. Create a candidate with '
                     'python3 scripts/create_generation_candidate.py and run this generator there.')
