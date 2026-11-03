import json
from dataclasses import replace
from pathlib import Path

import pytest

from tools.story_compiler.compiler import build_project, validate_project
from tools.story_compiler.diagnostics import CompilationError, DiagnosticCode
from tools.story_compiler.models import (
    EndProcedureNode,
    FlowNode,
    StartProcedureNode,
)
from tools.story_compiler.parser import ParseResult, StoryParser
from tools.story_compiler.registry import (
    EvidenceInspection,
    IdRegistry,
    InspectionHotspot,
    InspectionRegistry,
    ProcedureAction,
    ProcedureContext,
    ProcedureRegistry,
    Registries,
    RegistryError,
    load_registries,
)
from tools.story_compiler.validator import validate

PROJECT_ROOT = Path(__file__).parents[2]
SOURCE_FILE = "chapter_01/procedure_inspection.md"

PROCEDURE_STORY = """#scene proc_start
@procedure zhao_illegal_termination

#scene proc_continue
陆长庚[calm]:
依律，问询不得中止。
@procedure_end
@return

#scene proc_challenge
@return
"""

PRESENT_STORY = """#scene demo_start
@testimony zhao_demo_01
@penalty 20
@wrong -> demo_wrong

## statement demo_s01

赵廷禄[calm]:
本官昨夜在县衙。
@present night_duty_log verified -> demo_break

## statement demo_s02

赵廷禄[calm]:
值夜之人可以作证。
@present night_duty_log -> demo_break

@endtestimony
@return

#scene demo_wrong
@return

#scene demo_break
@return
"""

DATA_STORY = """#scene proc_start
@bg county_court_day
陆长庚[calm]:
正文。

#scene proc_continue
@return

#scene proc_challenge
@return

#scene inspect_handle
@return

#scene inspect_blade
@return

#scene inspect_stain
@return
"""

BUILD_STORY = """#scene proc_start
@bg county_court_day
@procedure zhao_illegal_termination

#scene proc_continue
陆长庚[calm]:
问询继续。

@procedure_end
@return

#scene proc_wrong
@return

#scene proc_break
@return

#scene proc_trial
@testimony zhao_proc_01
@penalty 10
@wrong -> proc_wrong

## statement zhao_proc_s01

赵廷禄[calm]:
本官昨夜在县衙。
@present night_duty_log verified -> proc_break

## statement zhao_proc_s02

赵廷禄[calm]:
值夜之人可以作证。
@present night_duty_log -> proc_wrong

@endtestimony
@return

#scene inspect_handle
@return

#scene inspect_stain
@return
"""

REQUIRED_REGISTRIES: dict[str, object] = {
    "characters.json": {
        "characters": [
            {"id": "lu_changgeng", "display_name": "陆长庚"},
            {"id": "zhao_tinglu", "display_name": "赵廷禄"},
        ]
    },
    "expressions.json": {
        "expressions": {
            "lu_changgeng": ["calm"],
            "zhao_tinglu": ["calm"],
        }
    },
    "evidence.json": {
        "evidence": [
            {
                "id": "night_duty_log",
                "name": "夜值簿",
                "versions": {"verified": {"description": "换班时辰已核对。"}},
            },
            {"id": "temporary_note", "name": "临时笔记"},
        ]
    },
    "backgrounds.json": {"backgrounds": [{"id": "county_court_day"}]},
    "bgm.json": {"bgm": [{"id": "testimony"}]},
    "sfx.json": {"sfx": [{"id": "gavel_light"}]},
}


def _write_data_root(root: Path, extra: dict[str, object]) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for name, value in {**REQUIRED_REGISTRIES, **extra}.items():
        (root / name).write_text(json.dumps(value), encoding="utf-8")


def _parse(source: str) -> ParseResult:
    return StoryParser().parse_text(source, SOURCE_FILE)


