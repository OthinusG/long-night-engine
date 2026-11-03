from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum


class DiagnosticSeverity(str, Enum):
    ERROR = "ERROR"
    # Placeholder presentation is allowed while Chapter 1 art is in production,
    # so content warnings must be reportable without failing a build.
    WARNING = "WARNING"


class DiagnosticCode(str, Enum):
    DUPLICATE_SCENE = "LN1001"
    UNKNOWN_SCENE = "LN1002"
    INVALID_SCENE_ID = "LN1003"
    UNKNOWN_CHARACTER = "LN1101"
    UNKNOWN_EXPRESSION = "LN1102"
    DUPLICATE_TESTIMONY = "LN1201"
    DUPLICATE_STATEMENT = "LN1202"
    UNKNOWN_EVIDENCE = "LN1203"
    INVALID_PRESENT_TARGET = "LN1204"
    EMPTY_TESTIMONY = "LN1205"
    INVALID_PRESS_TARGET = "LN1206"
    INVALID_WRONG_TARGET = "LN1207"
    INVALID_PENALTY = "LN1208"
    DUPLICATE_PRESENT_RULE = "LN1209"
    INVALID_TESTIMONY_ID = "LN1210"
    INVALID_STATEMENT_ID = "LN1211"
    MALFORMED_COMMAND = "LN1301"
    INVALID_COMMAND_CONTEXT = "LN1302"
    UNTERMINATED_TESTIMONY = "LN1303"
    UNKNOWN_BACKGROUND = "LN1401"
    UNKNOWN_BGM = "LN1402"
    UNKNOWN_SFX = "LN1403"
    INVALID_REGISTRY = "LN1404"
    DUPLICATE_LOCATION = "LN1501"
    INVALID_LOCATION_ID = "LN1502"
    UNKNOWN_LOCATION = "LN1503"
    DUPLICATE_HOTSPOT = "LN1504"
    INVALID_HOTSPOT_RECT = "LN1505"
    INVALID_LOCATION_CHILD_ID = "LN1506"
    UNKNOWN_INVESTIGATION_SCENE = "LN1507"
    UNKNOWN_LOCATION_CHARACTER = "LN1508"
    UNKNOWN_TALK_TOPIC = "LN1509"
    LOCATION_MISSING_BACKGROUND = "LN1510"
    DUPLICATE_TOPIC = "LN1511"
    DUPLICATE_PROCEDURE_CONTEXT = "LN1601"
    INVALID_PROCEDURE_ID = "LN1602"
    UNKNOWN_PROCEDURE_CONTEXT = "LN1603"
    DUPLICATE_PROCEDURE_ACTION = "LN1604"
    UNKNOWN_PROCEDURE_SCENE = "LN1605"
    INVALID_PROCEDURE_RESULT = "LN1606"
    EMPTY_PROCEDURE_CONTEXT = "LN1607"
    DUPLICATE_INSPECTION = "LN1701"
    UNKNOWN_INSPECTION_EVIDENCE = "LN1702"
    INVALID_INSPECTION_HOTSPOT = "LN1703"
    DUPLICATE_INSPECTION_HOTSPOT = "LN1704"
    INVALID_INSPECTION_RECT = "LN1705"
    UNKNOWN_INSPECTION_SCENE = "LN1706"
    UNKNOWN_INSPECTION_UNLOCK = "LN1707"
    EMPTY_INSPECTION = "LN1708"
    UNKNOWN_EVIDENCE_VERSION = "LN1709"
    # LN20xx: content catalog structure and duplicate IDs.
    DUPLICATE_CHARACTER = "LN2001"
    DUPLICATE_CHARACTER_NAME = "LN2002"
    DUPLICATE_EVIDENCE = "LN2003"
    DUPLICATE_BACKGROUND = "LN2004"
    DUPLICATE_BGM = "LN2005"
    DUPLICATE_SFX = "LN2006"
    DUPLICATE_EXPRESSION = "LN2007"
    DUPLICATE_PROCEDURE_CONTEXT_ID = "LN2008"
    DUPLICATE_PROCEDURE_ACTION_ID = "LN2009"
    DUPLICATE_INSPECTION_EVIDENCE = "LN2010"
    DUPLICATE_INSPECTION_HOTSPOT_ID = "LN2011"
    DUPLICATE_SCENE_ID = "LN2012"
    DUPLICATE_LOCATION_ID = "LN2013"
    DUPLICATE_TESTIMONY_ID = "LN2014"
    INVALID_CATALOG_ENTRY = "LN2015"
    UNREADABLE_CATALOG = "LN2016"
    UNSUPPORTED_FORMAT_VERSION = "LN2017"
    # LN21xx: content catalog references into the story or other catalogs.
    UNKNOWN_EXPRESSION_CHARACTER = "LN2101"
    UNKNOWN_PROCEDURE_ACTION_SCENE = "LN2102"
    UNKNOWN_PROCEDURE_REQUIRED_EVIDENCE = "LN2103"
    UNKNOWN_INSPECTION_EVIDENCE_ID = "LN2104"
    UNKNOWN_INSPECTION_HOTSPOT_SCENE = "LN2105"
    UNKNOWN_INSPECTION_UNLOCKED_BY = "LN2106"
    # LN22xx: story references into the content catalogs.
    UNKNOWN_CHARACTER_REFERENCE = "LN2201"
    UNKNOWN_EVIDENCE_REFERENCE = "LN2202"
    UNKNOWN_LOCATION_REFERENCE = "LN2203"
    UNKNOWN_EXPRESSION_REFERENCE = "LN2204"
    UNKNOWN_BACKGROUND_REFERENCE = "LN2205"
    UNKNOWN_BGM_REFERENCE = "LN2206"
    UNKNOWN_SFX_REFERENCE = "LN2207"
    UNKNOWN_PRESENT_VERSION = "LN2208"
    # LN23xx: asset existence. Convention misses are warnings unless
    # check-all runs with --strict-assets.
    MISSING_ASSET = "LN2301"
    MISSING_CONVENTION_ASSET = "LN2302"
    INVALID_ASSET_PATH = "LN2303"
    # LN24xx: investigation (location) references.
    UNKNOWN_INVESTIGATION_SCENE_REF = "LN2401"
    UNKNOWN_INVESTIGATION_CHARACTER_REF = "LN2402"
    UNKNOWN_TALK_TOPIC_REF = "LN2403"
    UNKNOWN_MOVE_TARGET = "LN2404"
    UNKNOWN_PRESENT_EVIDENCE = "LN2405"
    # LN25xx: the compiled build on disk versus the current sources. The runtime
    # reads story_build/, so an out-of-date build would silently ship old story.
    MISSING_STORY_BUILD = "LN2501"
    STALE_STORY_BUILD = "LN2502"


