from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .diagnostics import Diagnostic, DiagnosticCode, SourceLocation
from .registry import (
    EvidenceInspection,
    InspectionHotspot,
    ProcedureAction,
    ProcedureContext,
)

SUPPORTED_FORMAT_VERSION = 1

CHARACTERS_FILE = "data/characters.json"
EXPRESSIONS_FILE = "data/expressions.json"
EVIDENCE_FILE = "data/evidence.json"
PROCEDURES_FILE = "data/procedure.json"
INSPECTIONS_FILE = "data/evidence_inspections.json"

@dataclass(frozen=True, slots=True)
class CharacterDef:
    id: str
    display_name: str
    default_expression: str
    portraits: dict[str, str]
    source: SourceLocation


@dataclass(frozen=True, slots=True)
class ExpressionDef:
    character_id: str
    id: str
    portrait: str
    source: SourceLocation


@dataclass(frozen=True, slots=True)
class EvidenceVersionDef:
    id: str
    name: str
    description: str
    source: SourceLocation


@dataclass(frozen=True, slots=True)
class EvidenceDef:
    id: str
    name: str
    description: str
    presentable: bool
    icon: str
    detail_image: str
    versions: dict[str, EvidenceVersionDef]
    source: SourceLocation


@dataclass(frozen=True, slots=True)
class BackgroundDef:
    id: str
    path: str
    source: SourceLocation


@dataclass(frozen=True, slots=True)
class AudioDef:
    id: str
    path: str
    source: SourceLocation


@dataclass(frozen=True, slots=True)
class ContentCatalog:
    characters: tuple[CharacterDef, ...] = ()
    expressions: tuple[ExpressionDef, ...] = ()
    evidence: tuple[EvidenceDef, ...] = ()
    backgrounds: tuple[BackgroundDef, ...] = ()
    bgm: tuple[AudioDef, ...] = ()
    sfx: tuple[AudioDef, ...] = ()
    procedures: tuple[ProcedureContext, ...] = ()
    inspections: tuple[EvidenceInspection, ...] = ()

    def character(self, character_id: str) -> CharacterDef | None:
        return next((item for item in self.characters if item.id == character_id), None)

    def character_by_name(self, display_name: str) -> CharacterDef | None:
        return next(
            (item for item in self.characters if item.display_name == display_name), None
        )

    def character_names(self) -> tuple[str, ...]:
        return tuple(sorted(item.display_name for item in self.characters))

    def expressions_of(self, character_id: str) -> tuple[str, ...]:
        return tuple(
            item.id for item in self.expressions if item.character_id == character_id
        )

    def expression(self, character_id: str, expression_id: str) -> ExpressionDef | None:
        return next(
            (
                item
                for item in self.expressions
                if item.character_id == character_id and item.id == expression_id
            ),
            None,
        )

    def has_expression(self, character_id: str, expression_id: str) -> bool:
        return self.expression(character_id, expression_id) is not None

    def evidence_def(self, evidence_id: str) -> EvidenceDef | None:
        return next((item for item in self.evidence if item.id == evidence_id), None)

    def has_evidence(self, evidence_id: str) -> bool:
        return self.evidence_def(evidence_id) is not None

    def has_evidence_version(self, evidence_id: str, version_id: str) -> bool:
        definition = self.evidence_def(evidence_id)
        return definition is not None and version_id in definition.versions

    def has_background(self, background_id: str) -> bool:
        return any(item.id == background_id for item in self.backgrounds)

    def has_bgm(self, bgm_id: str) -> bool:
        return any(item.id == bgm_id for item in self.bgm)

    def has_sfx(self, sfx_id: str) -> bool:
        return any(item.id == sfx_id for item in self.sfx)


@dataclass(frozen=True, slots=True)
class ContentLoadResult:
    catalog: ContentCatalog
    diagnostics: tuple[Diagnostic, ...] = ()


