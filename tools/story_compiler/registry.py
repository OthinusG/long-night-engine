from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from .diagnostics import SourceLocation


class RegistryError(ValueError):
    def __init__(self, path: Path, message: str) -> None:
        self.path = path
        super().__init__(message)


@dataclass(frozen=True, slots=True)
class CharacterRegistry:
    ids_by_display_name: dict[str, str]

    def resolve(self, display_name: str) -> str | None:
        return self.ids_by_display_name.get(display_name)

    def contains(self, character_id: str) -> bool:
        return character_id in self.ids_by_display_name.values()


@dataclass(frozen=True, slots=True)
class ExpressionRegistry:
    ids_by_character: dict[str, frozenset[str]]

    def contains(self, character_id: str, expression_id: str) -> bool:
        return expression_id in self.ids_by_character.get(character_id, frozenset())


@dataclass(frozen=True, slots=True)
class IdRegistry:
    ids: frozenset[str]
    versions_by_id: dict[str, frozenset[str]] = field(default_factory=dict)

    def contains(self, item_id: str) -> bool:
        return item_id in self.ids

    def contains_version(self, item_id: str, version_id: str) -> bool:
        return version_id in self.versions_by_id.get(item_id, frozenset())


@dataclass(frozen=True, slots=True)
class ProcedureAction:
    id: str
    name: str
    description: str
    scene: str
    result: str = ""
    required_evidence: str = ""
    required_flag: str = ""
    # Set by content_loader only; the story compiler does not need entry lines.
    source: SourceLocation | None = None


@dataclass(frozen=True, slots=True)
class ProcedureContext:
    id: str
    title: str
    description: str
    actions: tuple[ProcedureAction, ...] = ()
    source: SourceLocation | None = None


@dataclass(frozen=True, slots=True)
class ProcedureRegistry:
    contexts: tuple[ProcedureContext, ...] = ()
    source_file: str = "data/procedure.json"

    def contains(self, context_id: str) -> bool:
        return any(context.id == context_id for context in self.contexts)


@dataclass(frozen=True, slots=True)
class InspectionHotspot:
    id: str
    scene: str
    rect: tuple[float, float, float, float] | None = None
    unlocked_by: str = ""
    source: SourceLocation | None = None


@dataclass(frozen=True, slots=True)
class EvidenceInspection:
    evidence_id: str
    image: str
    hotspots: tuple[InspectionHotspot, ...] = ()
    source: SourceLocation | None = None


@dataclass(frozen=True, slots=True)
class InspectionRegistry:
    inspections: tuple[EvidenceInspection, ...] = ()
    source_file: str = "data/evidence_inspections.json"


@dataclass(frozen=True, slots=True)
class Registries:
    characters: CharacterRegistry
    expressions: ExpressionRegistry
    evidence: IdRegistry
    backgrounds: IdRegistry
    bgm: IdRegistry
    sfx: IdRegistry
    procedure: ProcedureRegistry = field(default_factory=ProcedureRegistry)
    inspections: InspectionRegistry = field(default_factory=InspectionRegistry)


def load_registries(data_root: Path) -> Registries:
    characters = _load_characters(data_root / "characters.json")
    expressions_path = data_root / "expressions.json"
    expressions = _load_expressions(expressions_path)
    unknown_characters = set(expressions.ids_by_character) - set(
        characters.ids_by_display_name.values()
    )
    if unknown_characters:
        raise RegistryError(
            expressions_path,
            f"Expressions reference unknown character ID: {sorted(unknown_characters)[0]}",
        )
    return Registries(
        characters=characters,
        expressions=expressions,
        evidence=_load_ids(data_root / "evidence.json", "evidence", "versions"),
        backgrounds=_load_ids(data_root / "backgrounds.json", "backgrounds"),
        bgm=_load_ids(data_root / "bgm.json", "bgm"),
        sfx=_load_ids(data_root / "sfx.json", "sfx"),
        procedure=_load_procedure(data_root / "procedure.json"),
        inspections=_load_inspections(data_root / "evidence_inspections.json"),
    )