@dataclass(frozen=True, slots=True)
class SourceLocation:
    file: str
    line: int
    text: str = ""

    def to_json(self) -> dict[str, str | int]:
        return {"file": self.file, "line": self.line}


@dataclass(frozen=True, slots=True)
class Diagnostic:
    code: DiagnosticCode
    location: SourceLocation
    message: str
    severity: DiagnosticSeverity = DiagnosticSeverity.ERROR

    def render(self) -> str:
        display_file = (
            self.location.file
            if self.location.file.startswith(("data/", "story_src/", "<"))
            else f"story_src/{self.location.file}"
        )
        source = f"\n\n{self.location.text}" if self.location.text else ""
        return (
            f"{display_file}:{self.location.line}\n\n"
            f"{self.severity.value} {self.code.value}"
            f"{source}\n\n{self.message}"
        )


class CompilationError(Exception):
    def __init__(self, diagnostics: list[Diagnostic]) -> None:
        self.diagnostics = diagnostics
        super().__init__(f"Story compilation failed with {len(diagnostics)} error(s)")


def errors_of(diagnostics: Iterable[Diagnostic]) -> list[Diagnostic]:
    return [item for item in diagnostics if item.severity is DiagnosticSeverity.ERROR]


def warnings_of(diagnostics: Iterable[Diagnostic]) -> list[Diagnostic]:
    return [item for item in diagnostics if item.severity is DiagnosticSeverity.WARNING]
