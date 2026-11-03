"""Cross-reference validation between the story source and data/*.json catalogs.

The story validator (validator.py) reports the story's own view with LN1xxx
codes. This module reports the same content graph from the catalog side with
LN2xxx codes, anchored to the catalog entry that carries the problem, so
check-all can point at the exact JSON line.
"""

from __future__ import annotations

from collections.abc import Iterable

from .content_loader import ContentCatalog
from .diagnostics import Diagnostic, DiagnosticCode, SourceLocation
from .models import (
    AssetKind,
    AssetNode,
    DialogueNode,
    EvidenceNode,
    StartInvestigationNode,
    StoryDocument,
    TalkUnlockNode,
)


def validate_structure(document: StoryDocument) -> list[Diagnostic]:
    """Story-scope duplicate IDs the catalogs cannot see (LN2012-LN2014)."""
    diagnostics: list[Diagnostic] = []
    _report_duplicates(
        ((scene.id, scene.source) for scene in document.scenes),
        DiagnosticCode.DUPLICATE_SCENE_ID,
        "scene ID",
        diagnostics,
    )
    _report_duplicates(
        ((location.id, location.source) for location in document.locations),
        DiagnosticCode.DUPLICATE_LOCATION_ID,
        "location ID",
        diagnostics,
    )
    _report_duplicates(
        ((testimony.id, testimony.source) for testimony in document.testimonies),
        DiagnosticCode.DUPLICATE_TESTIMONY_ID,
        "testimony ID",
        diagnostics,
    )
    return diagnostics


def validate_cross_references(
    document: StoryDocument,
    catalog: ContentCatalog,
) -> list[Diagnostic]:
    diagnostics: list[Diagnostic] = []
    scene_ids = {scene.id for scene in document.scenes}
    location_ids = {location.id for location in document.locations}
    topic_ids = {
        topic.id for location in document.locations for topic in location.topics
    }
    _validate_catalog_entries(catalog, scene_ids, diagnostics)
    _validate_story_document(document, catalog, location_ids, topic_ids, diagnostics)
    _validate_locations(document, catalog, scene_ids, location_ids, topic_ids, diagnostics)
    return diagnostics


def _validate_catalog_entries(
    catalog: ContentCatalog,
    scene_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    """Catalog entries must not point at content that does not exist."""
    for expression in catalog.expressions:
        if catalog.character(expression.character_id) is None:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNKNOWN_EXPRESSION_CHARACTER,
                    expression.source,
                    f"Expression '{expression.id}' belongs to unknown character "
                    f"'{expression.character_id}'. Available characters: "
                    f"{_join(sorted(item.id for item in catalog.characters))}.",
                )
            )
    for character in catalog.characters:
        if (
            character.default_expression
            and not catalog.has_expression(character.id, character.default_expression)
        ):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNKNOWN_EXPRESSION_REFERENCE,
                    character.source,
                    f"Unknown default expression '{character.default_expression}' for "
                    f"character '{character.id}'. Available: "
                    f"{_join(catalog.expressions_of(character.id))}.",
                )
            )
    for context in catalog.procedures:
        for action in context.actions:
            source = action.source or SourceLocation("data/procedure.json", 1)
            label = f"procedure action '{context.id}.{action.id}'"
            if action.scene and action.scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_PROCEDURE_ACTION_SCENE,
                        source,
                        f"Unknown scene for {label}: {action.scene}. "
                        "Expected a #scene defined in story_src.",
                    )
                )
            if action.required_evidence and not catalog.has_evidence(
                action.required_evidence
            ):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_PROCEDURE_REQUIRED_EVIDENCE,
                        source,
                        f"Unknown required evidence for {label}: "
                        f"{action.required_evidence}. Available: "
                        f"{_join(sorted(item.id for item in catalog.evidence))}.",
                    )
                )
    _validate_inspections(catalog, scene_ids, diagnostics)


