import json
import shutil
from pathlib import Path

import pytest

from tools.story_compiler.compiler import build_project
from tools.story_compiler.diagnostics import DiagnosticCode
from tools.story_compiler.models import (
    AssetNode,
    EndInvestigationNode,
    FlowNode,
    HotspotNode,
    LocationNode,
    StartInvestigationNode,
    TalkUnlockNode,
)
from tools.story_compiler.parser import ParseResult, StoryParser
from tools.story_compiler.registry import Registries
from tools.story_compiler.validator import validate

PROJECT_ROOT = Path(__file__).parents[2]
SOURCE_FILE = "chapter_01/investigation.md"

# Catalogs whose contents are cross-checked against story scenes must not leak
# into a fixture project, so fixture builds use only these registries.
BASE_CATALOGS = (
    "characters.json",
    "expressions.json",
    "evidence.json",
    "backgrounds.json",
    "bgm.json",
    "sfx.json",
)


def _isolated_data_root(tmp_path: Path) -> Path:
    data_root = tmp_path / "data"
    data_root.mkdir(parents=True, exist_ok=True)
    for name in BASE_CATALOGS:
        shutil.copy(PROJECT_ROOT / "data" / name, data_root / name)
    return data_root

LOCATION_SOURCE = """#location inn_room
@name 律师事务所
@bg office
@character 助手
@move -> inn_hall
@present attorney_badge -> shen_present_knife
@generic_present -> shen_present_generic

## hotspot window
@rect 0.52 0.21 0.19 0.31
@scene inn_room_window_examine

## topic victim
@title 死者
@scene shen_topic_victim

## topic last_night
@title 昨夜
@scene shen_topic_last_night
@locked

#location inn_hall
@bg office
@move -> inn_room
"""

INVESTIGATION_STORY = """#location inn_room
@name 律师事务所
@bg office
@character 辩护律师
@move -> inn_hall
@present crime_report -> inv_present
@generic_present -> inv_generic

## hotspot window
@rect 0.52 0.21 0.19 0.31
@scene inv_window

## topic victim
@title 死者
@scene inv_victim

## topic last_night
@title 昨夜
@scene inv_last_night
@locked

#location inn_hall
@bg office
@move -> inn_room

## hotspot counter
@rect 0.20 0.40 0.20 0.20
@scene inv_counter

#scene inv_start
@investigation inn_room
@talk_unlock last_night
@investigation_end
@return

#scene inv_present
@return

#scene inv_generic
@return

#scene inv_window
@return

#scene inv_victim
@return

#scene inv_last_night
@return

#scene inv_counter
@return
"""

COMPILER_SOURCE = """#location inn_room
@name 律师事务所
@bg office
@character 助手
@move -> inn_hall
@present attorney_badge -> shen_present_knife
@generic_present -> shen_present_generic

## hotspot window
@rect 0.52 0.21 0.19 0.31
@scene inn_room_window_examine

## topic victim
@title 死者
@scene shen_topic_victim

## topic last_night
@title 昨夜
@scene shen_topic_last_night
@locked

#location inn_hall
@bg office
@move -> inn_room

#scene ch01_investigation_start
@bg courtroom_witness
@investigation inn_room
@talk_unlock last_night
@investigation_end
@return

#scene inn_room_window_examine
@return

#scene shen_topic_victim
@return

#scene shen_topic_last_night
@return

#scene shen_present_knife
@return

#scene shen_present_generic
@return
"""


def _parse(source: str) -> ParseResult:
    return StoryParser().parse_text(source, SOURCE_FILE)


def _codes(source: str, registries: Registries) -> set[DiagnosticCode]:
    parsed = StoryParser().parse_text(source, "chapter_01/invalid.md")
    return {item.code for item in [*parsed.diagnostics, *validate(parsed.document, registries)]}


