from __future__ import annotations

import re

from .diagnostics import Diagnostic, DiagnosticCode, SourceLocation
from .models import (
    StageNode,
    AssetKind,
    AssetNode,
    ConditionNode,
    DialogueNode,
    EvidenceNode,
    FlowKind,
    FlowNode,
    StartInvestigationNode,
    StartProcedureNode,
    StartTestimonyNode,
    StatementNode,
    StoryDocument,
    TalkUnlockNode,
)
from .registry import (
    EvidenceInspection,
    InspectionRegistry,
    ProcedureRegistry,
    Registries,
)

STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
RECT_EPSILON = 1e-6
PROCEDURE_RESULTS = frozenset({"correct", "wrong", "special"})


def validate(document: StoryDocument, registries: Registries) -> list[Diagnostic]:
    diagnostics: list[Diagnostic] = []
    scene_ids: set[str] = set()
    testimony_ids: set[str] = set()
    statement_ids: set[str] = set()
    location_ids: set[str] = set()
    topic_ids: set[str] = set()

    if not document.scenes and not document.locations:
        return diagnostics

    for scene in document.scenes:
        if not STABLE_ID_RE.fullmatch(scene.id):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_SCENE_ID,
                    scene.source,
                    f"Invalid scene ID: {scene.id}",
                )
            )
        if scene.id in scene_ids:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.DUPLICATE_SCENE,
                    scene.source,
                    f"Duplicate scene ID: {scene.id}",
                )
            )
        scene_ids.add(scene.id)

    for testimony in document.testimonies:
        if not STABLE_ID_RE.fullmatch(testimony.id):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_TESTIMONY_ID,
                    testimony.source,
                    f"Invalid testimony ID: {testimony.id}",
                )
            )
        if testimony.id in testimony_ids:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.DUPLICATE_TESTIMONY,
                    testimony.source,
                    f"Duplicate testimony ID: {testimony.id}",
                )
            )
        testimony_ids.add(testimony.id)

    _validate_locations(document, scene_ids, location_ids, topic_ids, registries, diagnostics)

    for scene in document.scenes:
        for instruction in scene.instructions:
            if isinstance(instruction, DialogueNode):
                _validate_dialogue(instruction, registries, diagnostics)
            elif isinstance(instruction, FlowNode) and instruction.kind != FlowKind.RETURN:
                if instruction.target_scene not in scene_ids:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_SCENE,
                            instruction.source,
                            f"Unknown {instruction.kind.value} target: {instruction.target_scene}",
                        )
                    )
            elif isinstance(instruction, ConditionNode):
                if instruction.target_scene not in scene_ids:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_SCENE,
                            instruction.source,
                            f"Unknown condition target: {instruction.target_scene}",
                        )
                    )
            elif isinstance(instruction, AssetNode):
                _validate_asset(instruction, registries, diagnostics)
            elif isinstance(instruction, StageNode):
                _validate_stage(instruction, registries, diagnostics)
            elif isinstance(instruction, EvidenceNode):
                if not registries.evidence.contains(instruction.evidence_id):
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_EVIDENCE,
                            instruction.source,
                            f"Unknown evidence ID: {instruction.evidence_id}",
                        )
                    )
            elif isinstance(instruction, StartTestimonyNode):
                if instruction.testimony_id not in testimony_ids:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.INVALID_TESTIMONY_ID,
                            instruction.source,
                            f"Unknown testimony ID: {instruction.testimony_id}",
                        )
                    )
            elif isinstance(instruction, StartInvestigationNode):
                if instruction.location_id not in location_ids:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_LOCATION,
                            instruction.source,
                            f"Unknown location ID: {instruction.location_id}",
                        )
                    )
            elif isinstance(instruction, TalkUnlockNode):
                if instruction.topic_id not in topic_ids:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_TALK_TOPIC,
                            instruction.source,
                            f"Unknown talk topic ID: {instruction.topic_id}",
                        )
                    )
            elif isinstance(instruction, StartProcedureNode):
                if not registries.procedure.contains(instruction.context_id):
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_PROCEDURE_CONTEXT,
                            instruction.source,
                            f"Unknown procedure context ID: {instruction.context_id}",
                        )
                    )

    for testimony in document.testimonies:
        if not testimony.statements:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.EMPTY_TESTIMONY,
                    testimony.source,
                    f"Testimony '{testimony.id}' must contain at least one statement.",
                )
            )
        if testimony.penalty is None or not 0 <= testimony.penalty <= 100:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_PENALTY,
                    testimony.penalty_source or testimony.source,
                    "Penalty must be an integer from 0 through 100.",
                )
            )
        if not testimony.wrong_target_scene or testimony.wrong_target_scene not in scene_ids:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_WRONG_TARGET,
                    testimony.wrong_source or testimony.source,
                    f"Invalid wrong target: {testimony.wrong_target_scene or '<missing>'}",
                )
            )

        for statement in testimony.statements:
            if not STABLE_ID_RE.fullmatch(statement.id):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_STATEMENT_ID,
                        statement.source,
                        f"Invalid statement ID: {statement.id}",
                    )
                )
            if statement.id in statement_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.DUPLICATE_STATEMENT,
                        statement.source,
                        f"Duplicate statement ID: {statement.id}",
                    )
                )
            statement_ids.add(statement.id)

            if not statement.text:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        statement.source,
                        f"Statement '{statement.id}' requires dialogue.",
                    )
                )
            else:
                _validate_dialogue(statement, registries, diagnostics)

            if (
                statement.press_target_scene
                and statement.press_target_scene not in scene_ids
            ):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_PRESS_TARGET,
                        statement.press_source or statement.source,
                        f"Invalid press target: {statement.press_target_scene}",
                    )
                )

            presented_evidence: set[str] = set()
            for rule in statement.present_rules:
                if rule.evidence_id in presented_evidence:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.DUPLICATE_PRESENT_RULE,
                            rule.source,
                            f"Duplicate present rule for evidence: {rule.evidence_id}",
                        )
                    )
                presented_evidence.add(rule.evidence_id)
                if not registries.evidence.contains(rule.evidence_id):
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_EVIDENCE,
                            rule.source,
                            f"Unknown evidence ID: {rule.evidence_id}",
                        )
                    )
                elif rule.version and not registries.evidence.contains_version(
                    rule.evidence_id, rule.version
                ):
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.UNKNOWN_EVIDENCE_VERSION,
                            rule.source,
                            f"Unknown version '{rule.version}' for evidence "
                            f"'{rule.evidence_id}'.",
                        )
                    )
                if rule.target_scene not in scene_ids:
                    diagnostics.append(
                        Diagnostic(
                            DiagnosticCode.INVALID_PRESENT_TARGET,
                            rule.source,
                            f"Invalid present target: {rule.target_scene}",
                        )
                    )

    _validate_procedure_data(registries, scene_ids, diagnostics)
    _validate_inspection_data(registries, scene_ids, diagnostics)

    return diagnostics