def _codes(source: str, registries: Registries) -> set[DiagnosticCode]:
    parsed = StoryParser().parse_text(source, "chapter_01/invalid.md")
    return {item.code for item in [*parsed.diagnostics, *validate(parsed.document, registries)]}


def _action(
    action_id: str = "request_continue_questioning",
    *,
    scene: str = "proc_continue",
    result: str = "correct",
    required_evidence: str = "",
) -> ProcedureAction:
    return ProcedureAction(
        action_id, "请求继续问询", "依律继续。", scene, result, required_evidence
    )


def _context(
    context_id: str = "zhao_illegal_termination",
    *,
    actions: tuple[ProcedureAction, ...] = (),
) -> ProcedureContext:
    return ProcedureContext(context_id, "程序异议", "赵县令中止问询。", actions)


def _procedure(*contexts: ProcedureContext) -> ProcedureRegistry:
    return ProcedureRegistry(contexts)


def _hotspot(
    hotspot_id: str = "handle_mark",
    *,
    scene: str = "inspect_handle",
    rect: tuple[float, float, float, float] | None = (0.1, 0.1, 0.2, 0.2),
    unlocked_by: str = "",
) -> InspectionHotspot:
    return InspectionHotspot(hotspot_id, scene, rect, unlocked_by)


def _inspection(
    *hotspots: InspectionHotspot,
    evidence_id: str = "night_duty_log",
) -> EvidenceInspection:
    return EvidenceInspection(evidence_id, "night_duty_log_detail", hotspots)


def _inspections(*inspections: EvidenceInspection) -> InspectionRegistry:
    return InspectionRegistry(inspections)


@pytest.fixture
def versioned(registries: Registries) -> Registries:
    return replace(
        registries,
        evidence=IdRegistry(
            ids=frozenset({"night_duty_log", "wrong_evidence"}),
            versions_by_id={"night_duty_log": frozenset({"verified"})},
        ),
    )


def test_procedure_commands_parse() -> None:
    result = _parse(PROCEDURE_STORY)

    assert result.diagnostics == []
    start = result.document.scenes[0].instructions
    assert len(start) == 1
    assert isinstance(start[0], StartProcedureNode)
    assert start[0].context_id == "zhao_illegal_termination"
    assert start[0].source.line == 2

    branch = result.document.scenes[1].instructions
    assert isinstance(branch[1], EndProcedureNode)
    assert branch[1].source.line == 7
    assert isinstance(branch[2], FlowNode)


def test_present_version_token_parses() -> None:
    result = _parse(PRESENT_STORY)

    assert result.diagnostics == []
    statements = result.document.testimonies[0].statements

    versioned_rule = statements[0].present_rules[0]
    assert versioned_rule.evidence_id == "night_duty_log"
    assert versioned_rule.version == "verified"
    assert versioned_rule.target_scene == "demo_break"
    assert versioned_rule.source.line == 10

    plain_rule = statements[1].present_rules[0]
    assert plain_rule.version == ""
    assert plain_rule.target_scene == "demo_break"


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        ("#scene proc_start\n@procedure\n", DiagnosticCode.MALFORMED_COMMAND),
        ("#scene proc_start\n@procedure a b\n", DiagnosticCode.MALFORMED_COMMAND),
        ("#scene proc_start\n@procedure_end extra\n", DiagnosticCode.MALFORMED_COMMAND),
        (
            "#scene proc_start\n@testimony t01\n@penalty 10\n@wrong -> w\n## statement s01\n"
            "赵廷禄[calm]:\n证言。\n@procedure ctx\n@endtestimony\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        (
            "#scene proc_start\n@testimony t01\n@penalty 10\n@wrong -> w\n## statement s01\n"
            "赵廷禄[calm]:\n证言。\n@procedure_end\n@endtestimony\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        (
            "#location inn_room\n@bg county_court_day\n@procedure ctx\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        (
            "#location inn_room\n@bg county_court_day\n@procedure_end\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        ("@procedure ctx\n", DiagnosticCode.INVALID_COMMAND_CONTEXT),
        (
            "#location inn_room\n@bg county_court_day\n"
            "@present night_duty_log verified -> inv_present\n",
            DiagnosticCode.INVALID_COMMAND_CONTEXT,
        ),
        (
            "#scene demo_start\n@testimony t01\n@penalty 10\n@wrong -> w\n## statement s01\n"
            "赵廷禄[calm]:\n证言。\n@present night_duty_log verified extra -> b\n@endtestimony\n",
            DiagnosticCode.MALFORMED_COMMAND,
        ),
        (
            "#scene demo_start\n@testimony t01\n@penalty 10\n@wrong -> w\n## statement s01\n"
            "赵廷禄[calm]:\n证言。\n@present -> b\n@endtestimony\n",
            DiagnosticCode.MALFORMED_COMMAND,
        ),
        (
            "#scene demo_start\n@testimony t01\n@penalty 10\n@wrong -> w\n## statement s01\n"
            "赵廷禄[calm]:\n证言。\n@present night_duty_log verified\n@endtestimony\n",
            DiagnosticCode.MALFORMED_COMMAND,
        ),
    ],
)
def test_malformed_procedure_and_present_commands_are_rejected(
    source: str,
    expected: DiagnosticCode,
) -> None:
    assert expected in {item.code for item in _parse(source).diagnostics}


