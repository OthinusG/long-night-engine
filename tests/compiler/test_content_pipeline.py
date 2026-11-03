import json
import shutil
from pathlib import Path

import pytest

from tools.story_compiler import check_all
from tools.story_compiler.asset_validator import ASSET_KINDS, validate_assets
from tools.story_compiler.compiler import build_project
from tools.story_compiler.content_loader import ContentCatalog, load_content
from tools.story_compiler.content_validator import (
    validate_cross_references,
    validate_structure,
)
from tools.story_compiler.diagnostics import (
    Diagnostic,
    DiagnosticCode,
    DiagnosticSeverity,
)
from tools.story_compiler.manifest_builder import build_manifest
from tools.story_compiler.parser import StoryParser

PROJECT_ROOT = Path(__file__).parents[2]
SOURCE_FILE = "chapter_01/content.md"
BASE_CATALOGS = (
    "characters.json",
    "expressions.json",
    "evidence.json",
    "backgrounds.json",
    "bgm.json",
    "sfx.json",
)

VALID_STORY = """#scene content_start
@bg office
辩护律师[normal]:
正文。
@return
"""


def _story_root(tmp_path: Path, source: str) -> Path:
    story_file = tmp_path / "story_src" / "chapter_01" / "content.md"
    story_file.parent.mkdir(parents=True, exist_ok=True)
    story_file.write_text(source, encoding="utf-8")
    return tmp_path / "story_src"