def load_content(data_root: Path) -> ContentLoadResult:
    diagnostics: list[Diagnostic] = []
    catalog = ContentCatalog(
        characters=_load_characters(data_root / "characters.json", diagnostics),
        expressions=_load_expressions(data_root / "expressions.json", diagnostics),
        evidence=_load_evidence(data_root / "evidence.json", diagnostics),
        backgrounds=_load_assets(data_root / "backgrounds.json", "backgrounds", diagnostics),
        bgm=_load_assets(data_root / "bgm.json", "bgm", diagnostics),
        sfx=_load_assets(data_root / "sfx.json", "sfx", diagnostics),
        procedures=_load_procedures(data_root / "procedure.json", diagnostics),
        inspections=_load_inspections(
            data_root / "evidence_inspections.json", diagnostics
        ),
    )
    return ContentLoadResult(catalog, tuple(diagnostics))


# --- catalog plumbing ---------------------------------------------------------


def _load_root(
    path: Path,
    display: str,
    diagnostics: list[Diagnostic],
    *,
    required: bool = True,
) -> tuple[dict[str, object], str] | None:
    """Read one catalog, reporting LN2016/LN2015/LN2017 instead of raising."""
    if not path.is_file():
        if required:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.UNREADABLE_CATALOG,
                    SourceLocation(display, 1),
                    f"Missing content catalog: {display}. Expected: a readable JSON object.",
                )
            )
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNREADABLE_CATALOG,
                SourceLocation(display, 1),
                f"Cannot read {display}. Found: {error}.",
            )
        )
        return None
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.UNREADABLE_CATALOG,
                SourceLocation(display, error.lineno),
                f"Malformed JSON in {display}. Found: {error.msg}.",
            )
        )
        return None
    if not isinstance(value, dict):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                SourceLocation(display, 1),
                f"{display} must contain a JSON object at the root.",
            )
        )
        return None
    if not _check_format_version(display, text, value, diagnostics):
        return None
    return value, text


def _check_format_version(
    display: str,
    text: str,
    root: dict[str, object],
    diagnostics: list[Diagnostic],
) -> bool:
    """A missing format_version means version 1, so existing catalogs keep loading."""
    version = root.get("format_version")
    if version is None:
        return True
    if (
        isinstance(version, int)
        and not isinstance(version, bool)
        and version == SUPPORTED_FORMAT_VERSION
    ):
        return True
    diagnostics.append(
        Diagnostic(
            DiagnosticCode.UNSUPPORTED_FORMAT_VERSION,
            _line_source(display, text, '"format_version"'),
            f"Unsupported format_version in {display}. "
            f"Found: {version!r}; expected: {SUPPORTED_FORMAT_VERSION}.",
        )
    )
    return False


def _entries(
    root: dict[str, object],
    key: str,
    display: str,
    diagnostics: list[Diagnostic],
) -> list[object]:
    value = root.get(key)
    if not isinstance(value, list):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                SourceLocation(display, 1),
                f"{display} requires a '{key}' array.",
            )
        )
        return []
    return value


def _line_source(
    display: str, text: str, needle: str, start_line: int = 1
) -> SourceLocation:
    """Best-effort entry line: catalogs are human-authored, one ID per entry.

    `start_line` scopes the search to a nested entry (a character's expressions,
    an evidence entry's versions) so a repeated inner ID is not attributed to
    the first entry that happens to use it.
    """
    if needle:
        lines = text.splitlines()
        for line_number in range(max(start_line, 1), len(lines) + 1):
            if needle in lines[line_number - 1]:
                return SourceLocation(display, line_number)
    return SourceLocation(display, max(start_line, 1))


def _entry_source(
    display: str, text: str, entry_id: str, start_line: int = 1
) -> SourceLocation:
    return _line_source(display, text, f'"{entry_id}"', start_line)


def _require_id(
    entry: dict[str, object],
    display: str,
    text: str,
    label: str,
    diagnostics: list[Diagnostic],
) -> str:
    value = entry.get("id")
    if not isinstance(value, str) or not value:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                SourceLocation(display, 1),
                f"{display}: each {label} requires a non-empty string id.",
            )
        )
        return ""
    return value