def test_valid_procedure_story_is_accepted(registries: Registries) -> None:
    story = _parse(PROCEDURE_STORY)
    configured = replace(
        registries,
        procedure=_procedure(
            _context(
                actions=(
                    _action(),
                    _action("challenge_procedure", scene="proc_challenge", result="wrong"),
                )
            )
        ),
    )

    assert validate(story.document, configured) == []


def test_unknown_procedure_context_is_rejected(registries: Registries) -> None:
    source = PROCEDURE_STORY.replace(
        "@procedure zhao_illegal_termination", "@procedure missing_context"
    )

    assert _codes(source, registries) == {DiagnosticCode.UNKNOWN_PROCEDURE_CONTEXT}


def test_known_evidence_version_is_accepted(versioned: Registries) -> None:
    assert _codes(PRESENT_STORY, versioned) == set()


def test_unknown_evidence_version_is_rejected(versioned: Registries) -> None:
    source = PRESENT_STORY.replace("night_duty_log verified", "night_duty_log invented")

    assert _codes(source, versioned) == {DiagnosticCode.UNKNOWN_EVIDENCE_VERSION}


def test_unversioned_present_rule_needs_no_version_catalogue(
    registries: Registries,
) -> None:
    source = PRESENT_STORY.replace(" night_duty_log verified", "")

    assert DiagnosticCode.UNKNOWN_EVIDENCE_VERSION not in _codes(source, registries)


def test_present_version_is_not_checked_when_evidence_is_unknown(
    versioned: Registries,
) -> None:
    source = PRESENT_STORY.replace("night_duty_log verified", "missing_evidence verified")

    assert _codes(source, versioned) == {DiagnosticCode.UNKNOWN_EVIDENCE}