def _data_root(tmp_path: Path, extra: dict[str, object] | None = None) -> Path:
    """Fixture data root: the real catalogs plus explicit overrides.

    Only the catalogs a test needs are copied, so project content cannot leak
    into a fixture the way test_investigation._isolated_data_root avoids.
    """
    data_root = tmp_path / "data"
    data_root.mkdir(parents=True, exist_ok=True)
    for name in BASE_CATALOGS:
        shutil.copy(PROJECT_ROOT / "data" / name, data_root / name)
    for name, value in (extra or {}).items():
        (data_root / name).write_text(
            json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    return data_root


def _catalog(tmp_path: Path, extra: dict[str, object] | None = None) -> ContentCatalog:
    return load_content(_data_root(tmp_path, extra)).catalog


def _document(source: str):
    return StoryParser().parse_text(source, SOURCE_FILE).document


def _codes(diagnostics: list[Diagnostic]) -> set[DiagnosticCode]:
    return {item.code for item in diagnostics}


def _diagnostic(diagnostics: list[Diagnostic], code: DiagnosticCode) -> Diagnostic:
    return next(item for item in diagnostics if item.code == code)


def test_asset_convention_matches_frozen_table() -> None:
    assert [
        (kind.name, kind.root, kind.extensions) for kind in ASSET_KINDS
    ] == [
        ("background", "res://assets/backgrounds/", ("webp", "png", "jpg", "jpeg")),
        ("portrait", "res://assets/portraits/", ("webp", "png")),
        ("icon", "res://assets/evidence/", ("webp", "png")),
        ("detail", "res://assets/evidence/detail/", ("webp", "png")),
        ("bgm", "res://assets/audio/bgm/", ("ogg", "mp3", "wav")),
        ("sfx", "res://assets/audio/sfx/", ("ogg", "wav", "mp3")),
    ]


def test_duplicate_character_is_rejected(tmp_path: Path) -> None:
    result = load_content(
        _data_root(
            tmp_path,
            {
                "characters.json": {
                    "characters": [
                        {"id": "lu_changgeng", "display_name": "陆长庚"},
                        {"id": "lu_changgeng", "display_name": "陆长庚（重复）"},
                    ]
                }
            },
        )
    )

    codes = _codes(list(result.diagnostics))
    assert DiagnosticCode.DUPLICATE_CHARACTER in codes
    assert "lu_changgeng" in _diagnostic(
        list(result.diagnostics), DiagnosticCode.DUPLICATE_CHARACTER
    ).message


@pytest.mark.parametrize(
    ("name", "value", "code"),
    [
        (
            "evidence.json",
            {"evidence": [{"id": "a"}, {"id": "a"}]},
            DiagnosticCode.DUPLICATE_EVIDENCE,
        ),
        (
            "backgrounds.json",
            {"backgrounds": [{"id": "a"}, {"id": "a"}]},
            DiagnosticCode.DUPLICATE_BACKGROUND,
        ),
        ("bgm.json", {"bgm": [{"id": "a"}, {"id": "a"}]}, DiagnosticCode.DUPLICATE_BGM),
        ("sfx.json", {"sfx": [{"id": "a"}, {"id": "a"}]}, DiagnosticCode.DUPLICATE_SFX),
        (
            "expressions.json",
            {"expressions": {"protagonist": ["normal", "normal"]}},
            DiagnosticCode.DUPLICATE_EXPRESSION,
        ),
        (
            "procedure.json",
            {
                "contexts": [
                    {"id": "ctx", "title": "t", "description": "d", "actions": []},
                    {"id": "ctx", "title": "t", "description": "d", "actions": []},
                ]
            },
            DiagnosticCode.DUPLICATE_PROCEDURE_CONTEXT_ID,
        ),
        (
            "procedure.json",
            {
                "contexts": [
                    {
                        "id": "ctx",
                        "title": "t",
                        "description": "d",
                        "actions": [
                            {"id": "act", "name": "n", "description": "d", "scene": "s"},
                            {"id": "act", "name": "n", "description": "d", "scene": "s"},
                        ],
                    }
                ]
            },
            DiagnosticCode.DUPLICATE_PROCEDURE_ACTION_ID,
        ),
        (
            "evidence_inspections.json",
            {
                "inspections": [
                    {"evidence_id": "e", "image": "i", "hotspots": []},
                    {"evidence_id": "e", "image": "i", "hotspots": []},
                ]
            },
            DiagnosticCode.DUPLICATE_INSPECTION_EVIDENCE,
        ),
        (
            "evidence_inspections.json",
            {
                "inspections": [
                    {
                        "evidence_id": "e",
                        "image": "i",
                        "hotspots": [
                            {"id": "h", "rect": [0.1, 0.1, 0.2, 0.2], "scene": "s"},
                            {"id": "h", "rect": [0.1, 0.1, 0.2, 0.2], "scene": "s"},
                        ],
                    }
                ]
            },
            DiagnosticCode.DUPLICATE_INSPECTION_HOTSPOT_ID,
        ),
    ],
)
def test_duplicate_catalog_ids_are_rejected(
    tmp_path: Path, name: str, value: object, code: DiagnosticCode
) -> None:
    result = load_content(_data_root(tmp_path, {name: value}))

    assert code in _codes(list(result.diagnostics))


def test_duplicate_story_ids_are_rejected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
@testimony content_testimony
@penalty 20
@wrong -> content_other

## statement content_s01

辩护律师[normal]:
第一句。

@endtestimony
@return

#scene content_start
@return

#scene content_other
@testimony content_testimony
@penalty 20
@wrong -> content_start

## statement content_s02

辩护律师[normal]:
第二句。

@endtestimony
@return

#location inn_room
@name 客栈房间
@bg office

#location inn_room
@name 另一间房
@bg office
"""
    )

    codes = _codes(validate_structure(document))
    assert codes == {
        DiagnosticCode.DUPLICATE_SCENE_ID,
        DiagnosticCode.DUPLICATE_LOCATION_ID,
        DiagnosticCode.DUPLICATE_TESTIMONY_ID,
    }


def test_unknown_expression_is_rejected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
辩护律师[angry_2]:
正文。
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.UNKNOWN_EXPRESSION_REFERENCE)

    assert diagnostic.location.file == SOURCE_FILE
    assert diagnostic.location.line == 2
    assert "angry_2" in diagnostic.message
    assert "protagonist" in diagnostic.message
    assert "normal" in diagnostic.message


def test_missing_background_is_rejected(tmp_path: Path) -> None:
    catalog = _catalog(
        tmp_path,
        {
            "backgrounds.json": {
                "backgrounds": [
                    {
                        "id": "county_court_day",
                        "path": "res://assets/backgrounds/county_court_day.webp",
                    }
                ]
            }
        },
    )

    diagnostics = validate_assets(tmp_path, catalog)
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.MISSING_ASSET)

    assert diagnostic.severity is DiagnosticSeverity.ERROR
    assert "county_court_day" in diagnostic.message
    assert "county_court_day.webp" in diagnostic.message


def test_unknown_background_reference_is_rejected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
@bg no_such_background
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))

    assert DiagnosticCode.UNKNOWN_BACKGROUND_REFERENCE in _codes(diagnostics)


def test_missing_bgm_is_rejected(tmp_path: Path) -> None:
    catalog = _catalog(
        tmp_path,
        {
            "bgm.json": {
                "bgm": [{"id": "testimony", "path": "res://assets/audio/bgm/testimony.ogg"}]
            }
        },
    )

    diagnostics = validate_assets(tmp_path, catalog)
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.MISSING_ASSET)

    assert "bgm" in diagnostic.message
    assert "testimony.ogg" in diagnostic.message


def test_unknown_bgm_reference_is_rejected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
@bgm no_such_bgm
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))

    assert DiagnosticCode.UNKNOWN_BGM_REFERENCE in _codes(diagnostics)


def test_missing_sfx_is_rejected(tmp_path: Path) -> None:
    catalog = _catalog(
        tmp_path,
        {
            "sfx.json": {
                "sfx": [{"id": "gavel_light", "path": "res://assets/audio/sfx/gavel_light.ogg"}]
            }
        },
    )

    diagnostics = validate_assets(tmp_path, catalog)
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.MISSING_ASSET)

    assert "sfx" in diagnostic.message
    assert "gavel_light.ogg" in diagnostic.message


def test_unknown_sfx_reference_is_rejected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
@sfx no_such_sfx
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))

    assert DiagnosticCode.UNKNOWN_SFX_REFERENCE in _codes(diagnostics)


def test_missing_evidence_icon_is_rejected_when_authored(tmp_path: Path) -> None:
    catalog = _catalog(
        tmp_path,
        {
            "evidence.json": {
                "evidence": [
                    {
                        "id": "night_duty_log",
                        "name": "夜值簿",
                        "icon": "res://assets/evidence/night_duty_log.webp",
                    }
                ]
            }
        },
    )

    diagnostics = validate_assets(tmp_path, catalog)
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.MISSING_ASSET)

    assert "night_duty_log" in diagnostic.message
    assert diagnostic.severity is DiagnosticSeverity.ERROR


def test_invalid_location_destination_is_rejected(tmp_path: Path) -> None:
    document = _document(
        """#location inn_room
@name 客栈房间
@bg inn_room
@move -> nowhere

#scene content_start
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.UNKNOWN_MOVE_TARGET)

    assert "nowhere" in diagnostic.message
    assert "inn_room" in diagnostic.message