def _optional_string(
    entry: dict[str, object],
    key: str,
    source: SourceLocation,
    label: str,
    diagnostics: list[Diagnostic],
) -> str:
    value = entry.get(key)
    if value is None:
        return ""
    if not isinstance(value, str) or not value:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                source,
                f"'{key}' in {label} must be a non-empty string. Found: {value!r}.",
            )
        )
        return ""
    return value


def _report_duplicate(
    seen: set[str],
    item_id: str,
    code: DiagnosticCode,
    label: str,
    source: SourceLocation,
    diagnostics: list[Diagnostic],
) -> None:
    if item_id in seen:
        diagnostics.append(
            Diagnostic(
                code,
                source,
                f"Duplicate {label}: {item_id}. Expected: unique IDs.",
            )
        )
    seen.add(item_id)


# --- catalogs -----------------------------------------------------------------


def _load_characters(path: Path, diagnostics: list[Diagnostic]) -> tuple[CharacterDef, ...]:
    loaded = _load_root(path, CHARACTERS_FILE, diagnostics)
    if loaded is None:
        return ()
    root, text = loaded
    result: list[CharacterDef] = []
    seen_ids: set[str] = set()
    seen_names: set[str] = set()
    for entry in _entries(root, "characters", CHARACTERS_FILE, diagnostics):
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(CHARACTERS_FILE, 1),
                    "Each character entry must be an object.",
                )
            )
            continue
        character_id = _require_id(entry, CHARACTERS_FILE, text, "character", diagnostics)
        if not character_id:
            continue
        source = _entry_source(CHARACTERS_FILE, text, character_id)
        display_name = entry.get("display_name")
        if not isinstance(display_name, str) or not display_name:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    source,
                    f"Character '{character_id}' requires a non-empty display_name. "
                    f"Found: {display_name!r}.",
                )
            )
            display_name = ""
        _report_duplicate(
            seen_ids,
            character_id,
            DiagnosticCode.DUPLICATE_CHARACTER,
            "character ID",
            source,
            diagnostics,
        )
        if display_name:
            _report_duplicate(
                seen_names,
                display_name,
                DiagnosticCode.DUPLICATE_CHARACTER_NAME,
                "character display name",
                source,
                diagnostics,
            )
        result.append(
            CharacterDef(
                character_id,
                display_name,
                _optional_string(
                    entry, "default_expression", source, f"character '{character_id}'", diagnostics
                ),
                _load_portrait_overrides(entry, source, character_id, diagnostics),
                source,
            )
        )
    return tuple(result)


def _load_portrait_overrides(
    entry: dict[str, object],
    source: SourceLocation,
    character_id: str,
    diagnostics: list[Diagnostic],
) -> dict[str, str]:
    value = entry.get("portraits")
    if value is None:
        return {}
    if not isinstance(value, dict):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                source,
                f"'portraits' in character '{character_id}' must map expression IDs to "
                f"res:// paths. Found: {value!r}.",
            )
        )
        return {}
    portraits: dict[str, str] = {}
    for expression_id, portrait_path in value.items():
        if not isinstance(expression_id, str) or not isinstance(portrait_path, str):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    source,
                    f"Portrait override for character '{character_id}' must map string "
                    "expression IDs to string res:// paths.",
                )
            )
            continue
        portraits[expression_id] = portrait_path
    return portraits


