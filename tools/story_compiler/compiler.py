from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .content_loader import load_content
from .diagnostics import (
    CompilationError,
    Diagnostic,
    DiagnosticCode,
    SourceLocation,
    errors_of,
)
from .manifest_builder import build_manifest
from .models import (
    AssetKind,
    StageNode,
    AssetNode,
    ConditionNode,
    DialogueNode,
    EndInvestigationNode,
    EndProcedureNode,
    EvidenceKind,
    EvidenceNode,
    FlagNode,
    FlowNode,
    StartInvestigationNode,
    StartProcedureNode,
    StartTestimonyNode,
    StoryDocument,
    TalkUnlockNode,
)
from .parser import StoryParser
from .registry import Registries, RegistryError, load_registries
from .validator import validate


@dataclass(frozen=True, slots=True)
class ProjectSummary:
    scene_count: int
    testimony_count: int


def validate_project(source_root: Path, data_root: Path) -> ProjectSummary:
    document, _ = _load_valid_project(source_root, data_root)
    return ProjectSummary(len(document.scenes), len(document.testimonies))


def build_project(source_root: Path, data_root: Path, output_root: Path) -> ProjectSummary:
    document, registries = _load_valid_project(source_root, data_root)
    content = load_content(data_root)
    content_errors = errors_of(content.diagnostics)
    if content_errors:
        raise CompilationError(content_errors)
    program = compile_document(document, registries)
    manifest = build_manifest(document, content.catalog)
    output_root.mkdir(parents=True, exist_ok=True)
    _write_json(output_root / "story.json", program)
    _write_json(output_root / "manifest.json", manifest)
    return ProjectSummary(len(document.scenes), len(document.testimonies))


def compile_document(
    document: StoryDocument,
    registries: Registries,
) -> dict[str, object]:
    scenes: dict[str, object] = {}
    for scene in document.scenes:
        instructions: list[dict[str, object]] = []
        for instruction in scene.instructions:
            compiled: dict[str, object] = {
                "op": _instruction_name(instruction),
                "source": instruction.source.to_json(),
            }
            if isinstance(instruction, DialogueNode):
                compiled.update(
                    {
                        "speaker": registries.characters.resolve(instruction.speaker_name) or "",
                        "expression": instruction.expression_id,
                        "text": instruction.text,
                    }
                )
            elif isinstance(instruction, FlowNode):
                if instruction.target_scene:
                    compiled["target"] = instruction.target_scene
            elif isinstance(instruction, FlagNode):
                compiled.update({"flag": instruction.flag_id, "value": instruction.value})
            elif isinstance(instruction, ConditionNode):
                compiled.update(
                    {
                        "flag": instruction.flag_id,
                        "equals": True,
                        "target": instruction.target_scene,
                    }
                )
            elif isinstance(instruction, AssetNode):
                key = {
                    AssetKind.BACKGROUND: "background",
                    AssetKind.BGM: "bgm",
                    AssetKind.SFX: "sfx",
                }[instruction.kind]
                compiled[key] = instruction.asset_id
            elif isinstance(instruction, StageNode):
                compiled.update(
                    {
                        "character": instruction.character_id,
                        "slot": instruction.slot,
                        "expression": instruction.expression_id,
                        "visible": instruction.visible,
                    }
                )
            elif isinstance(instruction, EvidenceNode):
                compiled["evidence"] = instruction.evidence_id
                if instruction.kind == EvidenceKind.UPDATE:
                    compiled["version"] = instruction.version
            elif isinstance(instruction, StartTestimonyNode):
                compiled["testimony"] = instruction.testimony_id
            elif isinstance(instruction, StartInvestigationNode):
                compiled["location"] = instruction.location_id
            elif isinstance(instruction, TalkUnlockNode):
                compiled["topic"] = instruction.topic_id
            elif isinstance(instruction, StartProcedureNode):
                compiled["context"] = instruction.context_id
            instructions.append(compiled)
        scenes[scene.id] = {
            "id": scene.id,
            "source": scene.source.to_json(),
            "instructions": instructions,
        }

    testimonies: dict[str, object] = {}
    for testimony in document.testimonies:
        statements: list[dict[str, object]] = []
        for statement in testimony.statements:
            statements.append(
                {
                    "id": statement.id,
                    "speaker": registries.characters.resolve(statement.speaker_name) or "",
                    "expression": statement.expression_id,
                    "text": statement.text,
                    "press_target": statement.press_target_scene,
                    "present_rules": [
                        {
                            "evidence": rule.evidence_id,
                            "required_version": rule.version,
                            "target": rule.target_scene,
                            "result": "correct",
                            "source": rule.source.to_json(),
                        }
                        for rule in statement.present_rules
                    ],
                    "source": statement.source.to_json(),
                }
            )
        testimonies[testimony.id] = {
            "id": testimony.id,
            "wrong_target": testimony.wrong_target_scene,
            "wrong_penalty": testimony.penalty,
            "statements": statements,
            "source": testimony.source.to_json(),
        }

    locations: dict[str, object] = {}
    for location in document.locations:
        locations[location.id] = {
            "id": location.id,
            "name": location.name,
            "background": location.background,
            "characters": [
                registries.characters.resolve(display_name) or ""
                for display_name, _ in location.characters
            ],
            "moves": [target for target, _ in location.moves],
            "present_reactions": {
                evidence_id: target_scene
                for evidence_id, target_scene, _ in location.present_reactions
            },
            "generic_present": location.generic_present,
            "hotspots": [
                {
                    "id": hotspot.id,
                    "rect": list(hotspot.rect) if hotspot.rect is not None else [],
                    "scene": hotspot.scene,
                    "source": hotspot.source.to_json(),
                }
                for hotspot in location.hotspots
            ],
            "topics": [
                {
                    "id": topic.id,
                    "title": topic.title,
                    "scene": topic.scene,
                    "locked": topic.locked,
                    "source": topic.source.to_json(),
                }
                for topic in location.topics
            ],
            "source": location.source.to_json(),
        }

    program: dict[str, object] = {
        "schema_version": 1,
        "entry_scene": document.scenes[0].id,
        "scenes": scenes,
        "testimonies": testimonies,
    }
    # Omit the key for stories without locations so existing Story IR stays
    # byte-identical (schema_version 1 programs keep their frozen key set).
    if locations:
        program["locations"] = locations
    return program