def test_invalid_procedure_target_is_rejected(tmp_path: Path) -> None:
    catalog = _catalog(
        tmp_path,
        {
            "procedure.json": {
                "contexts": [
                    {
                        "id": "ctx",
                        "title": "程序异议",
                        "description": "描述",
                        "actions": [
                            {
                                "id": "act",
                                "name": "动作",
                                "description": "描述",
                                "result": "correct",
                                "scene": "missing_scene",
                            }
                        ],
                    }
                ]
            }
        },
    )

    diagnostics = validate_cross_references(_document(VALID_STORY), catalog)
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.UNKNOWN_PROCEDURE_ACTION_SCENE)

    assert "ctx.act" in diagnostic.message
    assert "missing_scene" in diagnostic.message
    assert diagnostic.location.file == "data/procedure.json"


def test_invalid_inspection_hotspot_is_rejected(tmp_path: Path) -> None:
    catalog = _catalog(
        tmp_path,
        {
            "evidence_inspections.json": {
                "inspections": [
                    {
                        "evidence_id": "paper_knife",
                        "image": "paper_knife_detail",
                        "hotspots": [
                            {
                                "id": "blade_edge",
                                "rect": [0.1, 0.1, 0.2, 0.2],
                                "scene": "content_start",
                            },
                            {
                                "id": "blood_stain",
                                "rect": [0.4, 0.4, 0.2, 0.2],
                                "scene": "missing_scene",
                                "unlocked_by": "ghost_hotspot",
                            },
                        ],
                    }
                ]
            }
        },
    )

    diagnostics = validate_cross_references(_document(VALID_STORY), catalog)

    assert DiagnosticCode.UNKNOWN_INSPECTION_HOTSPOT_SCENE in _codes(diagnostics)
    unlock = _diagnostic(diagnostics, DiagnosticCode.UNKNOWN_INSPECTION_UNLOCKED_BY)
    assert "ghost_hotspot" in unlock.message
    assert "blade_edge, blood_stain" in unlock.message