def _validate_locations(
    document: StoryDocument,
    scene_ids: set[str],
    location_ids: set[str],
    topic_ids: set[str],
    registries: Registries,
    diagnostics: list[Diagnostic],
) -> None:
    for location in document.locations:
        if not STABLE_ID_RE.fullmatch(location.id):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_LOCATION_ID,
                    location.source,
                    f"Invalid location ID: {location.id}",
                )
            )
        if location.id in location_ids:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.DUPLICATE_LOCATION,
                    location.source,
                    f"Duplicate location ID: {location.id}",
                )
            )
        location_ids.add(location.id)

    # A second pass: @move may point at a location that is authored later.
    for location in document.locations:
        if not location.background:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.LOCATION_MISSING_BACKGROUND,
                    location.source,
                    f"Location '{location.id}' requires @bg.",
                )
            )

        for display_name, source in location.characters:
            if registries.characters.resolve(display_name) is None:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_LOCATION_CHARACTER,
                        source,
                        f"Unknown character display name: {display_name}",
                    )
                )

        for target_location, source in location.moves:
            if target_location not in location_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_LOCATION,
                        source,
                        f"Unknown move target: {target_location}",
                    )
                )

        presented_evidence: set[str] = set()
        for evidence_id, target_scene, source in location.present_reactions:
            if evidence_id in presented_evidence:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.DUPLICATE_PRESENT_RULE,
                        source,
                        f"Duplicate present rule for evidence: {evidence_id}",
                    )
                )
            presented_evidence.add(evidence_id)
            if not registries.evidence.contains(evidence_id):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_EVIDENCE,
                        source,
                        f"Unknown evidence ID: {evidence_id}",
                    )
                )
            if target_scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE,
                        source,
                        f"Unknown present reaction scene: {target_scene}",
                    )
                )

        if location.generic_present and location.generic_present not in scene_ids:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE,
                    location.generic_present_source or location.source,
                    f"Unknown generic present scene: {location.generic_present}",
                )
            )

        hotspot_ids: set[str] = set()
        for hotspot in location.hotspots:
            if not STABLE_ID_RE.fullmatch(hotspot.id):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_LOCATION_CHILD_ID,
                        hotspot.source,
                        f"Invalid hotspot ID: {hotspot.id}",
                    )
                )
            if hotspot.id in hotspot_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.DUPLICATE_HOTSPOT,
                        hotspot.source,
                        f"Duplicate hotspot ID in location '{location.id}': {hotspot.id}",
                    )
                )
            hotspot_ids.add(hotspot.id)

            if hotspot.rect is None or not _valid_rect(hotspot.rect):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_HOTSPOT_RECT,
                        hotspot.rect_source or hotspot.source,
                        f"Hotspot '{hotspot.id}' requires a rect inside the unit square.",
                    )
                )
            if not hotspot.scene or hotspot.scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE,
                        hotspot.scene_source or hotspot.source,
                        f"Unknown hotspot scene: {hotspot.scene or '<missing>'}",
                    )
                )

        location_topic_ids: set[str] = set()
        for topic in location.topics:
            if not STABLE_ID_RE.fullmatch(topic.id):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_LOCATION_CHILD_ID,
                        topic.source,
                        f"Invalid topic ID: {topic.id}",
                    )
                )
            if topic.id in location_topic_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.DUPLICATE_TOPIC,
                        topic.source,
                        f"Duplicate topic ID in location '{location.id}': {topic.id}",
                    )
                )
            location_topic_ids.add(topic.id)
            topic_ids.add(topic.id)

            if not topic.title:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        topic.title_source or topic.source,
                        f"Topic '{topic.id}' requires @title.",
                    )
                )
            if not topic.scene or topic.scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INVESTIGATION_SCENE,
                        topic.scene_source or topic.source,
                        f"Unknown topic scene: {topic.scene or '<missing>'}",
                    )
                )


