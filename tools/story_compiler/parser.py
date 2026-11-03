from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from .diagnostics import Diagnostic, DiagnosticCode, SourceLocation
from .models import (
    AssetKind,
    AssetNode,
    ConditionNode,
    DialogueNode,
    EndInvestigationNode,
    EndProcedureNode,
    EvidenceKind,
    EvidenceNode,
    FlagNode,
    FlowKind,
    FlowNode,
    HotspotNode,
    LocationNode,
    PresentRuleNode,
    SceneNode,
    StartInvestigationNode,
    StartProcedureNode,
    StartTestimonyNode,
    StatementNode,
    StoryDocument,
    TalkTopicNode,
    StageNode,
    TalkUnlockNode,
    TestimonyNode,
)

SCENE_RE = re.compile(r"^#scene\s+(\S+)$")
LOCATION_RE = re.compile(r"^#location\s+(\S+)$")
STATEMENT_RE = re.compile(r"^##\s+statement\s+(\S+)$")
HOTSPOT_RE = re.compile(r"^##\s+hotspot\s+(\S+)$")
TOPIC_RE = re.compile(r"^##\s+topic\s+(\S+)$")
DIALOGUE_RE = re.compile(r"^([^\[\]:]+)\[([^\[\]]+)\]:$")
SIMPLE_COMMAND_RE = re.compile(r"^@(goto|call|bg|bgm|sfx|evidence_add|evidence_remove)\s+(\S+)$")
STAGE_RE = re.compile(r"^@char\s+(\S+)(?:\s+(left|center|right))?(?:\s+(\S+))?$")
HIDE_RE = re.compile(r"^@hide\s+(\S+)$")
EVIDENCE_UPDATE_RE = re.compile(r"^@evidence_update\s+(\S+)\s+(\S+)$")
FLAG_RE = re.compile(r"^@flag\s+(\S+)\s*=\s*(true|false)$")
IF_RE = re.compile(r"^@if\s+(\S+)$")
TESTIMONY_RE = re.compile(r"^@testimony\s+(\S+)$")
PENALTY_RE = re.compile(r"^@penalty\s+(.+)$")
WRONG_RE = re.compile(r"^@wrong\s+->\s+(\S+)$")
PRESS_RE = re.compile(r"^@press\s+->\s+(\S+)$")
PRESENT_RE = re.compile(r"^@present\s+(\S+)(?:\s+(\S+))?\s+->\s+(\S+)$")
LOCATION_PRESENT_RE = re.compile(r"^@present\s+(\S+)\s+->\s+(\S+)$")
INVESTIGATION_RE = re.compile(r"^@investigation\s+(\S+)$")
TALK_UNLOCK_RE = re.compile(r"^@talk_unlock\s+(\S+)$")
PROCEDURE_RE = re.compile(r"^@procedure\s+(\S+)$")
NAME_RE = re.compile(r"^@name\s+(.+)$")
BACKGROUND_RE = re.compile(r"^@bg\s+(\S+)$")
CHARACTER_RE = re.compile(r"^@character\s+(.+)$")
MOVE_RE = re.compile(r"^@move\s+->\s+(\S+)$")
GENERIC_PRESENT_RE = re.compile(r"^@generic_present\s+->\s+(\S+)$")
RECT_RE = re.compile(r"^@rect\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$")
TITLE_RE = re.compile(r"^@title\s+(.+)$")
CHILD_SCENE_RE = re.compile(r"^@scene\s+(\S+)$")

LOCATION_ONLY_RES = (NAME_RE, CHARACTER_RE, MOVE_RE, GENERIC_PRESENT_RE, RECT_RE, TITLE_RE)


@dataclass(slots=True)
class ParseResult:
    document: StoryDocument
    diagnostics: list[Diagnostic]