def _load_expressions(path: Path, diagnostics: list[Diagnostic]) -> tuple[ExpressionDef, ...]:
    loaded = _load_root(path, EXPRESSIONS_FILE, diagnostics)
    if loaded is None:
        return ()
    root, text = loaded
    entries = root.get("expressions")
    if not isinstance(entries, dict):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                SourceLocation(EXPRESSIONS_FILE, 1),
                f"{EXPRESSIONS_FILE} requires an 'expressions' object.",
            )
        )
        return ()

    result: list[ExpressionDef] = []
    for character_id, values in entries.items():
        if not isinstance(character_id, str) or not isinstance(values, list):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(EXPRESSIONS_FILE, 1),
                    "Expression entries must map character IDs to arrays of expression IDs.",
                )
            )
            continue
        seen: set[str] = set()
        character_line = _entry_source(EXPRESSIONS_FILE, text, character_id).line
        for value in values:
            expression_id, portrait = _read_expression(value, character_id, diagnostics)
            if not expression_id:
                continue
            source = _entry_source(EXPRESSIONS_FILE, text, expression_id, character_line)
            _report_duplicate(
                seen,
                expression_id,
                DiagnosticCode.DUPLICATE_EXPRESSION,
                f"expression ID for '{character_id}'",
                source,
                diagnostics,
            )
            result.append(ExpressionDef(character_id, expression_id, portrait, source))
    return tuple(result)


def _read_expression(
    value: object,
    character_id: str,
    diagnostics: list[Diagnostic],
) -> tuple[str, str]:
    """Expressions are authored either as IDs or as {id, portrait} objects."""
    if isinstance(value, str) and value:
        return value, ""
    if isinstance(value, dict):
        expression_id = value.get("id")
        if isinstance(expression_id, str) and expression_id:
            portrait = value.get("portrait")
            return expression_id, portrait if isinstance(portrait, str) else ""
    diagnostics.append(
        Diagnostic(
            DiagnosticCode.INVALID_CATALOG_ENTRY,
            SourceLocation(EXPRESSIONS_FILE, 1),
            f"Expression entries for '{character_id}' must be IDs or objects with a "
            f"string id. Found: {value!r}.",
        )
    )
    return "", ""


def _load_evidence(path: Path, diagnostics: list[Diagnostic]) -> tuple[EvidenceDef, ...]:
    loaded = _load_root(path, EVIDENCE_FILE, diagnostics)
    if loaded is None:
        return ()
    root, text = loaded
    result: list[EvidenceDef] = []
    seen: set[str] = set()
    for entry in _entries(root, "evidence", EVIDENCE_FILE, diagnostics):
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(EVIDENCE_FILE, 1),
                    "Each evidence entry must be an object.",
                )
            )
            continue
        evidence_id = _require_id(entry, EVIDENCE_FILE, text, "evidence entry", diagnostics)
        if not evidence_id:
            continue
        source = _entry_source(EVIDENCE_FILE, text, evidence_id)
        _report_duplicate(
            seen,
            evidence_id,
            DiagnosticCode.DUPLICATE_EVIDENCE,
            "evidence ID",
            source,
            diagnostics,
        )
        presentable = entry.get("presentable")
        result.append(
            EvidenceDef(
                evidence_id,
                _optional_string(entry, "name", source, f"evidence '{evidence_id}'", diagnostics),
                _optional_string(
                    entry, "description", source, f"evidence '{evidence_id}'", diagnostics
                ),
                presentable if isinstance(presentable, bool) else True,
                _optional_string(entry, "icon", source, f"evidence '{evidence_id}'", diagnostics),
                _optional_string(
                    entry, "detail_image", source, f"evidence '{evidence_id}'", diagnostics
                ),
                _load_versions(entry, text, source, evidence_id, diagnostics),
                source,
            )
        )
    return tuple(result)


def _load_versions(
    entry: dict[str, object],
    text: str,
    source: SourceLocation,
    evidence_id: str,
    diagnostics: list[Diagnostic],
) -> dict[str, EvidenceVersionDef]:
    value = entry.get("versions")
    if value is None:
        return {}
    if not isinstance(value, dict):
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.INVALID_CATALOG_ENTRY,
                source,
                f"'versions' for evidence '{evidence_id}' must be an object. Found: {value!r}.",
            )
        )
        return {}
    versions: dict[str, EvidenceVersionDef] = {}
    for version_id, version in value.items():
        if not isinstance(version_id, str) or not isinstance(version, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    source,
                    f"Evidence versions for '{evidence_id}' must map version IDs to objects.",
                )
            )
            continue
        version_source = _entry_source(EVIDENCE_FILE, text, version_id, source.line)
        versions[version_id] = EvidenceVersionDef(
            version_id,
            _optional_string(
                version, "name", version_source, f"version '{version_id}'", diagnostics
            ),
            _optional_string(
                version, "description", version_source, f"version '{version_id}'", diagnostics
            ),
            version_source,
        )
    return versions