def test_location_block_parses_every_field() -> None:
    result = _parse(LOCATION_SOURCE)

    assert result.diagnostics == []
    locations = result.document.locations
    assert [location.id for location in locations] == ["inn_room", "inn_hall"]

    location = locations[0]
    assert location.source.file == SOURCE_FILE
    assert location.source.line == 1
    assert location.name == "律师事务所"
    assert location.background == "office"
    assert location.background_source is not None and location.background_source.line == 3
    assert [name for name, _ in location.characters] == ["助手"]
    assert [source.line for _, source in location.characters] == [4]
    assert [target for target, _ in location.moves] == ["inn_hall"]
    assert [(evidence, scene) for evidence, scene, _ in location.present_reactions] == [
        ("attorney_badge", "shen_present_knife")
    ]
    assert location.generic_present == "shen_present_generic"
    assert location.generic_present_source is not None
    assert location.generic_present_source.line == 7

    assert len(location.hotspots) == 1
    hotspot = location.hotspots[0]
    assert isinstance(hotspot, HotspotNode)
    assert hotspot.id == "window"
    assert hotspot.source.line == 9
    assert hotspot.rect == (0.52, 0.21, 0.19, 0.31)
    assert hotspot.rect_source is not None and hotspot.rect_source.line == 10
    assert hotspot.scene == "inn_room_window_examine"
    assert hotspot.scene_source is not None and hotspot.scene_source.line == 11

    assert [topic.id for topic in location.topics] == ["victim", "last_night"]
    victim, last_night = location.topics
    assert (victim.title, victim.scene, victim.locked) == ("死者", "shen_topic_victim", False)
    assert victim.source.line == 13
    assert victim.title_source is not None and victim.title_source.line == 14
    assert victim.scene_source is not None and victim.scene_source.line == 15
    assert (last_night.title, last_night.scene, last_night.locked) == (
        "昨夜",
        "shen_topic_last_night",
        True,
    )

    assert isinstance(locations[1], LocationNode)
    assert locations[1].name == ""
    assert locations[1].hotspots == []
    assert locations[1].topics == []


def test_scene_header_closes_the_location() -> None:
    source = LOCATION_SOURCE + "\n#scene inn_room_window_examine\n@bg inn_hall\n@return\n\n#location inn_back_alley\n@bg inn_back_alley\n"
    result = _parse(source)

    assert result.diagnostics == []
    assert [location.id for location in result.document.locations] == [
        "inn_room",
        "inn_hall",
        "inn_back_alley",
    ]
    assert [scene.id for scene in result.document.scenes] == ["inn_room_window_examine"]

    instructions = result.document.scenes[0].instructions
    assert isinstance(instructions[0], AssetNode)
    assert instructions[0].asset_id == "inn_hall"
    assert isinstance(instructions[1], FlowNode)


def test_investigation_scene_commands_parse() -> None:
    result = _parse(
        "#scene inv_start\n"
        "@investigation inn_room\n"
        "@talk_unlock last_night\n"
        "@investigation_end\n"
        "@return\n"
    )

    assert result.diagnostics == []
    instructions = result.document.scenes[0].instructions
    assert isinstance(instructions[0], StartInvestigationNode)
    assert instructions[0].location_id == "inn_room"
    assert instructions[0].source.line == 2
    assert isinstance(instructions[1], TalkUnlockNode)
    assert instructions[1].topic_id == "last_night"
    assert isinstance(instructions[2], EndInvestigationNode)
    assert isinstance(instructions[3], FlowNode)


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        ("## hotspot window\n@rect 0.1 0.1 0.2 0.2\n@scene inv_window\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n## topic victim\n@title 死者\n@scene inv_victim\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n@name 客栈房间\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n@move -> inn_hall\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n@rect 0.1 0.1 0.2 0.2\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n@title 死者\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n@scene inv_victim\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#scene inv_start\n@locked\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@rect 0.1 0.1 0.2 0.2\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@title 死者\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@locked\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@scene inv_window\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@bgm testimony\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@goto inv_window\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n## statement s01\n", DiagnosticCode.MALFORMED_COMMAND),
        ("#location inn_room\n@bg inn_room\n陆长庚[calm]:\n正文。\n", DiagnosticCode.MALFORMED_COMMAND),
        ("#location inn_room\n@bg inn_room\n## hotspot window\n@title 死者\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n## topic victim\n@rect 0.1 0.1 0.2 0.2\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        (
            "#location inn_room\n@bg inn_room\n## hotspot window\n@rect 0.1 0.1 0.2 0.2\n@rect 0.2 0.2 0.2 0.2\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        (
            "#location inn_room\n@bg inn_room\n## topic victim\n@title 死者\n@title 死者\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        (
            "#location inn_room\n@bg inn_room\n## topic victim\n@title 死者\n@locked\n@locked\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        ("#location inn_room\n@name 客栈房间\n@name 客栈房间\n@bg inn_room\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n@bg inn_hall\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        (
            "#location inn_room\n@bg inn_room\n@generic_present -> a\n@generic_present -> b\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        ("#location inn_room\n@bg inn_room\n@character\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        ("#location inn_room\n@bg inn_room\n## hotspot window\n@rect a b c d\n@scene inv_window\n", DiagnosticCode.MALFORMED_COMMAND),
    ],
)
def test_invalid_location_content_is_rejected(
    source: str,
    expected: DiagnosticCode,
) -> None:
    assert expected in {item.code for item in _parse(source).diagnostics}


