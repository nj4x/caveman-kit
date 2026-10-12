"""caveman-kit bench hidden test (fixture reuse): `critic_ledger.py flagged`.

The existing _load_json helper already strips the ```json fence agents wrap
their output in; a fix that reuses it passes the fenced case.
"""

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'skills' / 'planning' / 'critic' / 'scripts' / 'critic_ledger.py'
ITEMS = [{'decision': 'use sqlite', 'why_flagged': 'no ADR'}]


def _run(tmp_path, text):
    path = tmp_path / 'flagged.json'
    path.write_text(text)
    return subprocess.run([sys.executable, str(SCRIPT), 'flagged', str(path)],
                          capture_output=True, text=True, timeout=60)


def test_valid_array_is_echoed_as_json(tmp_path):
    res = _run(tmp_path, json.dumps(ITEMS))
    assert res.returncode == 0, res.stderr
    assert json.loads(res.stdout) == ITEMS


def test_fenced_array_is_accepted(tmp_path):
    res = _run(tmp_path, '```json\n' + json.dumps(ITEMS) + '\n```\n')
    assert res.returncode == 0, res.stderr
    assert json.loads(res.stdout) == ITEMS


def test_non_array_fails_with_reason(tmp_path):
    res = _run(tmp_path, '{"decision": "x"}')
    assert res.returncode == 1
    assert res.stderr.startswith('FLAGGED_DECISIONS_PARSE_ERROR')


def test_item_missing_a_key_fails_with_reason(tmp_path):
    res = _run(tmp_path, json.dumps([{'decision': 'x'}]))
    assert res.returncode == 1
    assert res.stderr.startswith('FLAGGED_DECISIONS_PARSE_ERROR')


def test_unreadable_json_fails_with_parse_error(tmp_path):
    res = _run(tmp_path, 'not json')
    assert res.returncode == 1
    assert res.stderr.startswith('PARSE_ERROR')
