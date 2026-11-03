from tools.story_compiler.models import (
    AssetNode,
    ConditionNode,
    DialogueNode,
    EvidenceNode,
    FlagNode,
    FlowKind,
    FlowNode,
    StartTestimonyNode,
)
from tools.story_compiler.parser import StoryParser


def test_parser_supports_vertical_slice_syntax() -> None:
    result = StoryParser().parse_text(
        """#scene demo_start
陆长庚[thinking]:
第一行。
第二行。
@bg county_court_day
@bgm testimony
@sfx gavel_light
@evidence_add night_duty_log
@evidence_update night_duty_log verified
@evidence_remove wrong_evidence
@flag saw_bloodstain = true
@if saw_bloodstain
@goto demo_trial
@call demo_branch
@return
@goto demo_trial
#scene demo_trial
@testimony zhao_demo_01
@penalty 20
@wrong -> demo_wrong
## statement zhao_demo_s01
赵廷禄[calm]:
证言一。
@press -> demo_press
@present night_duty_log -> demo_break
## statement zhao_demo_s02
赵廷禄[angry]:
证言二。
@endtestimony
#scene demo_branch
@return
#scene demo_wrong
@return
#scene demo_press
@return
#scene demo_break
@return
""",
        "chapter_01/parser.md",
    )

    assert result.diagnostics == []
    assert [scene.id for scene in result.document.scenes] == [
        "demo_start",
        "demo_trial",
        "demo_branch",
        "demo_wrong",
        "demo_press",
        "demo_break",
    ]
    instructions = result.document.scenes[0].instructions
    assert isinstance(instructions[0], DialogueNode)
    assert instructions[0].text == "第一行。\n第二行。"
    assert sum(isinstance(item, AssetNode) for item in instructions) == 3
    assert sum(isinstance(item, EvidenceNode) for item in instructions) == 3
    assert any(isinstance(item, FlagNode) for item in instructions)
    assert any(isinstance(item, ConditionNode) for item in instructions)
    assert any(
        isinstance(item, FlowNode) and item.kind == FlowKind.CALL
        for item in instructions
    )
    assert any(
        isinstance(item, FlowNode) and item.kind == FlowKind.RETURN
        for item in instructions
    )
    assert any(
        isinstance(item, FlowNode) and item.kind == FlowKind.GOTO
        for item in instructions
    )
    assert isinstance(result.document.scenes[1].instructions[0], StartTestimonyNode)

    testimony = result.document.testimonies[0]
    assert testimony.id == "zhao_demo_01"
    assert testimony.penalty == 20
    assert len(testimony.statements) == 2
    assert testimony.statements[0].press_target_scene == "demo_press"
    assert testimony.statements[0].present_rules[0].evidence_id == "night_duty_log"


def test_dialogue_source_location_uses_header_line() -> None:
    result = StoryParser().parse_text(
        "#scene demo\n\n陆长庚[calm]:\n正文。\n",
        "chapter_01/location.md",
    )

    dialogue = result.document.scenes[0].instructions[0]
    assert isinstance(dialogue, DialogueNode)
    assert dialogue.source.file == "chapter_01/location.md"
    assert dialogue.source.line == 3