@pytest.mark.parametrize(
    ("procedure", "expected"),
    [
        (
            _procedure(_context(actions=(_action(), _action()))),
            DiagnosticCode.DUPLICATE_PROCEDURE_ACTION,
        ),
        (
            _procedure(
                _context("zhao_illegal_termination", actions=(_action(),)),
                _context(actions=(_action(),)),
            ),
            DiagnosticCode.DUPLICATE_PROCEDURE_CONTEXT,
        ),
        (
            _procedure(_context("Zhao-Illegal", actions=(_action(),))),
            DiagnosticCode.INVALID_PROCEDURE_ID,
        ),
        (
            _procedure(_context(actions=(_action("Request-Continue"),))),
            DiagnosticCode.INVALID_PROCEDURE_ID,
        ),
        (
            _procedure(_context(actions=())),
            DiagnosticCode.EMPTY_PROCEDURE_CONTEXT,
        ),
        (
            _procedure(_context(actions=(_action(result="maybe"),))),
            DiagnosticCode.INVALID_PROCEDURE_RESULT,
        ),
        (
            _procedure(_context(actions=(_action(result=""),))),
            DiagnosticCode.INVALID_PROCEDURE_RESULT,
        ),
        (
            _procedure(_context(actions=(_action(scene="missing_scene"),))),
            DiagnosticCode.UNKNOWN_PROCEDURE_SCENE,
        ),
        (
            _procedure(_context(actions=(_action(required_evidence="missing_evidence"),))),
            DiagnosticCode.UNKNOWN_EVIDENCE,
        ),
    ],
)
def test_invalid_procedure_data_is_rejected(
    procedure: ProcedureRegistry,
    expected: DiagnosticCode,
    registries: Registries,
) -> None:
    configured = replace(registries, procedure=procedure)

    assert _codes(DATA_STORY, configured) == {expected}


def test_procedure_data_diagnostics_point_at_the_data_file(
    registries: Registries,
) -> None:
    story = _parse(DATA_STORY)
    configured = replace(registries, procedure=_procedure(_context(actions=())))

    diagnostic = next(
        item
        for item in validate(story.document, configured)
        if item.code == DiagnosticCode.EMPTY_PROCEDURE_CONTEXT
    )

    assert diagnostic.location.file == "data/procedure.json"
    assert diagnostic.location.line == 1
    rendered = diagnostic.render()
    assert "data/procedure.json:1" in rendered
    assert "ERROR LN1607" in rendered
    assert "zhao_illegal_termination" in rendered


@pytest.mark.parametrize(
    ("inspections", "expected"),
    [
        (
            _inspections(_inspection(_hotspot()), _inspection(_hotspot())),
            DiagnosticCode.DUPLICATE_INSPECTION,
        ),
        (
            _inspections(_inspection(_hotspot(), evidence_id="missing_evidence")),
            DiagnosticCode.UNKNOWN_INSPECTION_EVIDENCE,
        ),
        (
            _inspections(_inspection(_hotspot("Handle-Mark"))),
            DiagnosticCode.INVALID_INSPECTION_HOTSPOT,
        ),
        (
            _inspections(_inspection(_hotspot(), _hotspot())),
            DiagnosticCode.DUPLICATE_INSPECTION_HOTSPOT,
        ),
        (
            _inspections(_inspection(_hotspot(rect=None))),
            DiagnosticCode.INVALID_INSPECTION_RECT,
        ),
        (
            _inspections(_inspection(_hotspot(rect=(0.1, 0.1, 0.0, 0.2)))),
            DiagnosticCode.INVALID_INSPECTION_RECT,
        ),
        (
            _inspections(_inspection(_hotspot(scene="missing_scene"))),
            DiagnosticCode.UNKNOWN_INSPECTION_SCENE,
        ),
        (
            _inspections(_inspection(_hotspot(unlocked_by="missing_hotspot"))),
            DiagnosticCode.UNKNOWN_INSPECTION_UNLOCK,
        ),
        (
            _inspections(_inspection(_hotspot(unlocked_by="handle_mark"))),
            DiagnosticCode.UNKNOWN_INSPECTION_UNLOCK,
        ),
        (
            _inspections(_inspection()),
            DiagnosticCode.EMPTY_INSPECTION,
        ),
    ],
)
def test_invalid_inspection_data_is_rejected(
    inspections: InspectionRegistry,
    expected: DiagnosticCode,
    registries: Registries,
) -> None:
    configured = replace(registries, inspections=inspections)

    assert _codes(DATA_STORY, configured) == {expected}