def _read_object(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RegistryError(path, f"Cannot load registry: {error}") from error
    if not isinstance(value, dict):
        raise RegistryError(path, "Registry root must be a JSON object.")
    return value


def _load_characters(path: Path) -> CharacterRegistry:
    entries = _read_object(path).get("characters")
    if not isinstance(entries, list):
        raise RegistryError(path, "'characters' must be an array.")

    result: dict[str, str] = {}
    character_ids: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise RegistryError(path, "Each character must be an object.")
        character_id = entry.get("id")
        display_name = entry.get("display_name")
        if not isinstance(character_id, str) or not isinstance(display_name, str):
            raise RegistryError(path, "Each character requires string id and display_name.")
        if display_name in result:
            raise RegistryError(path, f"Duplicate character display name: {display_name}")
        if character_id in character_ids:
            raise RegistryError(path, f"Duplicate character ID: {character_id}")
        result[display_name] = character_id
        character_ids.add(character_id)
    return CharacterRegistry(result)


def _load_expressions(path: Path) -> ExpressionRegistry:
    entries = _read_object(path).get("expressions")
    if not isinstance(entries, dict):
        raise RegistryError(path, "'expressions' must be an object.")

    result: dict[str, frozenset[str]] = {}
    for character_id, expression_ids in entries.items():
        if not isinstance(character_id, str) or not isinstance(expression_ids, list):
            raise RegistryError(path, "Expression entries must map character IDs to arrays.")
        if not all(isinstance(item, str) for item in expression_ids):
            raise RegistryError(path, "Expression IDs must be strings.")
        result[character_id] = frozenset(expression_ids)
    return ExpressionRegistry(result)


def _load_ids(path: Path, key: str, versions_key: str = "") -> IdRegistry:
    entries = _read_object(path).get(key)
    if not isinstance(entries, list):
        raise RegistryError(path, f"'{key}' must be an array.")

    result: set[str] = set()
    versions_by_id: dict[str, frozenset[str]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise RegistryError(path, f"Each {key} entry requires a string id.")
        item_id = entry["id"]
        if item_id in result:
            raise RegistryError(path, f"Duplicate {key} ID: {item_id}")
        result.add(item_id)
        if versions_key:
            versions = entry.get(versions_key)
            if versions is not None and not isinstance(versions, dict):
                raise RegistryError(
                    path, f"'{versions_key}' for {key} '{item_id}' must be an object."
                )
            versions_by_id[item_id] = (
                frozenset(versions) if isinstance(versions, dict) else frozenset()
            )
    return IdRegistry(frozenset(result), versions_by_id)


def _load_procedure(path: Path) -> ProcedureRegistry:
    if not path.exists():
        return ProcedureRegistry()
    entries = _read_object(path).get("contexts")
    if not isinstance(entries, list):
        raise RegistryError(path, "'contexts' must be an array.")
    return ProcedureRegistry(
        tuple(_load_procedure_context(path, entry) for entry in entries),
        _source_file(path),
    )


def _load_procedure_context(path: Path, entry: object) -> ProcedureContext:
    context = _require_object(path, entry, "procedure context")
    context_id = _require_string(path, context, "id", "procedure context")
    label = f"procedure context '{context_id}'"
    actions = context.get("actions")
    if not isinstance(actions, list):
        raise RegistryError(path, f"{label} requires an 'actions' array.")
    return ProcedureContext(
        context_id,
        _require_string(path, context, "title", label),
        _require_string(path, context, "description", label),
        tuple(_load_procedure_action(path, context_id, item) for item in actions),
    )


def _load_procedure_action(path: Path, context_id: str, entry: object) -> ProcedureAction:
    label = f"procedure action in '{context_id}'"
    action = _require_object(path, entry, label)
    result = action.get("result")
    return ProcedureAction(
        _require_string(path, action, "id", label),
        _require_string(path, action, "name", label),
        _require_string(path, action, "description", label),
        _require_string(path, action, "scene", label),
        result if isinstance(result, str) else "",
        _optional_string(path, action, "required_evidence", label),
        _optional_string(path, action, "required_flag", label),
    )


def _load_inspections(path: Path) -> InspectionRegistry:
    if not path.exists():
        return InspectionRegistry()
    entries = _read_object(path).get("inspections")
    if not isinstance(entries, list):
        raise RegistryError(path, "'inspections' must be an array.")
    return InspectionRegistry(
        tuple(_load_inspection(path, entry) for entry in entries),
        _source_file(path),
    )


def _load_inspection(path: Path, entry: object) -> EvidenceInspection:
    inspection = _require_object(path, entry, "inspection")
    evidence_id = _require_string(path, inspection, "evidence_id", "inspection")
    label = f"inspection for '{evidence_id}'"
    hotspots = inspection.get("hotspots")
    if not isinstance(hotspots, list):
        raise RegistryError(path, f"{label} requires a 'hotspots' array.")
    return EvidenceInspection(
        evidence_id,
        _require_string(path, inspection, "image", label),
        tuple(_load_inspection_hotspot(path, evidence_id, item) for item in hotspots),
    )


def _load_inspection_hotspot(
    path: Path, evidence_id: str, entry: object
) -> InspectionHotspot:
    label = f"inspection hotspot in '{evidence_id}'"
    hotspot = _require_object(path, entry, label)
    return InspectionHotspot(
        _require_string(path, hotspot, "id", label),
        _require_string(path, hotspot, "scene", label),
        _load_rect(hotspot.get("rect")),
        _optional_string(path, hotspot, "unlocked_by", label),
    )


def _load_rect(value: object) -> tuple[float, float, float, float] | None:
    if not isinstance(value, list) or len(value) != 4:
        return None
    if not all(
        isinstance(item, (int, float)) and not isinstance(item, bool) for item in value
    ):
        return None
    return (float(value[0]), float(value[1]), float(value[2]), float(value[3]))


def _require_object(path: Path, entry: object, label: str) -> dict[str, object]:
    if not isinstance(entry, dict):
        raise RegistryError(path, f"Each {label} must be an object.")
    return entry


def _require_string(
    path: Path, entry: dict[str, object], key: str, label: str
) -> str:
    value = entry.get(key)
    if not isinstance(value, str) or not value:
        raise RegistryError(path, f"Each {label} requires a non-empty string {key}.")
    return value


def _optional_string(
    path: Path, entry: dict[str, object], key: str, label: str
) -> str:
    value = entry.get(key)
    if value is None:
        return ""
    if not isinstance(value, str) or not value:
        raise RegistryError(path, f"'{key}' in {label} must be a non-empty string.")
    return value


def _source_file(path: Path) -> str:
    """Repo-relative display path, matching the compiler's INVALID_REGISTRY mapping."""
    return path.relative_to(path.parent.parent).as_posix()