def test_location_story_is_valid(registries: Registries) -> None:
    parsed = StoryParser().parse_text(INVESTIGATION_STORY, SOURCE_FILE)

    assert parsed.diagnostics == []
    assert validate(parsed.document, registries) == []


def test_valid_rect_boundaries_are_accepted(registries: Registries) -> None:
    source = INVESTIGATION_STORY.replace("@rect 0.52 0.21 0.19 0.31", "@rect 0.0 0.0 1.0 1.0")

    assert DiagnosticCode.INVALID_HOTSPOT_RECT not in _codes(source, registries)


def test_locations_and_scenes_validate_across_files(registries: Registries) -> None:
    location_text, scene_text = INVESTIGATION_STORY.split("#scene inv_start", maxsplit=1)
    document = StoryParser().parse_text(location_text, "chapter_01/locations.md").document
    document.extend(
        StoryParser()
        .parse_text("#scene inv_start" + scene_text, "chapter_01/scenes.md")
        .document
    )

    assert [location.id for location in document.locations] == ["inn_room", "inn_hall"]
    assert validate(document, registries) == []


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        (INVESTIGATION_STORY + "#location inn_room\n@bg office\n", DiagnosticCode.DUPLICATE_LOCATION),
        (INVESTIGATION_STORY.replace("#location inn_room", "#location Inn-Room"), DiagnosticCode.INVALID_LOCATION_ID),
        (
            INVESTIGATION_STORY.replace("@bg office\n@character 辩护律师", "@character 辩护律师"),
            DiagnosticCode.LOCATION_MISSING_BACKGROUND,
        ),
        (
            INVESTIGATION_STORY.replace(
                "## hotspot window",
                "## hotspot window\n@rect 0.1 0.1 0.2 0.2\n@scene inv_window\n\n## hotspot window",
            ),
            DiagnosticCode.DUPLICATE_HOTSPOT,
        ),
        (
            INVESTIGATION_STORY.replace(
                "## topic victim",
                "## topic victim\n@title 死者\n@scene inv_victim\n\n## topic victim",
            ),
            DiagnosticCode.DUPLICATE_TOPIC,
        ),
        (INVESTIGATION_STORY.replace("## hotspot window", "## hotspot Window"), DiagnosticCode.INVALID_LOCATION_CHILD_ID),
        (INVESTIGATION_STORY.replace("## topic victim", "## topic Victim"), DiagnosticCode.INVALID_LOCATION_CHILD_ID),
        (INVESTIGATION_STORY.replace("@rect 0.52 0.21 0.19 0.31\n", ""), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("0.52 0.21 0.19 0.31", "-0.01 0.1 0.2 0.2"), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("0.52 0.21 0.19 0.31", "0.1 -0.01 0.2 0.2"), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("0.52 0.21 0.19 0.31", "0.1 0.1 0.0 0.2"), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("0.52 0.21 0.19 0.31", "0.1 0.1 0.2 0.0"), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("0.52 0.21 0.19 0.31", "0.9 0.1 0.2 0.2"), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("0.52 0.21 0.19 0.31", "0.1 0.9 0.2 0.2"), DiagnosticCode.INVALID_HOTSPOT_RECT),
        (INVESTIGATION_STORY.replace("@scene inv_window", "@scene inv_missing"), DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE),
        (INVESTIGATION_STORY.replace("@scene inv_victim", "@scene inv_missing"), DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE),
        (
            INVESTIGATION_STORY.replace(
                "@present crime_report -> inv_present",
                "@present crime_report -> inv_missing",
            ),
            DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE,
        ),
        (
            INVESTIGATION_STORY.replace(
                "@generic_present -> inv_generic",
                "@generic_present -> inv_missing",
            ),
            DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE,
        ),
        (INVESTIGATION_STORY.replace("@character 辩护律师", "@character 未知人物"), DiagnosticCode.UNKNOWN_LOCATION_CHARACTER),
        (INVESTIGATION_STORY.replace("@move -> inn_hall", "@move -> inn_missing"), DiagnosticCode.UNKNOWN_LOCATION),
        (INVESTIGATION_STORY.replace("@investigation inn_room", "@investigation inn_missing"), DiagnosticCode.UNKNOWN_LOCATION),
        (INVESTIGATION_STORY.replace("@talk_unlock last_night", "@talk_unlock missing_topic"), DiagnosticCode.UNKNOWN_TALK_TOPIC),
        (INVESTIGATION_STORY.replace("@title 死者\n", ""), DiagnosticCode.INVALID_COMMAND_CONTEXT),
        (INVESTIGATION_STORY.replace("@present crime_report", "@present missing"), DiagnosticCode.UNKNOWN_EVIDENCE),
        (
            INVESTIGATION_STORY.replace(
                "@present crime_report -> inv_present",
                "@present crime_report -> inv_present\n@present crime_report -> inv_present",
            ),
            DiagnosticCode.DUPLICATE_PRESENT_RULE,
        ),
    ],
)
def test_invalid_location_story_is_rejected(
    source: str,
    expected: DiagnosticCode,
    registries: Registries,
) -> None:
    assert expected in _codes(source, registries)