def _validate_inspections(
    catalog: ContentCatalog,
    scene_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    for inspection in catalog.inspections:
        source = inspection.source or SourceLocation("data/evidence_inspections.json", 1)
        if not catalog.has_evidence(inspection.evidence_id):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNKNOWN_INSPECTION_EVIDENCE_ID,
                    source,
                    f"Inspection targets unknown evidence '{inspection.evidence_id}'. "
                    f"Available: {_join(sorted(item.id for item in catalog.evidence))}.",
                )
            )
        hotspot_ids = {hotspot.id for hotspot in inspection.hotspots}
        for hotspot in inspection.hotspots:
            hotspot_source = hotspot.source or source
            if hotspot.scene and hotspot.scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INSPECTION_HOTSPOT_SCENE,
                        hotspot_source,
                        f"Unknown scene for inspection hotspot '{hotspot.id}' of "
                        f"'{inspection.evidence_id}': {hotspot.scene}. "
                        "Expected a #scene defined in story_src.",
                    )
                )
            if hotspot.unlocked_by and hotspot.unlocked_by not in hotspot_ids - {hotspot.id}:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INSPECTION_UNLOCKED_BY,
                        hotspot_source,
                        f"Hotspot '{hotspot.id}' of '{inspection.evidence_id}' is "
                        f"unlocked by unknown hotspot '{hotspot.unlocked_by}'. "
                        f"Available: {_join(sorted(hotspot_ids))}.",
                    )
                )


def _validate_story_document(
    document: StoryDocument,
    catalog: ContentCatalog,
    location_ids: set[str],
    topic_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    for scene in document.scenes:
        for instruction in scene.instructions:
            if isinstance(instruction, DialogueNode):
                _validate_dialogue(
                    instruction.speaker_name,
                    instruction.expression_id,
                    instruction.source,
                    catalog,
                    diagnostics,
                )
            elif isinstance(instruction, AssetNode):
                _validate_asset(instruction, catalog, diagnostics)
            elif isinstance(instruction, EvidenceNode):
                _validate_evidence(
                    instruction.evidence_id, instruction.source, catalog, diagnostics
                )
            elif isinstance(instruction, StartInvestigationNode):
                _validate_location_ref(
                    instruction.location_id, instruction.source, location_ids, diagnostics
                )
            elif isinstance(instruction, TalkUnlockNode):
                _validate_topic_ref(
                    instruction.topic_id, instruction.source, topic_ids, diagnostics
                )

    for testimony in document.testimonies:
        for statement in testimony.statements:
            if statement.speaker_name:
                _validate_dialogue(
                    statement.speaker_name,
                    statement.expression_id,
                    statement.dialogue_source or statement.source,
                    catalog,
                    diagnostics,
                )
            for rule in statement.present_rules:
                _validate_evidence(rule.evidence_id, rule.source, catalog, diagnostics)
                if rule.version and not catalog.has_evidence_version(
                    rule.evidence_id, rule.version
                ):
                    definition = catalog.evidence_def(rule.evidence_id)
                    available = (
                        _join(sorted(definition.versions))
                        if definition is not None
                        else "<unknown evidence>"
                    )
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_PRESENT_VERSION,
                            rule.source,
                            f"Unknown version '{rule.version}' for evidence "
                            f"'{rule.evidence_id}'. Available: {available}.",
                        )
                    )


def _validate_locations(
    document: StoryDocument,
    catalog: ContentCatalog,
    scene_ids: set[str],
    location_ids: set[str],
    topic_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    for location in document.locations:
        if location.background:
            _validate_asset(
                AssetNode(
                    AssetKind.BACKGROUND,
                    location.background,
                    location.background_source or location.source,
                ),
                catalog,
                diagnostics,
            )
        for display_name, source in location.characters:
            if catalog.character_by_name(display_name) is None:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INVESTIGATION_CHARACTER_REF,
                        source,
                        f"Unknown character '{display_name}' in location "
                        f"'{location.id}'. Expected a display_name from "
                        f"data/characters.json. Available: "
                        f"{_join(catalog.character_names())}.",
                    )
                )
        for target_location, source in location.moves:
            if target_location not in location_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_MOVE_TARGET,
                        source,
                        f"Unknown move target '{target_location}' in location "
                        f"'{location.id}'. Defined locations: {_join(sorted(location_ids))}.",
                    )
                )
        for evidence_id, target_scene, source in location.present_reactions:
            _validate_evidence(evidence_id, source, catalog, diagnostics)
            _validate_scene_ref(
                target_scene,
                source,
                scene_ids,
                f"present reaction in '{location.id}'",
                diagnostics,
            )
        if location.generic_present:
            _validate_scene_ref(
                location.generic_present,
                location.generic_present_source or location.source,
                scene_ids,
                f"generic present in '{location.id}'",
                diagnostics,
            )
        for hotspot in location.hotspots:
            _validate_scene_ref(
                hotspot.scene,
                hotspot.scene_source or hotspot.source,
                scene_ids,
                f"hotspot '{hotspot.id}' in '{location.id}'",
                diagnostics,
            )
        for topic in location.topics:
            _validate_scene_ref(
                topic.scene,
                topic.scene_source or topic.source,
                scene_ids,
                f"topic '{topic.id}' in '{location.id}'",
                diagnostics,
            )