def _load_assets(
    path: Path,
    key: str,
    diagnostics: list[Diagnostic],
) -> tuple[BackgroundDef | AudioDef, ...]:
    display_file = f"data/{path.name}"
    loaded = _load_root(path, display_file, diagnostics)
    if loaded is None:
        return ()
    root, text = loaded
    duplicate_code = {
        "backgrounds": DiagnosticCode.DUPLICATE_BACKGROUND,
        "bgm": DiagnosticCode.DUPLICATE_BGM,
        "sfx": DiagnosticCode.DUPLICATE_SFX,
    }[key]
    result: list[BackgroundDef | AudioDef] = []
    seen: set[str] = set()
    for entry in _entries(root, key, display_file, diagnostics):
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(display_file, 1),
                    f"Each '{key}' entry must be an object.",
                )
            )
            continue
        asset_id = _require_id(entry, display_file, text, f"'{key}' entry", diagnostics)
        if not asset_id:
            continue
        source = _entry_source(display_file, text, asset_id)
        _report_duplicate(seen, asset_id, duplicate_code, f"{key} ID", source, diagnostics)
        authored = _optional_string(entry, "path", source, f"'{asset_id}'", diagnostics)
        definition = (BackgroundDef if key == "backgrounds" else AudioDef)(
            asset_id, authored, source
        )
        result.append(definition)
    return tuple(result)


def _load_procedures(path: Path, diagnostics: list[Diagnostic]) -> tuple[ProcedureContext, ...]:
    loaded = _load_root(path, PROCEDURES_FILE, diagnostics, required=False)
    if loaded is None:
        return ()
    root, text = loaded
    result: list[ProcedureContext] = []
    seen: set[str] = set()
    for entry in _entries(root, "contexts", PROCEDURES_FILE, diagnostics):
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(PROCEDURES_FILE, 1),
                    "Each procedure context must be an object.",
                )
            )
            continue
        context_id = _require_id(entry, PROCEDURES_FILE, text, "procedure context", diagnostics)
        if not context_id:
            continue
        source = _entry_source(PROCEDURES_FILE, text, context_id)
        _report_duplicate(
            seen,
            context_id,
            DiagnosticCode.DUPLICATE_PROCEDURE_CONTEXT_ID,
            "procedure context ID",
            source,
            diagnostics,
        )
        actions = entry.get("actions")
        if not isinstance(actions, list):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    source,
                    f"Procedure context '{context_id}' requires an 'actions' array. "
                    f"Found: {actions!r}.",
                )
            )
            actions = []
        result.append(
            ProcedureContext(
                context_id,
                _optional_string(
                    entry, "title", source, f"procedure context '{context_id}'", diagnostics
                ),
                _optional_string(
                    entry, "description", source, f"procedure context '{context_id}'", diagnostics
                ),
                _load_actions(actions, text, context_id, source.line, diagnostics),
                source,
            )
        )
    return tuple(result)


def _load_actions(
    actions: list[object],
    text: str,
    context_id: str,
    start_line: int,
    diagnostics: list[Diagnostic],
) -> tuple[ProcedureAction, ...]:
    result: list[ProcedureAction] = []
    seen: set[str] = set()
    for entry in actions:
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(PROCEDURES_FILE, 1),
                    f"Each action in procedure context '{context_id}' must be an object.",
                )
            )
            continue
        action_id = _require_id(entry, PROCEDURES_FILE, text, "procedure action", diagnostics)
        if not action_id:
            continue
        source = _entry_source(PROCEDURES_FILE, text, action_id, start_line)
        label = f"action '{context_id}.{action_id}'"
        _report_duplicate(
            seen,
            action_id,
            DiagnosticCode.DUPLICATE_PROCEDURE_ACTION_ID,
            f"procedure action ID in '{context_id}'",
            source,
            diagnostics,
        )
        result.append(
            ProcedureAction(
                action_id,
                _optional_string(entry, "name", source, label, diagnostics),
                _optional_string(entry, "description", source, label, diagnostics),
                _optional_string(entry, "scene", source, label, diagnostics),
                _optional_string(entry, "result", source, label, diagnostics),
                _optional_string(entry, "required_evidence", source, label, diagnostics),
                _optional_string(entry, "required_flag", source, label, diagnostics),
                source,
            )
        )
    return tuple(result)