def _valid_rect(rect: tuple[float, float, float, float]) -> bool:
    x, y, width, height = rect
    return (
        width > 0
        and height > 0
        and -RECT_EPSILON <= x <= 1 + RECT_EPSILON
        and -RECT_EPSILON <= y <= 1 + RECT_EPSILON
        and x + width <= 1 + RECT_EPSILON
        and y + height <= 1 + RECT_EPSILON
    )


def _validate_dialogue(
    dialogue: DialogueNode | StatementNode,
    registries: Registries,
    diagnostics: list[Diagnostic],
) -> None:
    source = (
        dialogue.dialogue_source
        if isinstance(dialogue, StatementNode) and dialogue.dialogue_source is not None
        else dialogue.source
    )
    character_id = registries.characters.resolve(dialogue.speaker_name)
    if character_id is None:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNKNOWN_CHARACTER,
                source,
                f"Unknown character display name: {dialogue.speaker_name}",
            )
        )
    elif not registries.expressions.contains(character_id, dialogue.expression_id):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNKNOWN_EXPRESSION,
                source,
                f"Unknown expression '{dialogue.expression_id}' for character '{character_id}'.",
            )
        )


def _validate_asset(
    instruction: AssetNode,
    registries: Registries,
    diagnostics: list[Diagnostic],
) -> None:
    if instruction.kind == AssetKind.BACKGROUND:
        registry = registries.backgrounds
        code = DiagnosticCode.UNKNOWN_BACKGROUND
    elif instruction.kind == AssetKind.BGM:
        registry = registries.bgm
        code = DiagnosticCode.UNKNOWN_BGM
    else:
        registry = registries.sfx
        code = DiagnosticCode.UNKNOWN_SFX
    if not registry.contains(instruction.asset_id):
        diagnostics.append(
            Diagnostic(code, instruction.source, f"Unknown {instruction.kind.value} ID: {instruction.asset_id}")
        )


def _validate_stage(
    instruction: StageNode,
    registries: Registries,
    diagnostics: list[Diagnostic],
) -> None:
    if instruction.character_id != "all" and not registries.characters.contains(
        instruction.character_id
    ):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNKNOWN_CHARACTER,
                instruction.source,
                f"Unknown character ID: {instruction.character_id}",
            )
        )
        return
    if instruction.expression_id and not registries.expressions.contains(
        instruction.character_id, instruction.expression_id
    ):
        available = sorted(registries.expressions.ids_by_character.get(instruction.character_id, ()))
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNKNOWN_EXPRESSION,
                instruction.source,
                f"Unknown expression: {instruction.expression_id} "
                f"(character {instruction.character_id}, available: {', '.join(available)})",
            )
        )