def test_valid_inspection_data_is_accepted(registries: Registries) -> None:
    configured = replace(
        registries,
        inspections=_inspections(
            _inspection(
                _hotspot(),
                _hotspot("blade_edge", scene="inspect_blade"),
                _hotspot(
                    "blood_stain",
                    scene="inspect_stain",
                    rect=(0.4, 0.58, 0.12, 0.1),
                    unlocked_by="blade_edge",
                ),
            )
        ),
    )

    assert _codes(DATA_STORY, configured) == set()


@pytest.mark.parametrize(
    ("rect", "expected"),
    [
        ((0.0, 0.0, 1.0, 1.0), None),
        ((0.9, 0.9, 0.1, 0.1), None),
        ((0.1, 0.1, 0.0, 0.2), DiagnosticCode.INVALID_INSPECTION_RECT),
        ((0.1, 0.1, 0.2, 0.0), DiagnosticCode.INVALID_INSPECTION_RECT),
        ((-0.01, 0.1, 0.2, 0.2), DiagnosticCode.INVALID_INSPECTION_RECT),
        ((0.1, -0.01, 0.2, 0.2), DiagnosticCode.INVALID_INSPECTION_RECT),
        ((0.9, 0.1, 0.2, 0.2), DiagnosticCode.INVALID_INSPECTION_RECT),
        ((0.1, 0.9, 0.2, 0.2), DiagnosticCode.INVALID_INSPECTION_RECT),
        (None, DiagnosticCode.INVALID_INSPECTION_RECT),
    ],
)
def test_inspection_rect_bounds(
    rect: tuple[float, float, float, float] | None,
    expected: DiagnosticCode | None,
    registries: Registries,
) -> None:
    configured = replace(
        registries, inspections=_inspections(_inspection(_hotspot(rect=rect)))
    )
    codes = _codes(DATA_STORY, configured)

    if expected is None:
        assert codes == set()
    else:
        assert codes == {expected}


def test_compiled_procedure_and_version_ir_matches_frozen_schema(
    tmp_path: Path,
) -> None:
    source_root = tmp_path / "story_src"
    (source_root / "chapter_01").mkdir(parents=True)
    (source_root / "chapter_01" / "procedure.md").write_text(
        BUILD_STORY, encoding="utf-8"
    )
    data_root = tmp_path / "data"
    _write_data_root(
        data_root,
        {
            "procedure.json": {
                "contexts": [
                    {
                        "id": "zhao_illegal_termination",
                        "title": "程序异议",
                        "description": "赵县令中止问询。",
                        "actions": [
                            {
                                "id": "request_continue_questioning",
                                "name": "请求继续问询",
                                "description": "依律继续。",
                                "result": "correct",
                                "scene": "proc_continue",
                            },
                            {
                                "id": "accept_termination",
                                "name": "接受终止",
                                "description": "停止问询。",
                                "result": "wrong",
                                "scene": "proc_wrong",
                                "required_evidence": "night_duty_log",
                                "required_flag": "asked_zhao",
                            },
                        ],
                    }
                ]
            },
            "evidence_inspections.json": {
                "inspections": [
                    {
                        "evidence_id": "night_duty_log",
                        "image": "night_duty_log_detail",
                        "hotspots": [
                            {
                                "id": "handle_mark",
                                "rect": [0.62, 0.38, 0.14, 0.18],
                                "scene": "inspect_handle",
                            },
                            {
                                "id": "blood_stain",
                                "rect": [0.4, 0.58, 0.12, 0.1],
                                "scene": "inspect_stain",
                                "unlocked_by": "handle_mark",
                            },
                        ],
                    }
                ]
            },
        },
    )
    output_root = tmp_path / "story_build"

    build_project(source_root, data_root, output_root)

    story = json.loads((output_root / "story.json").read_text(encoding="utf-8"))

    def line_of(needle: str) -> int:
        return BUILD_STORY.splitlines().index(needle) + 1

    def source_at(line: int) -> dict[str, object]:
        return {"file": "chapter_01/procedure.md", "line": line}

    assert set(story) == {"schema_version", "entry_scene", "scenes", "testimonies"}
    assert story["entry_scene"] == "proc_start"
    assert story["scenes"]["proc_start"]["instructions"] == [
        {
            "op": "bg",
            "background": "county_court_day",
            "source": source_at(line_of("@bg county_court_day")),
        },
        {
            "op": "procedure",
            "context": "zhao_illegal_termination",
            "source": source_at(line_of("@procedure zhao_illegal_termination")),
        },
    ]
    assert story["scenes"]["proc_continue"]["instructions"][-2] == {
        "op": "procedure_end",
        "source": source_at(line_of("@procedure_end")),
    }
    assert story["testimonies"]["zhao_proc_01"]["statements"][0]["present_rules"] == [
        {
            "evidence": "night_duty_log",
            "required_version": "verified",
            "result": "correct",
            "source": source_at(line_of("@present night_duty_log verified -> proc_break")),
            "target": "proc_break",
        }
    ]
    assert story["testimonies"]["zhao_proc_01"]["statements"][1]["present_rules"] == [
        {
            "evidence": "night_duty_log",
            "required_version": "",
            "result": "correct",
            "source": source_at(line_of("@present night_duty_log -> proc_wrong")),
            "target": "proc_wrong",
        }
    ]