class StoryParser:
    def parse_path(self, path: Path, source_root: Path) -> ParseResult:
        source_name = path.relative_to(source_root).as_posix()
        return self.parse_text(path.read_text(encoding="utf-8"), source_name)

    def parse_text(self, text: str, source_name: str = "test.md") -> ParseResult:
        lines = text.splitlines()
        document = StoryDocument()
        diagnostics: list[Diagnostic] = []
        scene: SceneNode | None = None
        location_node: LocationNode | None = None
        hotspot: HotspotNode | None = None
        topic: TalkTopicNode | None = None
        testimony: TestimonyNode | None = None
        statement: StatementNode | None = None
        index = 0

        def location(line_index: int) -> SourceLocation:
            return SourceLocation(source_name, line_index + 1, lines[line_index])

        def error(code: DiagnosticCode, line_index: int, message: str) -> None:
            diagnostics.append(Diagnostic(code, location(line_index), message))

        def context_error(line_index: int, message: str) -> None:
            error(DiagnosticCode.INVALID_COMMAND_CONTEXT, line_index, message)

        def close_testimony(line_index: int) -> None:
            nonlocal testimony, statement
            if testimony is not None:
                error(
                    DiagnosticCode.UNTERMINATED_TESTIMONY,
                    line_index,
                    f"Testimony '{testimony.id}' is missing @endtestimony.",
                )
                testimony = None
                statement = None

        def reject_location_content(line_index: int, context: str) -> None:
            line = lines[line_index].strip()
            if line.startswith("@"):
                context_error(line_index, f"Command is not valid in {context}: {line}")
            else:
                error(
                    DiagnosticCode.MALFORMED_COMMAND,
                    line_index,
                    f"Unexpected content in {context}: {line}",
                )

        def parse_location_line(line_index: int) -> None:
            nonlocal hotspot, topic
            node = location_node
            if node is None:
                return
            line = lines[line_index].strip()

            hotspot_match = HOTSPOT_RE.fullmatch(line)
            if hotspot_match:
                hotspot = HotspotNode(hotspot_match.group(1), location(line_index))
                node.hotspots.append(hotspot)
                topic = None
                return

            topic_match = TOPIC_RE.fullmatch(line)
            if topic_match:
                topic = TalkTopicNode(topic_match.group(1), location(line_index))
                node.topics.append(topic)
                hotspot = None
                return

            if hotspot is not None:
                rect_match = RECT_RE.fullmatch(line)
                if rect_match:
                    if hotspot.rect is not None:
                        context_error(line_index, "Hotspot rect is already defined.")
                    else:
                        try:
                            x, y, width, height = (
                                float(value) for value in rect_match.groups()
                            )
                            hotspot.rect = (x, y, width, height)
                            hotspot.rect_source = location(line_index)
                        except ValueError:
                            error(
                                DiagnosticCode.MALFORMED_COMMAND,
                                line_index,
                                "Expected @rect x y w h with numbers.",
                            )
                    return
                child_scene_match = CHILD_SCENE_RE.fullmatch(line)
                if child_scene_match:
                    if hotspot.scene:
                        context_error(line_index, "Hotspot scene is already defined.")
                    else:
                        hotspot.scene = child_scene_match.group(1)
                        hotspot.scene_source = location(line_index)
                    return
                if TITLE_RE.fullmatch(line) or line == "@locked":
                    context_error(line_index, f"Command is only valid inside a ## topic: {line}")
                    return
                reject_location_content(line_index, "a ## hotspot")
                return

            if topic is not None:
                title_match = TITLE_RE.fullmatch(line)
                if title_match:
                    if topic.title:
                        context_error(line_index, "Topic title is already defined.")
                    else:
                        topic.title = title_match.group(1).strip()
                        topic.title_source = location(line_index)
                    return
                child_scene_match = CHILD_SCENE_RE.fullmatch(line)
                if child_scene_match:
                    if topic.scene:
                        context_error(line_index, "Topic scene is already defined.")
                    else:
                        topic.scene = child_scene_match.group(1)
                        topic.scene_source = location(line_index)
                    return
                if line == "@locked":
                    if topic.locked:
                        context_error(line_index, "Topic is already locked.")
                    else:
                        topic.locked = True
                    return
                if RECT_RE.fullmatch(line):
                    context_error(line_index, f"Command is only valid inside a ## hotspot: {line}")
                    return
                reject_location_content(line_index, "a ## topic")
                return

            name_match = NAME_RE.fullmatch(line)
            if name_match:
                if node.name:
                    context_error(line_index, "Location name is already defined.")
                else:
                    node.name = name_match.group(1).strip()
                return

            background_match = BACKGROUND_RE.fullmatch(line)
            if background_match:
                if node.background:
                    context_error(line_index, "Location background is already defined.")
                else:
                    node.background = background_match.group(1)
                    node.background_source = location(line_index)
                return

            character_match = CHARACTER_RE.fullmatch(line)
            if character_match:
                node.characters.append(
                    (character_match.group(1).strip(), location(line_index))
                )
                return

            move_match = MOVE_RE.fullmatch(line)
            if move_match:
                node.moves.append((move_match.group(1), location(line_index)))
                return

            present_match = LOCATION_PRESENT_RE.fullmatch(line)
            if present_match:
                node.present_reactions.append(
                    (present_match.group(1), present_match.group(2), location(line_index))
                )
                return

            generic_match = GENERIC_PRESENT_RE.fullmatch(line)
            if generic_match:
                if node.generic_present:
                    context_error(line_index, "Generic present scene is already defined.")
                else:
                    node.generic_present = generic_match.group(1)
                    node.generic_present_source = location(line_index)
                return

            if RECT_RE.fullmatch(line):
                context_error(line_index, f"Command is only valid inside a ## hotspot: {line}")
                return
            if TITLE_RE.fullmatch(line) or line == "@locked":
                context_error(line_index, f"Command is only valid inside a ## topic: {line}")
                return
            if CHILD_SCENE_RE.fullmatch(line):
                context_error(line_index, "@scene is only valid inside a ## hotspot or ## topic.")
                return
            reject_location_content(line_index, "a #location")

        while index < len(lines):
            raw = lines[index]
            line = raw.strip()
            if not line:
                index += 1
                continue

            scene_match = SCENE_RE.fullmatch(line)
            if scene_match:
                close_testimony(index)
                location_node = None
                hotspot = None
                topic = None
                scene = SceneNode(scene_match.group(1), location(index))
                document.scenes.append(scene)
                index += 1
                continue

            location_match = LOCATION_RE.fullmatch(line)
            if location_match:
                close_testimony(index)
                scene = None
                hotspot = None
                topic = None
                location_node = LocationNode(location_match.group(1), location(index))
                document.locations.append(location_node)
                index += 1
                continue

            if location_node is not None:
                parse_location_line(index)
                index += 1
                continue

            if HOTSPOT_RE.fullmatch(line):
                context_error(index, "## hotspot is only valid inside a #location.")
                index += 1
                continue

            if TOPIC_RE.fullmatch(line):
                context_error(index, "## topic is only valid inside a #location.")
                index += 1
                continue

            if CHILD_SCENE_RE.fullmatch(line):
                context_error(index, "@scene is only valid inside a ## hotspot or ## topic.")
                index += 1
                continue

            if line == "@locked" or any(
                pattern.fullmatch(line) for pattern in LOCATION_ONLY_RES
            ):
                context_error(index, f"Command is only valid inside a #location: {line}")
                index += 1
                continue

            if scene is None:
                error(
                    DiagnosticCode.INVALID_COMMAND_CONTEXT,
                    index,
                    "Story content must appear inside a #scene.",
                )
                index += 1
                continue

            statement_match = STATEMENT_RE.fullmatch(line)
            if statement_match:
                if testimony is None:
                    error(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        index,
                        "## statement is only valid inside a testimony.",
                    )
                else:
                    statement = StatementNode(statement_match.group(1), location(index))
                    testimony.statements.append(statement)
                index += 1
                continue

            dialogue_match = DIALOGUE_RE.fullmatch(line)
            if dialogue_match:
                body: list[str] = []
                body_index = index + 1
                while body_index < len(lines):
                    body_line = lines[body_index]
                    stripped = body_line.strip()
                    if (
                        not stripped
                        or stripped.startswith("@")
                        or stripped.startswith("#")
                        or DIALOGUE_RE.fullmatch(stripped)
                    ):
                        break
                    body.append(body_line.strip())
                    body_index += 1
                if not body:
                    error(DiagnosticCode.MALFORMED_COMMAND, index, "Dialogue has no text body.")
                elif testimony is None:
                    scene.instructions.append(
                        DialogueNode(
                            dialogue_match.group(1).strip(),
                            dialogue_match.group(2),
                            "\n".join(body),
                            location(index),
                        )
                    )
                elif statement is None:
                    error(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        index,
                        "Dialogue inside testimony requires a statement.",
                    )
                elif statement.text:
                    error(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        index,
                        "A statement may contain only one dialogue block.",
                    )
                else:
                    statement.speaker_name = dialogue_match.group(1).strip()
                    statement.expression_id = dialogue_match.group(2)
                    statement.text = "\n".join(body)
                    statement.dialogue_source = location(index)
                index = max(body_index, index + 1)
                continue

            if line == "@endtestimony":
                if testimony is None:
                    error(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        index,
                        "@endtestimony has no active testimony.",
                    )
                testimony = None
                statement = None
                index += 1
                continue

            testimony_match = TESTIMONY_RE.fullmatch(line)
            if testimony_match:
                if testimony is not None:
                    error(
                        DiagnosticCode.INVALID_COMMAND_CONTEXT,
                        index,
                        "Nested testimonies are not supported.",
                    )
                else:
                    testimony = TestimonyNode(testimony_match.group(1), location(index))
                    document.testimonies.append(testimony)
                    scene.instructions.append(
                        StartTestimonyNode(testimony.id, location(index))
                    )
                    statement = None
                index += 1
                continue

            if testimony is not None:
                penalty_match = PENALTY_RE.fullmatch(line)
                if penalty_match:
                    if testimony.penalty is not None:
                        error(DiagnosticCode.INVALID_PENALTY, index, "Penalty is already defined.")
                    else:
                        try:
                            testimony.penalty = int(penalty_match.group(1))
                            testimony.penalty_source = location(index)
                        except ValueError:
                            error(
                                DiagnosticCode.INVALID_PENALTY,
                                index,
                                "Penalty must be an integer from 0 through 100.",
                            )
                    index += 1
                    continue

                wrong_match = WRONG_RE.fullmatch(line)
                if wrong_match:
                    if testimony.wrong_target_scene:
                        error(
                            DiagnosticCode.INVALID_COMMAND_CONTEXT,
                            index,
                            "Wrong target is already defined.",
                        )
                    else:
                        testimony.wrong_target_scene = wrong_match.group(1)
                        testimony.wrong_source = location(index)
                    index += 1
                    continue

                press_match = PRESS_RE.fullmatch(line)
                if press_match:
                    if statement is None:
                        error(
                            DiagnosticCode.INVALID_COMMAND_CONTEXT,
                            index,
                            "@press is only valid inside a statement.",
                        )
                    elif statement.press_target_scene:
                        error(
                            DiagnosticCode.INVALID_COMMAND_CONTEXT,
                            index,
                            "Statement press target is already defined.",
                        )
                    else:
                        statement.press_target_scene = press_match.group(1)
                        statement.press_source = location(index)
                    index += 1
                    continue
                if line.startswith("@press"):
                    error(
                        DiagnosticCode.MALFORMED_COMMAND,
                        index,
                        "Expected @press -> target_scene.",
                    )
                    index += 1
                    continue

                present_match = PRESENT_RE.fullmatch(line)
                if present_match:
                    if statement is None:
                        error(
                            DiagnosticCode.INVALID_COMMAND_CONTEXT,
                            index,
                            "@present is only valid inside a statement.",
                        )
                    else:
                        statement.present_rules.append(
                            PresentRuleNode(
                                evidence_id=present_match.group(1),
                                target_scene=present_match.group(3),
                                source=location(index),
                                version=present_match.group(2) or "",
                            )
                        )
                    index += 1
                    continue
                if line.startswith("@present"):
                    error(
                        DiagnosticCode.MALFORMED_COMMAND,
                        index,
                        "Expected @present evidence_id [version] -> target_scene.",
                    )
                    index += 1
                    continue

                error(
                    DiagnosticCode.INVALID_COMMAND_CONTEXT,
                    index,
                    f"Command is not valid in testimony context: {line}",
                )
                index += 1
                continue

            if line == "@return":
                scene.instructions.append(FlowNode(FlowKind.RETURN, location(index)))
                index += 1
                continue

            if line == "@investigation_end":
                scene.instructions.append(EndInvestigationNode(location(index)))
                index += 1
                continue

            investigation_match = INVESTIGATION_RE.fullmatch(line)
            if investigation_match:
                scene.instructions.append(
                    StartInvestigationNode(investigation_match.group(1), location(index))
                )
                index += 1
                continue

            talk_unlock_match = TALK_UNLOCK_RE.fullmatch(line)
            if talk_unlock_match:
                scene.instructions.append(
                    TalkUnlockNode(talk_unlock_match.group(1), location(index))
                )
                index += 1
                continue

            if line == "@procedure_end":
                scene.instructions.append(EndProcedureNode(location(index)))
                index += 1
                continue

            procedure_match = PROCEDURE_RE.fullmatch(line)
            if procedure_match:
                scene.instructions.append(
                    StartProcedureNode(procedure_match.group(1), location(index))
                )
                index += 1
                continue

            if line.startswith("@procedure"):
                error(
                    DiagnosticCode.MALFORMED_COMMAND,
                    index,
                    "Expected @procedure context_id.",
                )
                index += 1
                continue

            simple_match = SIMPLE_COMMAND_RE.fullmatch(line)
            if simple_match:
                command, argument = simple_match.groups()
                if command in {"goto", "call"}:
                    scene.instructions.append(
                        FlowNode(FlowKind(command), location(index), argument)
                    )
                elif command in {"bg", "bgm", "sfx"}:
                    scene.instructions.append(
                        AssetNode(AssetKind(command), argument, location(index))
                    )
                else:
                    scene.instructions.append(
                        EvidenceNode(EvidenceKind(command), argument, location(index))
                    )
                index += 1
                continue

            stage_match = STAGE_RE.fullmatch(line)
            if stage_match:
                scene.instructions.append(
                    StageNode(
                        stage_match.group(1),
                        location(index),
                        stage_match.group(2) or "center",
                        stage_match.group(3) or "",
                    )
                )
                index += 1
                continue

            hide_match = HIDE_RE.fullmatch(line)
            if hide_match:
                scene.instructions.append(
                    StageNode(hide_match.group(1), location(index), visible=False)
                )
                index += 1
                continue

            update_match = EVIDENCE_UPDATE_RE.fullmatch(line)
            if update_match:
                scene.instructions.append(
                    EvidenceNode(
                        EvidenceKind.UPDATE,
                        update_match.group(1),
                        location(index),
                        update_match.group(2),
                    )
                )
                index += 1
                continue

            flag_match = FLAG_RE.fullmatch(line)
            if flag_match:
                scene.instructions.append(
                    FlagNode(flag_match.group(1), flag_match.group(2) == "true", location(index))
                )
                index += 1
                continue

            if_match = IF_RE.fullmatch(line)
            if if_match:
                goto_index = index + 1
                while goto_index < len(lines) and not lines[goto_index].strip():
                    goto_index += 1
                goto_match = (
                    re.fullmatch(r"@goto\s+(\S+)", lines[goto_index].strip())
                    if goto_index < len(lines)
                    else None
                )
                if goto_match is None:
                    error(
                        DiagnosticCode.MALFORMED_COMMAND,
                        index,
                        "@if must be followed by @goto target_scene.",
                    )
                    index += 1
                else:
                    scene.instructions.append(
                        ConditionNode(if_match.group(1), goto_match.group(1), location(index))
                    )
                    index = goto_index + 1
                continue

            if (
                PENALTY_RE.fullmatch(line)
                or WRONG_RE.fullmatch(line)
                or PRESS_RE.fullmatch(line)
                or PRESENT_RE.fullmatch(line)
                or line == "@endtestimony"
            ):
                error(
                    DiagnosticCode.INVALID_COMMAND_CONTEXT,
                    index,
                    f"Command is only valid inside testimony: {line}",
                )
                index += 1
                continue

            if line.startswith("@") or line.startswith("#"):
                error(
                    DiagnosticCode.MALFORMED_COMMAND,
                    index,
                    f"Malformed or unsupported command: {line}",
                )
            else:
                error(
                    DiagnosticCode.MALFORMED_COMMAND,
                    index,
                    "Text must follow a character dialogue header.",
                )
            index += 1

        if testimony is not None:
            last_index = max(len(lines) - 1, 0)
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNTERMINATED_TESTIMONY,
                    SourceLocation(source_name, last_index + 1, lines[last_index] if lines else ""),
                    f"Testimony '{testimony.id}' is missing @endtestimony.",
                )
            )

        return ParseResult(document, diagnostics)