def test_cross_reference_errors_are_detected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
无名氏[calm]:
正文。
@evidence_add no_such_evidence
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))
    codes = _codes(diagnostics)

    assert DiagnosticCode.UNKNOWN_CHARACTER_REFERENCE in codes
    assert DiagnosticCode.UNKNOWN_EVIDENCE_REFERENCE in codes
    character = _diagnostic(diagnostics, DiagnosticCode.UNKNOWN_CHARACTER_REFERENCE)
    assert "无名氏" in character.message
    assert "辩护律师" in character.message


def test_present_rule_unknown_version_is_rejected(tmp_path: Path) -> None:
    document = _document(
        """#scene content_start
@testimony content_testimony
@penalty 20
@wrong -> content_wrong

## statement content_s01

辩护律师[normal]:
第一句。
@present crime_report made_up -> content_wrong

@endtestimony
@return

#scene content_wrong
@return
"""
    )

    diagnostics = validate_cross_references(document, _catalog(tmp_path))
    diagnostic = _diagnostic(diagnostics, DiagnosticCode.UNKNOWN_PRESENT_VERSION)

    assert "made_up" in diagnostic.message
    assert "verified" in diagnostic.message


def test_manifest_is_deterministic(tmp_path: Path) -> None:
    source_root = _story_root(tmp_path, VALID_STORY)
    data_root = _data_root(tmp_path)

    build_project(source_root, data_root, tmp_path / "first")
    build_project(source_root, data_root, tmp_path / "second")

    first = (tmp_path / "first" / "manifest.json").read_bytes()
    assert first == (tmp_path / "second" / "manifest.json").read_bytes()

    manifest = json.loads(first)
    assert set(manifest) == {
        "format_version",
        "chapters",
        "scenes",
        "testimonies",
        "characters",
        "expressions",
        "evidence",
        "evidence_versions",
        "locations",
        "backgrounds",
        "bgm",
        "sfx",
        "procedures",
        "inspections",
    }
    assert manifest["format_version"] == 1
    assert manifest["chapters"] == ["chapter_01"]
    assert manifest["scenes"] == ["content_start"]
    assert "protagonist" in manifest["characters"]
    assert {"normal", "thinking", "confident"}.issubset(set(manifest["expressions"]["protagonist"]))
    assert manifest["evidence_versions"]["crime_report"] == ["verified"]