def _validate_procedure_data(
    registries: Registries,
    scene_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    """Validate data/procedure.json; the registry keeps the raw catalog shape."""
    registry: ProcedureRegistry = registries.procedure
    source = SourceLocation(registry.source_file, 1)
    context_ids: set[str] = set()

    for context in registry.contexts:
        if not STABLE_ID_RE.fullmatch(context.id):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_PROCEDURE_ID,
                    source,
                    f"Invalid procedure context ID: {context.id}",
                )
            )
        if context.id in context_ids:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.DUPLICATE_PROCEDURE_CONTEXT,
                    source,
                    f"Duplicate procedure context ID: {context.id}",
                )
            )
        context_ids.add(context.id)

        if not context.actions:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.EMPTY_PROCEDURE_CONTEXT,
                    source,
                    f"Procedure context '{context.id}' requires at least one action.",
                )
            )

        action_ids: set[str] = set()
        for action in context.actions:
            if not STABLE_ID_RE.fullmatch(action.id):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_PROCEDURE_ID,
                        source,
                        f"Invalid procedure action ID: {context.id}.{action.id}",
                    )
                )
            if action.id in action_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.DUPLICATE_PROCEDURE_ACTION,
                        source,
                        f"Duplicate procedure action ID in '{context.id}': {action.id}",
                    )
                )
            action_ids.add(action.id)

            if action.result not in PROCEDURE_RESULTS:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_PROCEDURE_RESULT,
                        source,
                        f"Procedure action '{context.id}.{action.id}' has invalid result: "
                        f"{action.result or '<missing>'}",
                    )
                )
            if action.scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_PROCEDURE_SCENE,
                        source,
                        f"Unknown procedure action scene: {action.scene}",
                    )
                )
            if action.required_evidence and not registries.evidence.contains(
                action.required_evidence
            ):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_EVIDENCE,
                        source,
                        f"Unknown procedure action evidence: {action.required_evidence}",
                    )
                )


def _validate_inspection_data(
    registries: Registries,
    scene_ids: set[str],
    diagnostics: list[Diagnostic],
) -> None:
    """Validate data/evidence_inspections.json; the registry keeps the raw catalog shape."""
    registry: InspectionRegistry = registries.inspections
    source = SourceLocation(registry.source_file, 1)
    inspected_evidence: set[str] = set()

    for inspection in registry.inspections:
        if inspection.evidence_id in inspected_evidence:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.DUPLICATE_INSPECTION,
                    source,
                    f"Duplicate inspection for evidence: {inspection.evidence_id}",
                )
            )
        inspected_evidence.add(inspection.evidence_id)

        if not registries.evidence.contains(inspection.evidence_id):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNKNOWN_INSPECTION_EVIDENCE,
                    source,
                    f"Unknown inspection evidence ID: {inspection.evidence_id}",
                )
            )

        if not inspection.hotspots:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.EMPTY_INSPECTION,
                    source,
                    f"Inspection for '{inspection.evidence_id}' requires at least one hotspot.",
                )
            )

        hotspot_ids = {hotspot.id for hotspot in inspection.hotspots}
        seen_hotspots: set[str] = set()
        for hotspot in inspection.hotspots:
            if not STABLE_ID_RE.fullmatch(hotspot.id):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_INSPECTION_HOTSPOT,
                        source,
                        f"Invalid inspection hotspot ID: {hotspot.id}",
                    )
                )
            if hotspot.id in seen_hotspots:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.DUPLICATE_INSPECTION_HOTSPOT,
                        source,
                        f"Duplicate inspection hotspot ID in '{inspection.evidence_id}': "
                        f"{hotspot.id}",
                    )
                )
            seen_hotspots.add(hotspot.id)

            if hotspot.rect is None or not _valid_rect(hotspot.rect):
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.INVALID_INSPECTION_RECT,
                        source,
                        f"Inspection hotspot '{hotspot.id}' requires a rect inside the "
                        "unit square.",
                    )
                )
            if hotspot.scene not in scene_ids:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INSPECTION_SCENE,
                        source,
                        f"Unknown inspection hotspot scene: {hotspot.scene}",
                    )
                )
            if hotspot.unlocked_by and hotspot.unlocked_by not in hotspot_ids - {hotspot.id}:
                diagnostics.append(
                    Diagnostic(
                        DiagnosticCode.UNKNOWN_INSPECTION_UNLOCK,
                        source,
                        f"Inspection hotspot '{hotspot.id}' is unlocked by an unknown "
                        f"hotspot: {hotspot.unlocked_by}",
                    )
                )
