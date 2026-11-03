"""`check-all`: the one content validation entry point.

Runs the whole content pipeline in order and reports every stage:

    story parse -> story semantic validation -> content catalog validation
    -> cross-reference validation -> asset existence validation
    -> IR build validation (compile in memory, no writes)
    -> build freshness (does story_build/ still match the sources?)
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from . import content_validator
from .asset_validator import validate_assets
from .compiler import compile_document, parse_project
from .content_loader import ContentCatalog, load_content
from .diagnostics import (
    CompilationError,
    Diagnostic,
    DiagnosticCode,
    SourceLocation,
    errors_of,
    warnings_of,
)
from .manifest_builder import build_manifest
from .models import StoryDocument
from .registry import Registries, RegistryError, load_registries
from .validator import validate

BUILD_DIR: str = "story_build"
BUILD_FILES: tuple[str, ...] = ("story.json", "manifest.json")
REBUILD_HINT: str = "Run: python -m tools.story_compiler build"


@dataclass(frozen=True, slots=True)
class CheckStage:
    name: str
    summary: str
    diagnostics: tuple[Diagnostic, ...]


@dataclass(frozen=True, slots=True)
class CheckReport:
    stages: tuple[CheckStage, ...]
    strict_assets: bool = False

    @property
    def diagnostics(self) -> tuple[Diagnostic, ...]:
        return tuple(item for stage in self.stages for item in stage.diagnostics)

    @property
    def errors(self) -> list[Diagnostic]:
        return errors_of(self.diagnostics)

    @property
    def warnings(self) -> list[Diagnostic]:
        return warnings_of(self.diagnostics)

    @property
    def exit_code(self) -> int:
        return 1 if self.errors else 0


def run_check_all(
    project_root: Path,
    *,
    strict_assets: bool = False,
    check_build: bool = True,
) -> CheckReport:
    data_root = project_root / "data"
    stages: list[CheckStage] = []

    document, parse_diagnostics = parse_project(project_root / "story_src")
    stages.append(
        CheckStage(
            "story parse",
            f"{_plural(len(document.scenes), 'scene')}, "
            f"{_plural(len(document.testimonies), 'testimony', 'testimonies')}, "
            f"{_plural(len(document.locations), 'location')}",
            tuple(parse_diagnostics),
        )
    )

    registries: Registries | None = None
    semantic_diagnostics: list[Diagnostic] = []
    try:
        registries = load_registries(data_root)
    except RegistryError as error:
        semantic_diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_REGISTRY,
                SourceLocation(display_path(error.path, project_root), 1),
                str(error),
            )
        )
    else:
        semantic_diagnostics.extend(validate(document, registries))
    stages.append(
        CheckStage(
            "story semantic validation",
            f"{len(semantic_diagnostics)} diagnostic(s)",
            tuple(semantic_diagnostics),
        )
    )

    content = load_content(data_root)
    catalog = content.catalog
    structure_diagnostics = [
        *content.diagnostics,
        *content_validator.validate_structure(document),
    ]
    stages.append(
        CheckStage(
            "content validation",
            f"{_plural(len(catalog.characters), 'character')}, "
            f"{_plural(len(catalog.expressions), 'expression')}, "
            f"{len(catalog.evidence)} evidence, "
            f"{_plural(len(catalog.backgrounds), 'background')}, "
            f"{len(catalog.bgm)} bgm, {len(catalog.sfx)} sfx, "
            f"{_plural(len(catalog.procedures), 'procedure')}, "
            f"{_plural(len(catalog.inspections), 'inspection')}",
            tuple(structure_diagnostics),
        )
    )

    reference_diagnostics = content_validator.validate_cross_references(document, catalog)
    stages.append(
        CheckStage(
            "cross-reference validation",
            f"{len(reference_diagnostics)} diagnostic(s)",
            tuple(reference_diagnostics),
        )
    )

    asset_diagnostics = validate_assets(project_root, catalog, strict=strict_assets)
    stages.append(
        CheckStage(
            "asset existence validation",
            f"{len(asset_diagnostics)} diagnostic(s)"
            + (" (--strict-assets)" if strict_assets else ""),
            tuple(asset_diagnostics),
        )
    )

    build_stage, program = _build_stage(document, registries)
    stages.append(build_stage)
    stages.append(
        _freshness_stage(
            project_root,
            program,
            document,
            content.catalog,
            check_build=check_build,
        )
    )
    return CheckReport(tuple(stages), strict_assets)


def _build_stage(
    document: StoryDocument, registries: Registries | None
) -> tuple[CheckStage, dict[str, object] | None]:
    name = "IR build validation"
    if registries is None:
        return CheckStage(name, "skipped: content catalogs are unusable", ()), None
    if not document.scenes:
        return CheckStage(name, "skipped: the story source defines no scenes", ()), None
    try:
        program = compile_document(document, registries)
    except CompilationError as error:
        return CheckStage(name, "failed", tuple(error.diagnostics)), None
    except Exception as error:  # pragma: no cover - internal compiler failure
        return (
            CheckStage(
                name,
                "failed",
                (
                    Diagnostic(
                        DiagnosticCode.MALFORMED_COMMAND,
                        SourceLocation("<project>", 1),
                        f"IR build failed: {error!r}.",
                    ),
                ),
            ),
            None,
        )
    scenes = program.get("scenes")
    scene_map = scenes if isinstance(scenes, dict) else {}
    instruction_count = sum(
        len(scene.get("instructions", []))
        for scene in scene_map.values()
        if isinstance(scene, dict)
    )
    return (
        CheckStage(
            name,
            f"compiled in memory: {_plural(len(scene_map), 'scene')}, "
            f"{_plural(instruction_count, 'instruction')}",
            (),
        ),
        program,
    )


def _freshness_stage(
    project_root: Path,
    program: dict[str, object] | None,
    document: StoryDocument,
    catalog: ContentCatalog,
    *,
    check_build: bool,
) -> CheckStage:
    """Compares the committed build with what the current sources compile to.

    The runtime only ever reads `story_build/`, so an out-of-date build means the
    game silently plays old content while the sources look fine. A project that
    ships no build at all is not an error: building is a separate step, and
    `build_story.sh` validates before it writes.
    """
    name = "build freshness"
    build_root = project_root / BUILD_DIR
    if not check_build:
        return CheckStage(name, "skipped: --skip-build-check", ())
    if not build_root.is_dir():
        return CheckStage(name, f"skipped: {BUILD_DIR}/ does not exist yet", ())
    if program is None:
        return CheckStage(name, "skipped: the sources do not compile", ())

    expected: dict[str, object] = {
        "story.json": program,
        "manifest.json": build_manifest(document, catalog),
    }
    diagnostics: list[Diagnostic] = []
    for file_name in BUILD_FILES:
        path = build_root / file_name
        location = SourceLocation(f"{BUILD_DIR}/{file_name}", 1)
        if not path.is_file():
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.MISSING_STORY_BUILD,
                    location,
                    f"{BUILD_DIR}/{file_name} is missing. {REBUILD_HINT}",
                )
            )
            continue
        try:
            actual = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.STALE_STORY_BUILD,
                    location,
                    f"{BUILD_DIR}/{file_name} cannot be read: {error}. {REBUILD_HINT}",
                )
            )
            continue
        if actual != expected[file_name]:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.STALE_STORY_BUILD,
                    location,
                    f"{BUILD_DIR}/{file_name} does not match the sources "
                    f"({_difference(expected[file_name], actual)}). {REBUILD_HINT}",
                )
            )

    summary = (
        "in sync with story_src/ and data/"
        if not diagnostics
        else _plural(len(diagnostics), "out-of-date file")
    )
    return CheckStage(name, summary, tuple(diagnostics))


def _difference(expected: object, actual: object) -> str:
    """Names the parts that differ, so the message is actionable."""
    if isinstance(expected, dict) and isinstance(actual, dict):
        keys = sorted(
            key
            for key in set(expected) | set(actual)
            if expected.get(key) != actual.get(key)
        )
        if keys:
            return "differs in " + ", ".join(keys)
    return "content differs"


def display_path(path: Path, project_root: Path) -> str:
    if path.is_relative_to(project_root):
        return path.relative_to(project_root).as_posix()
    return path.as_posix()


def _plural(count: int, singular: str, plural: str = "") -> str:
    if count == 1:
        return f"{count} {singular}"
    return f"{count} {plural or singular + 's'}"


def print_report(report: CheckReport) -> None:
    total = len(report.stages)
    for index, stage in enumerate(report.stages, 1):
        errors = errors_of(stage.diagnostics)
        status = "OK" if not errors else f"FAILED ({len(errors)} error(s))"
        print(f"[{index}/{total}] {stage.name}: {status} - {stage.summary}")
        for diagnostic in stage.diagnostics:
            print(diagnostic.render())
    print(
        f"check-all: {len(report.errors)} error(s), {len(report.warnings)} warning(s)"
    )
    if report.warnings and not report.strict_assets:
        print(
            "check-all: warnings are placeholder-art notices; "
            "--strict-assets turns them into errors."
        )


def main(
    project_root: Path,
    *,
    strict_assets: bool = False,
    check_build: bool = True,
) -> int:
    report = run_check_all(project_root, strict_assets=strict_assets, check_build=check_build)
    print_report(report)
    return report.exit_code
