from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import TypeAlias

from .diagnostics import SourceLocation


class FlowKind(str, Enum):
    GOTO = "goto"
    CALL = "call"
    RETURN = "return"


class AssetKind(str, Enum):
    BACKGROUND = "bg"
    BGM = "bgm"
    SFX = "sfx"


class EvidenceKind(str, Enum):
    ADD = "evidence_add"
    UPDATE = "evidence_update"
    REMOVE = "evidence_remove"


@dataclass(slots=True)
class DialogueNode:
    speaker_name: str
    expression_id: str
    text: str
    source: SourceLocation


@dataclass(slots=True)
class FlowNode:
    kind: FlowKind
    source: SourceLocation
    target_scene: str = ""


@dataclass(slots=True)
class FlagNode:
    flag_id: str
    value: bool
    source: SourceLocation


@dataclass(slots=True)
class ConditionNode:
    flag_id: str
    target_scene: str
    source: SourceLocation


@dataclass(slots=True)
class AssetNode:
    kind: AssetKind
    asset_id: str
    source: SourceLocation


@dataclass(slots=True)
class StageNode:
    """Character staging request: @char <id> [slot] [expression] / @hide <id>."""

    character_id: str
    source: SourceLocation
    slot: str = "center"
    expression_id: str = ""
    visible: bool = True


@dataclass(slots=True)
class EvidenceNode:
    kind: EvidenceKind
    evidence_id: str
    source: SourceLocation
    version: str = ""


@dataclass(slots=True)
class StartTestimonyNode:
    testimony_id: str
    source: SourceLocation


@dataclass(slots=True)
class StartInvestigationNode:
    location_id: str
    source: SourceLocation


@dataclass(slots=True)
class EndInvestigationNode:
    source: SourceLocation


@dataclass(slots=True)
class TalkUnlockNode:
    topic_id: str
    source: SourceLocation


@dataclass(slots=True)
class StartProcedureNode:
    context_id: str
    source: SourceLocation


@dataclass(slots=True)
class EndProcedureNode:
    source: SourceLocation


InstructionNode: TypeAlias = (
    DialogueNode
    | StageNode
    | FlowNode
    | FlagNode
    | ConditionNode
    | AssetNode
    | EvidenceNode
    | StartTestimonyNode
    | StartInvestigationNode
    | EndInvestigationNode
    | TalkUnlockNode
    | StartProcedureNode
    | EndProcedureNode
)


@dataclass(slots=True)
class PresentRuleNode:
    evidence_id: str
    target_scene: str
    source: SourceLocation
    version: str = ""


@dataclass(slots=True)
class StatementNode:
    id: str
    source: SourceLocation
    speaker_name: str = ""
    expression_id: str = ""
    text: str = ""
    dialogue_source: SourceLocation | None = None
    press_target_scene: str = ""
    press_source: SourceLocation | None = None
    present_rules: list[PresentRuleNode] = field(default_factory=list)


@dataclass(slots=True)
class TestimonyNode:
    id: str
    source: SourceLocation
    penalty: int | None = None
    penalty_source: SourceLocation | None = None
    wrong_target_scene: str = ""
    wrong_source: SourceLocation | None = None
    statements: list[StatementNode] = field(default_factory=list)


@dataclass(slots=True)
class SceneNode:
    id: str
    source: SourceLocation
    instructions: list[InstructionNode] = field(default_factory=list)


@dataclass(slots=True)
class HotspotNode:
    id: str
    source: SourceLocation
    rect: tuple[float, float, float, float] | None = None
    rect_source: SourceLocation | None = None
    scene: str = ""
    scene_source: SourceLocation | None = None


@dataclass(slots=True)
class TalkTopicNode:
    id: str
    source: SourceLocation
    title: str = ""
    title_source: SourceLocation | None = None
    scene: str = ""
    scene_source: SourceLocation | None = None
    locked: bool = False


@dataclass(slots=True)
class LocationNode:
    id: str
    source: SourceLocation
    name: str = ""
    background: str = ""
    background_source: SourceLocation | None = None
    characters: list[tuple[str, SourceLocation]] = field(default_factory=list)
    moves: list[tuple[str, SourceLocation]] = field(default_factory=list)
    present_reactions: list[tuple[str, str, SourceLocation]] = field(default_factory=list)
    generic_present: str = ""
    generic_present_source: SourceLocation | None = None
    hotspots: list[HotspotNode] = field(default_factory=list)
    topics: list[TalkTopicNode] = field(default_factory=list)


@dataclass(slots=True)
class StoryDocument:
    scenes: list[SceneNode] = field(default_factory=list)
    testimonies: list[TestimonyNode] = field(default_factory=list)
    locations: list[LocationNode] = field(default_factory=list)

    def extend(self, other: StoryDocument) -> None:
        self.scenes.extend(other.scenes)
        self.testimonies.extend(other.testimonies)
        self.locations.extend(other.locations)