def test_manifest_builder_is_path_independent(tmp_path: Path) -> None:
    source_root = _story_root(tmp_path, VALID_STORY)
    catalog = _catalog(tmp_path)

    parsed = StoryParser().parse_path(source_root / SOURCE_FILE, source_root)
    manifest = build_manifest(parsed.document, catalog)

    assert "res://" not in json.dumps(manifest)
    assert str(tmp_path) not in json.dumps(manifest)


def test_missing_convention_asset_warns_without_failing(tmp_path: Path) -> None:
    _story_root(tmp_path, VALID_STORY)
    _data_root(tmp_path)

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 0
    assert report.errors == []
    assert report.warnings
    assert {item.code for item in report.warnings} == {
        DiagnosticCode.MISSING_CONVENTION_ASSET
    }
    assert check_all.main(tmp_path) == 0


def test_strict_assets_promotes_warnings_to_errors(tmp_path: Path) -> None:
    _story_root(tmp_path, VALID_STORY)
    _data_root(tmp_path)

    report = check_all.run_check_all(tmp_path, strict_assets=True)

    assert report.warnings == []
    assert report.errors
    assert {item.code for item in report.errors} == {DiagnosticCode.MISSING_ASSET}
    assert check_all.main(tmp_path, strict_assets=True) == 1


def test_check_all_fails_on_invalid_fixture(tmp_path: Path) -> None:
    _story_root(
        tmp_path,
        """#scene content_start
@bg no_such_background
@bgm no_such_bgm
@sfx no_such_sfx
辩护律师[normal]:
正文。
@return
""",
    )
    _data_root(tmp_path)

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 1
    assert check_all.main(tmp_path) == 1
    assert {
        DiagnosticCode.UNKNOWN_BACKGROUND_REFERENCE,
        DiagnosticCode.UNKNOWN_BGM_REFERENCE,
        DiagnosticCode.UNKNOWN_SFX_REFERENCE,
    } <= {item.code for item in report.errors}


def test_check_all_passes_on_repository_content() -> None:
    report = check_all.run_check_all(PROJECT_ROOT)

    assert report.exit_code == 0, [item.render() for item in report.errors]


def _freshness_stage(report: check_all.CheckReport) -> check_all.CheckStage:
    return next(stage for stage in report.stages if stage.name == "build freshness")


def _built_fixture(tmp_path: Path) -> None:
    _story_root(tmp_path, VALID_STORY)
    _data_root(tmp_path)
    build_project(
        tmp_path / "story_src", tmp_path / "data", tmp_path / check_all.BUILD_DIR
    )


def test_check_all_accepts_a_build_matching_the_sources(tmp_path: Path) -> None:
    _built_fixture(tmp_path)

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 0, [item.render() for item in report.errors]
    assert _freshness_stage(report).summary == "in sync with story_src/ and data/"
    assert check_all.main(tmp_path) == 0


def test_check_all_detects_a_stale_build(tmp_path: Path) -> None:
    _built_fixture(tmp_path)
    story_file = tmp_path / "story_src" / SOURCE_FILE
    story_file.write_text(
        VALID_STORY.replace("正文。", "改过的正文，但没有重新 build。"),
        encoding="utf-8",
    )

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 1
    assert {item.code for item in report.errors} == {DiagnosticCode.STALE_STORY_BUILD}
    assert "story_build/story.json" in report.errors[0].render()
    assert "python -m tools.story_compiler build" in report.errors[0].render()
    assert check_all.main(tmp_path) == 1

    build_project(
        tmp_path / "story_src", tmp_path / "data", tmp_path / check_all.BUILD_DIR
    )
    assert check_all.run_check_all(tmp_path).exit_code == 0


def test_check_all_detects_a_missing_build_file(tmp_path: Path) -> None:
    _built_fixture(tmp_path)
    (tmp_path / check_all.BUILD_DIR / "manifest.json").unlink()

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 1
    assert {item.code for item in report.errors} == {DiagnosticCode.MISSING_STORY_BUILD}
    assert check_all.main(tmp_path) == 1


