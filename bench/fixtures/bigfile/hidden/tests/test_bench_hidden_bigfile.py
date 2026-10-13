"""caveman-kit bench hidden test (fixture bigfile): classifier score bounds."""

from anthrouter.model_router import parse_classifier_score


def _resp(text):
    return {'content': [{'type': 'text', 'text': text}]}


def test_score_of_100_is_accepted():
    assert parse_classifier_score(_resp('100')) == 100
    assert parse_classifier_score(_resp(' 100\n')) == 100


def test_in_range_scores_still_parse():
    assert parse_classifier_score(_resp('0')) == 0
    assert parse_classifier_score(_resp('42')) == 42
    assert parse_classifier_score(_resp('99')) == 99


def test_out_of_range_and_malformed_scores_are_rejected():
    assert parse_classifier_score(_resp('101')) is None
    assert parse_classifier_score(_resp('-5')) is None
    assert parse_classifier_score(_resp('42/100')) is None
