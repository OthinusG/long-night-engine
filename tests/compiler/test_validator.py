from pathlib import Path

import pytest

from tools.story_compiler.diagnostics import DiagnosticCode
from tools.story_compiler.parser import StoryParser
from tools.story_compiler.registry import Registries
from tools.story_compiler.validator import validate

BASE_STORY = """#scene demo_start
陆长庚[calm]:
开始。
@bg county_court_day
@bgm testimony
@sfx gavel_light
@evidence_add night_duty_log
@testimony zhao_demo_01
@penalty 20
@wrong -> demo_wrong
## statement demo_s01
赵廷禄[calm]:
证言。
@press -> demo_press
@present night_duty_log -> demo_break
@endtestimony
@goto demo_end
#scene demo_wrong
@return
#scene demo_press
@return
#scene demo_break
@return
#scene demo_end
@return
"""


def _codes(source: str, registries: Registries) -> set[DiagnosticCode]:
    parsed = StoryParser().parse_text(source, "chapter_01/invalid.md")
    return {item.code for item in [*parsed.diagnostics, *validate(parsed.document, registries)]}


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        (BASE_STORY + "#scene demo_start\n@return\n", DiagnosticCode.DUPLICATE_SCENE),
        (BASE_STORY.replace("陆长庚[calm]", "未知人物[calm]"), DiagnosticCode.UNKNOWN_CHARACTER),
        (BASE_STORY.replace("陆长庚[calm]", "陆长庚[missing]"), DiagnosticCode.UNKNOWN_EXPRESSION),
        (BASE_STORY.replace("night_duty_log -> demo_break", "missing -> demo_break"), DiagnosticCode.UNKNOWN_EVIDENCE),
        (BASE_STORY.replace("@goto demo_end", "@goto missing"), DiagnosticCode.UNKNOWN_SCENE),
        (BASE_STORY.replace("@goto demo_end", "@call missing"), DiagnosticCode.UNKNOWN_SCENE),
        (BASE_STORY.replace("@press -> demo_press", "@press -> missing"), DiagnosticCode.INVALID_PRESS_TARGET),
        (BASE_STORY.replace("night_duty_log -> demo_break", "night_duty_log -> missing"), DiagnosticCode.INVALID_PRESENT_TARGET),
        (BASE_STORY.replace("@penalty 20", "@penalty 101"), DiagnosticCode.INVALID_PENALTY),
        (BASE_STORY.replace("@wrong -> demo_wrong", "@wrong -> missing"), DiagnosticCode.INVALID_WRONG_TARGET),
        (BASE_STORY.replace("@bg county_court_day", "@bg missing"), DiagnosticCode.UNKNOWN_BACKGROUND),
        (BASE_STORY.replace("@bgm testimony", "@bgm missing"), DiagnosticCode.UNKNOWN_BGM),
        (BASE_STORY.replace("@sfx gavel_light", "@sfx missing"), DiagnosticCode.UNKNOWN_SFX),
        (BASE_STORY.replace("#scene demo_start", "#scene Demo-Start"), DiagnosticCode.INVALID_SCENE_ID),
        (BASE_STORY.replace("@goto demo_end", "@unknown value"), DiagnosticCode.MALFORMED_COMMAND),
        (BASE_STORY.replace("@goto demo_end", "@press -> demo_press"), DiagnosticCode.INVALID_COMMAND_CONTEXT),
        (BASE_STORY.replace("@endtestimony", ""), DiagnosticCode.UNTERMINATED_TESTIMONY),
        (BASE_STORY.replace("@goto demo_end", "@char missing"), DiagnosticCode.UNKNOWN_CHARACTER),
        (
            BASE_STORY.replace("@goto demo_end", "@char lu_changgeng left missing"),
            DiagnosticCode.UNKNOWN_EXPRESSION,
        ),
        (BASE_STORY.replace("@goto demo_end", "@char"), DiagnosticCode.MALFORMED_COMMAND),
        (
            BASE_STORY.replace("@goto demo_end", "@hide"),
            DiagnosticCode.MALFORMED_COMMAND,
        ),
    ],
)
def test_invalid_story_is_rejected(
    source: str,
    expected: DiagnosticCode,
    registries: Registries,
) -> None:
    assert expected in _codes(source, registries)


def test_duplicate_statement_is_rejected(registries: Registries) -> None:
    duplicate = """## statement demo_s01
赵廷禄[calm]:
重复证言。
"""
    source = BASE_STORY.replace("@endtestimony", duplicate + "@endtestimony")
    assert DiagnosticCode.DUPLICATE_STATEMENT in _codes(source, registries)


def test_duplicate_testimony_is_rejected(registries: Registries) -> None:
    duplicate = """@testimony zhao_demo_01
@penalty 20
@wrong -> demo_wrong
## statement demo_s02
赵廷禄[calm]:
另一证言。
@endtestimony
"""
    source = BASE_STORY.replace("@goto demo_end", duplicate + "@goto demo_end")
    assert DiagnosticCode.DUPLICATE_TESTIMONY in _codes(source, registries)


def test_empty_testimony_is_rejected(registries: Registries) -> None:
    statement = """## statement demo_s01
赵廷禄[calm]:
证言。
@press -> demo_press
@present night_duty_log -> demo_break
"""
    assert DiagnosticCode.EMPTY_TESTIMONY in _codes(BASE_STORY.replace(statement, ""), registries)


def test_duplicate_present_rule_is_rejected(registries: Registries) -> None:
    source = BASE_STORY.replace(
        "@present night_duty_log -> demo_break",
        "@present night_duty_log -> demo_break\n@present night_duty_log -> demo_break",
    )
    assert DiagnosticCode.DUPLICATE_PRESENT_RULE in _codes(source, registries)


def test_malformed_press_is_rejected(registries: Registries) -> None:
    source = BASE_STORY.replace("@press -> demo_press", "@press")
    assert DiagnosticCode.MALFORMED_COMMAND in _codes(source, registries)


def test_diagnostic_render_includes_file_line_and_code(registries: Registries) -> None:
    parsed = StoryParser().parse_text(
        BASE_STORY.replace("@goto demo_end", "@goto missing"),
        "chapter_01/invalid.md",
    )
    diagnostic = next(
        item
        for item in validate(parsed.document, registries)
        if item.code == DiagnosticCode.UNKNOWN_SCENE
    )

    rendered = diagnostic.render()
    assert "story_src/chapter_01/invalid.md:17" in rendered
    assert "ERROR LN1002" in rendered


def test_invalid_fixture_fails_with_expected_code(registries: Registries) -> None:
    fixture = Path(__file__).parent / "fixtures" / "invalid_unknown_evidence.md"
    parsed = StoryParser().parse_path(fixture, fixture.parent)

    assert DiagnosticCode.UNKNOWN_EVIDENCE in {
        item.code for item in validate(parsed.document, registries)
    }