def test_check_all_can_skip_the_build_check(tmp_path: Path) -> None:
    _built_fixture(tmp_path)
    (tmp_path / check_all.BUILD_DIR / "story.json").write_text("{}", encoding="utf-8")

    report = check_all.run_check_all(tmp_path, check_build=False)

    assert report.exit_code == 0
    assert _freshness_stage(report).summary == "skipped: --skip-build-check"
    assert check_all.main(tmp_path, check_build=False) == 0


def test_check_all_skips_the_build_check_without_a_build(tmp_path: Path) -> None:
    _story_root(tmp_path, VALID_STORY)
    _data_root(tmp_path)

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 0
    assert _freshness_stage(report).summary.startswith("skipped: story_build/")


def test_content_only_change_needs_no_engine_change(tmp_path: Path) -> None:
    """Step 13.28: the real Chapter 1 content plus one new scene, one new
    background, one new expression and one new evidence item must validate and
    build without touching a single line of GDScript."""
    shutil.copytree(PROJECT_ROOT / "data", tmp_path / "data")
    shutil.copytree(PROJECT_ROOT / "story_src", tmp_path / "story_src")

    def patch_catalog(name: str, change) -> None:
        path = tmp_path / "data" / name
        data = json.loads(path.read_text(encoding="utf-8"))
        change(data)
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    patch_catalog(
        "backgrounds.json",
        lambda data: data["backgrounds"].append({"id": "teahouse_night"}),
    )
    patch_catalog(
        "expressions.json",
        lambda data: data["expressions"]["protagonist"].append("smug"),
    )
    patch_catalog(
        "evidence.json",
        lambda data: data["evidence"].append(
            {
                "id": "teahouse_receipt",
                "name": "茶楼收据",
                "description": "一张茶楼收据。",
                "presentable": True,
            }
        ),
    )
    (tmp_path / "story_src" / "demo" / "probe.md").write_text(
        "#scene probe_teahouse\n\n"
        "@bg teahouse_night\n"
        "@char protagonist center smug\n"
        "辩护律师[smug]:\n新场景只是数据与 Markdown。\n"
        "@evidence_add teahouse_receipt\n",
        encoding="utf-8",
    )

    report = check_all.run_check_all(tmp_path)

    assert report.exit_code == 0, [item.render() for item in report.errors]
    build_project(
        tmp_path / "story_src", tmp_path / "data", tmp_path / check_all.BUILD_DIR
    )
    story = json.loads(
        (tmp_path / check_all.BUILD_DIR / "story.json").read_text(encoding="utf-8")
    )
    manifest = json.loads(
        (tmp_path / check_all.BUILD_DIR / "manifest.json").read_text(encoding="utf-8")
    )
    assert "probe_teahouse" in story["scenes"]
    assert "teahouse_night" in manifest["backgrounds"]
    assert "smug" in manifest["expressions"]["protagonist"]
    assert "teahouse_receipt" in manifest["evidence"]


def test_format_version_defaults_to_one(tmp_path: Path) -> None:
    data_root = _data_root(tmp_path)
    (data_root / "characters.json").write_text(
        json.dumps({"characters": [{"id": "protagonist", "display_name": "辩护律师"}]}),
        encoding="utf-8",
    )

    result = load_content(data_root)

    assert result.catalog.characters[0].id == "protagonist"
    assert DiagnosticCode.UNSUPPORTED_FORMAT_VERSION not in _codes(
        list(result.diagnostics)
    )


def test_unsupported_format_version_is_rejected(tmp_path: Path) -> None:
    result = load_content(
        _data_root(
            tmp_path,
            {
                "characters.json": {
                    "format_version": 2,
                    "characters": [{"id": "protagonist", "display_name": "辩护律师"}],
                }
            },
        )
    )

    assert DiagnosticCode.UNSUPPORTED_FORMAT_VERSION in _codes(list(result.diagnostics))
    assert result.catalog.characters == ()