def parse_project(source_root: Path) -> tuple[StoryDocument, list[Diagnostic]]:
    """Parse every Markdown file under source_root; check-all reports this stage."""
    parser = StoryParser()
    document = StoryDocument()
    diagnostics: list[Diagnostic] = []
    source_paths = sorted(source_root.rglob("*.md")) if source_root.exists() else []
    if not source_paths:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.MALFORMED_COMMAND,
                SourceLocation("<project>", 1),
                "No Markdown story files were found.",
            )
        )
    for source_path in source_paths:
        result = parser.parse_path(source_path, source_root)
        document.extend(result.document)
        diagnostics.extend(result.diagnostics)

    if not document.scenes:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.MALFORMED_COMMAND,
                SourceLocation("<project>", 1),
                "The story source defines no scenes.",
            )
        )
    return document, diagnostics


def _load_valid_project(
    source_root: Path,
    data_root: Path,
) -> tuple[StoryDocument, Registries]:
    document, diagnostics = parse_project(source_root)

    try:
        registries = load_registries(data_root)
    except RegistryError as error:
        relative_path = (
            error.path.relative_to(data_root.parent).as_posix()
            if error.path.is_relative_to(data_root.parent)
            else error.path.as_posix()
        )
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_REGISTRY,
                SourceLocation(relative_path, 1),
                str(error),
            )
        )
        raise CompilationError(diagnostics) from error

    diagnostics.extend(validate(document, registries))
    if diagnostics:
        raise CompilationError(diagnostics)
    return document, registries


def _instruction_name(instruction: object) -> str:
    if isinstance(instruction, DialogueNode):
        return "say"
    if isinstance(instruction, (FlowNode, AssetNode, EvidenceNode)):
        return instruction.kind.value
    if isinstance(instruction, FlagNode):
        return "flag"
    if isinstance(instruction, ConditionNode):
        return "condition"
    if isinstance(instruction, StartTestimonyNode):
        return "start_testimony"
    if isinstance(instruction, StartInvestigationNode):
        return "investigation"
    if isinstance(instruction, EndInvestigationNode):
        return "investigation_end"
    if isinstance(instruction, TalkUnlockNode):
        return "talk_unlock"
    if isinstance(instruction, StartProcedureNode):
        return "procedure"
    if isinstance(instruction, EndProcedureNode):
        return "procedure_end"
    if isinstance(instruction, StageNode):
        return "stage"
    raise TypeError(f"Unsupported instruction: {type(instruction).__name__}")


def _write_json(path: Path, value: dict[str, object]) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
