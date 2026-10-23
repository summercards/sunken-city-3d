#!/usr/bin/env python3
"""Copy the runtime project outside the repository for reviewable regeneration."""
from pathlib import Path
import datetime as dt
import json
import os
import shutil
import uuid

ROOT = Path(__file__).resolve().parents[1]
work = Path(os.environ.get('SEA_WORK_ROOT', str(ROOT.parent / 'sea-work'))).resolve()
if work == ROOT or ROOT in work.parents:
    raise SystemExit('SEA_WORK_ROOT must be outside the repository')
target = work / 'generation' / (dt.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]) / 'godot'
shutil.copytree(ROOT / 'godot', target, ignore=shutil.ignore_patterns('.godot', 'outputs', 'build', '__pycache__'))
(target / '.sea-generation-candidate').write_text(json.dumps({'source_project': str(ROOT / 'godot')}, indent=2))
print(target)
print('Run generators in this copy; review differences before transferring selected resources.')