def _load_inspections(
    path: Path, diagnostics: list[Diagnostic]
) -> tuple[EvidenceInspection, ...]:
    loaded = _load_root(path, INSPECTIONS_FILE, diagnostics, required=False)
    if loaded is None:
        return ()
    root, text = loaded
    result: list[EvidenceInspection] = []
    seen: set[str] = set()
    for entry in _entries(root, "inspections", INSPECTIONS_FILE, diagnostics):
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(INSPECTIONS_FILE, 1),
                    "Each inspection must be an object.",
                )
            )
            continue
        evidence_id = entry.get("evidence_id")
        if not isinstance(evidence_id, str) or not evidence_id:
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(INSPECTIONS_FILE, 1),
                    "Each inspection requires a non-empty string evidence_id.",
                )
            )
            continue
        source = _entry_source(INSPECTIONS_FILE, text, evidence_id)
        _report_duplicate(
            seen,
            evidence_id,
            DiagnosticCode.DUPLICATE_INSPECTION_EVIDENCE,
            "inspection for evidence",
            source,
            diagnostics,
        )
        hotspots = entry.get("hotspots")
        if not isinstance(hotspots, list):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    source,
                    f"Inspection for '{evidence_id}' requires a 'hotspots' array. "
                    f"Found: {hotspots!r}.",
                )
            )
            hotspots = []
        result.append(
            EvidenceInspection(
                evidence_id,
                _optional_string(
                    entry, "image", source, f"inspection for '{evidence_id}'", diagnostics
                ),
                _load_hotspots(hotspots, text, evidence_id, source.line, diagnostics),
                source,
            )
        )
    return tuple(result)


def _load_hotspots(
    hotspots: list[object],
    text: str,
    evidence_id: str,
    start_line: int,
    diagnostics: list[Diagnostic],
) -> tuple[InspectionHotspot, ...]:
    result: list[InspectionHotspot] = []
    seen: set[str] = set()
    for entry in hotspots:
        if not isinstance(entry, dict):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_CATALOG_ENTRY,
                    SourceLocation(INSPECTIONS_FILE, 1),
                    f"Each hotspot in inspection '{evidence_id}' must be an object.",
                )
            )
            continue
        hotspot_id = _require_id(entry, INSPECTIONS_FILE, text, "inspection hotspot", diagnostics)
        if not hotspot_id:
            continue
        source = _entry_source(INSPECTIONS_FILE, text, hotspot_id, start_line)
        _report_duplicate(
            seen,
            hotspot_id,
            DiagnosticCode.DUPLICATE_INSPECTION_HOTSPOT_ID,
            f"hotspot ID in inspection '{evidence_id}'",
            source,
            diagnostics,
        )
        result.append(
            InspectionHotspot(
                hotspot_id,
                _optional_string(
                    entry, "scene", source, f"hotspot '{hotspot_id}'", diagnostics
                ),
                _load_rect(entry.get("rect")),
                _optional_string(
                    entry, "unlocked_by", source, f"hotspot '{hotspot_id}'", diagnostics
                ),
                source,
            )
        )
    return tuple(result)


def _load_rect(value: object) -> tuple[float, float, float, float] | None:
    if not isinstance(value, list) or len(value) != 4:
        return None
    if not all(
        isinstance(item, (int, float)) and not isinstance(item, bool) for item in value
    ):
        return None
    return (float(value[0]), float(value[1]), float(value[2]), float(value[3]))
