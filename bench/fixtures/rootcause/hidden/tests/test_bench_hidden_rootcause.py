"""caveman-kit bench hidden test (fixture rootcause): the shared stripping helper.

The planted bug sits in request_text.strip_reminders, which several call sites
share. A fix at one call site only leaves the other assertions failing.
"""

from anthrouter.handlers import _final_user_text
from anthrouter.model_router import _extract_user_text
from anthrouter.request_text import is_activity_label_prompt, strip_reminders

REMINDER = '<system-reminder>context</system-reminder>\n'


def test_strip_reminders_trims_outer_whitespace():
    assert strip_reminders(REMINDER + '  hello there \n') == 'hello there'
    assert strip_reminders(REMINDER) == ''


def test_activity_label_prompt_after_reminder_is_detected():
    assert is_activity_label_prompt(REMINDER + 'Describe your most recent action in 3-5 words.')


def test_router_sees_trimmed_user_text():
    assert _extract_user_text(REMINDER + 'fix it  ')[0] == 'fix it'


def test_reminder_only_message_is_not_a_local_command():
    payload = {'messages': [{'role': 'user', 'content': REMINDER + '   '}]}
    assert _final_user_text(payload) is None