def test_missing_catalog_files_disable_the_catalogs(tmp_path: Path) -> None:
    data_root = tmp_path / "data"
    _write_data_root(data_root, {})

    registries = load_registries(data_root)

    assert registries.procedure.contexts == ()
    assert registries.inspections.inspections == ()
    assert not registries.procedure.contains("zhao_illegal_termination")
    assert registries.evidence.contains("night_duty_log")


def test_evidence_versions_are_loaded(tmp_path: Path) -> None:
    data_root = tmp_path / "data"
    _write_data_root(data_root, {})

    registries = load_registries(data_root)

    assert registries.evidence.contains_version("night_duty_log", "verified")
    assert not registries.evidence.contains_version("night_duty_log", "invented")
    assert not registries.evidence.contains_version("temporary_note", "verified")


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("procedure.json", {"contexts": [{"id": "ctx"}]}),
        ("procedure.json", {"contexts": "not-an-array"}),
        ("procedure.json", []),
        ("evidence_inspections.json", {"inspections": [{"evidence_id": "night_duty_log"}]}),
        ("evidence_inspections.json", {"inspections": "not-an-array"}),
    ],
)
def test_malformed_catalog_files_are_registry_errors(
    tmp_path: Path, name: str, value: object
) -> None:
    data_root = tmp_path / "data"
    _write_data_root(data_root, {name: value})

    with pytest.raises(RegistryError):
        load_registries(data_root)


def test_malformed_catalog_is_reported_as_invalid_registry(tmp_path: Path) -> None:
    source_root = tmp_path / "story_src"
    (source_root / "chapter_01").mkdir(parents=True)
    (source_root / "chapter_01" / "procedure.md").write_text(
        DATA_STORY, encoding="utf-8"
    )
    data_root = tmp_path / "data"
    _write_data_root(data_root, {"procedure.json": {"contexts": [{"id": "ctx"}]}})

    with pytest.raises(CompilationError) as error:
        validate_project(source_root, data_root)

    assert DiagnosticCode.INVALID_REGISTRY in {
        diagnostic.code for diagnostic in error.value.diagnostics
    }
    assert any(
        diagnostic.location.file == "data/procedure.json"
        for diagnostic in error.value.diagnostics
    )


def test_project_catalogs_are_loaded() -> None:
    registries = load_registries(PROJECT_ROOT / "data")

    assert registries.procedure.contains("court_procedural_crisis")
    assert [item.evidence_id for item in registries.inspections.inspections] == [
        "pocket_watch"
    ]
    assert registries.evidence.contains_version("crime_report", "verified")


def test_project_validates_with_catalogs() -> None:
    summary = validate_project(PROJECT_ROOT / "story_src", PROJECT_ROOT / "data")

    assert summary.scene_count > 0