def _validate_dialogue(
    speaker_name: str,
    expression_id: str,
    source: SourceLocation,
    catalog: ContentCatalog,
    diagnostics: list[Diagnostic],
) -> None:
    character = catalog.character_by_name(speaker_name)
    if character is None:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNKNOWN_CHARACTER_REFERENCE,
                source,
                f"Unknown character '{speaker_name}'. Expected a display_name from "
                f"data/characters.json. Available: {_join(catalog.character_names())}.",
            )
        )
        return
    if not catalog.has_expression(character.id, expression_id):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNKNOWN_EXPRESSION_REFERENCE,
                source,
                f"Unknown expression '{expression_id}' for character '{character.id}'. "
                f"Available: {_join(catalog.expressions_of(character.id))}.",
            )
        )


def _validate_asset(
    instruction: AssetNode,
    catalog: ContentCatalog,
    diagnostics: list[Diagnostic],
) -> None:
    if instruction.kind == AssetKind.BACKGROUND:
        if catalog.has_background(instruction.asset_id):
            return
        code = DiagnosticCode.UNKNOWN_BACKGROUND_REFERENCE
        available = _join(sorted(item.id for item in catalog.backgrounds))
    elif instruction.kind == AssetKind.BGM:
        if catalog.has_bgm(instruction.asset_id):
            return
        code = DiagnosticCode.UNKNOWN_BGM_REFERENCE
        available = _join(sorted(item.id for item in catalog.bgm))
    else:
        if catalog.has_sfx(instruction.asset_id):
            return
        code = DiagnosticCode.UNKNOWN_SFX_REFERENCE
        available = _join(sorted(item.id for item in catalog.sfx))
    diagnostics.append(
        Diagnostic(
            code,
            instruction.source,
            f"Unknown {instruction.kind.value} ID: {instruction.asset_id}. "
            f"Available: {available}.",
        )
    )


def _validate_evidence(
    evidence_id: str,
    source: SourceLocation,
    catalog: ContentCatalog,
    diagnostics: list[Diagnostic],
) -> None:
    if catalog.has_evidence(evidence_id):
        return
    diagnostics.append(
        Diagnostic(
            DiagnosticCode.UNKNOWN_EVIDENCE_REFERENCE,
            source,
            f"Unknown evidence ID '{evidence_id}'. Available: "
            f"{_join(sorted(item.id for item in catalog.evidence))}.",
        )
    )


def _validate_location_ref(
    location_id: str,
    source: SourceLocation,
    location_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    if location_id in location_ids:
        return
    diagnostics.append(
        Diagnostic(
            DiagnosticCode.UNKNOWN_LOCATION_REFERENCE,
            source,
            f"Unknown location ID '{location_id}'. Defined locations: "
            f"{_join(sorted(location_ids))}.",
        )
    )


def _validate_topic_ref(
    topic_id: str,
    source: SourceLocation,
    topic_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    if topic_id in topic_ids:
        return
    diagnostics.append(
        Diagnostic(
            DiagnosticCode.UNKNOWN_TALK_TOPIC_REF,
            source,
            f"Unknown talk topic ID '{topic_id}'. Defined topics: "
            f"{_join(sorted(topic_ids))}.",
        )
    )


def _validate_scene_ref(
    scene_id: str,
    source: SourceLocation,
    scene_ids: set[str],
    label: str,
    diagnostics: list[Diagnostic],
) -> None:
    if scene_id in scene_ids:
        return
    diagnostics.append(
        Diagnostic(
            DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE_REF,
            source,
            f"Unknown scene '{scene_id}' for {label}. "
            "Expected a #scene defined in story_src.",
        )
    )


def _report_duplicates(
    entries: Iterable[tuple[str, SourceLocation]],
    code: DiagnosticCode,
    label: str,
    diagnostics: list[Diagnostic],
) -> None:
    seen: set[str] = set()
    for item_id, source in entries:
        if item_id in seen:
            diagnostics.append(
                Diagnostic(
                    code,
                    source,
                    f"Duplicate {label}: {item_id}. Expected: unique IDs.",
                )
            )
        seen.add(item_id)


def _join(values: Iterable[str]) -> str:
    items = list(values)
    return ", ".join(items) if items else "<none>"