def test_compiled_location_matches_frozen_schema(tmp_path: Path) -> None:
    source_root = tmp_path / "story_src"
    (source_root / "chapter_01").mkdir(parents=True)
    (source_root / "chapter_01" / "investigation.md").write_text(
        COMPILER_SOURCE, encoding="utf-8"
    )
    output_root = tmp_path / "story_build"

    build_project(source_root, _isolated_data_root(tmp_path), output_root)

    story = json.loads((output_root / "story.json").read_text(encoding="utf-8"))
    manifest = json.loads((output_root / "manifest.json").read_text(encoding="utf-8"))

    def line_of(needle: str) -> int:
        return COMPILER_SOURCE.splitlines().index(needle) + 1

    def source_at(line: int) -> dict[str, object]:
        return {"file": SOURCE_FILE, "line": line}

    assert story["schema_version"] == 1
    assert story["entry_scene"] == "ch01_investigation_start"
    assert story["locations"] == {
        "inn_room": {
            "id": "inn_room",
            "name": "律师事务所",
            "background": "office",
            "characters": ["assistant"],
            "moves": ["inn_hall"],
            "present_reactions": {"attorney_badge": "shen_present_knife"},
            "generic_present": "shen_present_generic",
            "hotspots": [
                {
                    "id": "window",
                    "rect": [0.52, 0.21, 0.19, 0.31],
                    "scene": "inn_room_window_examine",
                    "source": source_at(line_of("## hotspot window")),
                }
            ],
            "topics": [
                {
                    "id": "victim",
                    "title": "死者",
                    "scene": "shen_topic_victim",
                    "locked": False,
                    "source": source_at(line_of("## topic victim")),
                },
                {
                    "id": "last_night",
                    "title": "昨夜",
                    "scene": "shen_topic_last_night",
                    "locked": True,
                    "source": source_at(line_of("## topic last_night")),
                },
            ],
            "source": source_at(1),
        },
        "inn_hall": {
            "id": "inn_hall",
            "name": "",
            "background": "office",
            "characters": [],
            "moves": ["inn_room"],
            "present_reactions": {},
            "generic_present": "",
            "hotspots": [],
            "topics": [],
            "source": source_at(line_of("#location inn_hall")),
        },
    }
    assert story["scenes"]["ch01_investigation_start"]["instructions"] == [
        {
            "op": "bg",
            "background": "courtroom_witness",
            "source": source_at(line_of("@bg courtroom_witness")),
        },
        {
            "op": "investigation",
            "location": "inn_room",
            "source": source_at(line_of("@investigation inn_room")),
        },
        {
            "op": "talk_unlock",
            "topic": "last_night",
            "source": source_at(line_of("@talk_unlock last_night")),
        },
        {
            "op": "investigation_end",
            "source": source_at(line_of("@investigation_end")),
        },
        {"op": "return", "source": source_at(line_of("@return"))},
    ]
    assert manifest["locations"] == ["inn_hall", "inn_room"]
