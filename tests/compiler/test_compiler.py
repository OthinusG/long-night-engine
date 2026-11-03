import json
from pathlib import Path

import pytest

from tools.story_compiler.compiler import build_project, validate_project
from tools.story_compiler.diagnostics import CompilationError, DiagnosticCode

PROJECT_ROOT = Path(__file__).parents[2]


def test_valid_demo_compiles(tmp_path: Path) -> None:
    summary = build_project(
        PROJECT_ROOT / "story_src",
        PROJECT_ROOT / "data",
        tmp_path,
    )

    assert summary.scene_count == 20
    assert summary.testimony_count == 1
    assert (tmp_path / "story.json").is_file()
    assert (tmp_path / "manifest.json").is_file()


def test_compiled_json_matches_frozen_schema(tmp_path: Path) -> None:
    build_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data", tmp_path)
    story = json.loads((tmp_path / "story.json").read_text(encoding="utf-8"))

    assert story["schema_version"] == 1
    assert story["entry_scene"] == "scene_demo_intro"
    assert set(story) == {
        "schema_version",
        "entry_scene",
        "scenes",
        "testimonies",
        "locations",
    }
    operations = {
        instruction["op"]
        for scene in story["scenes"].values()
        for instruction in scene["instructions"]
    }
    assert operations.issubset({
        "say",
        "goto",
        "call",
        "return",
        "flag",
        "condition",
        "bg",
        "bgm",
        "sfx",
        "start_testimony",
        "evidence_add",
        "evidence_update",
        "evidence_remove",
        "investigation",
        "investigation_end",
        "talk_unlock",
        "procedure",
        "procedure_end",
        "stage",
    })
    assert {"location_office", "location_crime_scene"}.issubset(set(story["locations"]))
    testimony = story["testimonies"]["testimony_demo_01"]
    assert testimony["wrong_penalty"] == 20
    assert len(testimony["statements"]) == 4
    assert testimony["statements"][2]["present_rules"][0]["evidence"] == "crime_report"


def test_stage_commands_compile(tmp_path: Path) -> None:
    build_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data", tmp_path)
    story = json.loads((tmp_path / "story.json").read_text(encoding="utf-8"))

    instructions = [
        instruction
        for scene in story["scenes"].values()
        for instruction in scene["instructions"]
        if instruction["op"] == "stage"
    ]

    assert {
        ("protagonist", "center", "normal", True),
        ("assistant", "right", "normal", True),
    }.issubset(
        {
            (
                instruction["character"],
                instruction["slot"],
                instruction["expression"],
                instruction["visible"],
            )
            for instruction in instructions
        }
    )


def test_source_mapping_is_preserved(tmp_path: Path) -> None:
    build_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data", tmp_path)
    story = json.loads((tmp_path / "story.json").read_text(encoding="utf-8"))

    for scene in story["scenes"].values():
        assert set(scene["source"]) == {"file", "line"}
        for instruction in scene["instructions"]:
            assert set(instruction["source"]) == {"file", "line"}
    for testimony in story["testimonies"].values():
        assert set(testimony["source"]) == {"file", "line"}
        for statement in testimony["statements"]:
            assert set(statement["source"]) == {"file", "line"}
            for rule in statement["present_rules"]:
                assert set(rule["source"]) == {"file", "line"}


def test_build_output_is_deterministic(tmp_path: Path) -> None:
    build_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data", tmp_path)
    first_story = (tmp_path / "story.json").read_bytes()
    first_manifest = (tmp_path / "manifest.json").read_bytes()

    build_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data", tmp_path)

    assert (tmp_path / "story.json").read_bytes() == first_story
    assert (tmp_path / "manifest.json").read_bytes() == first_manifest


def test_validate_demo() -> None:
    summary = validate_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data")

    assert summary.scene_count == 20
    assert summary.testimony_count == 1


def test_invalid_fixture_fails_validation() -> None:
    fixture_root = Path(__file__).parent / "fixtures"

    with pytest.raises(CompilationError) as error:
        validate_project(fixture_root, PROJECT_ROOT / "data")

    assert DiagnosticCode.UNKNOWN_EVIDENCE in {
        diagnostic.code for diagnostic in error.value.diagnostics
    }
