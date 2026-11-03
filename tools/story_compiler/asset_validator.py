from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .content_loader import ContentCatalog
from .diagnostics import (
    Diagnostic,
    DiagnosticCode,
    DiagnosticSeverity,
    SourceLocation,
)

RESOURCE_PREFIX = "res://"


@dataclass(frozen=True, slots=True)
class AssetKindSpec:
    """One row of the frozen asset convention shared with AssetRegistry.gd."""

    name: str
    root: str
    extensions: tuple[str, ...]


BACKGROUND = AssetKindSpec(
    "background", "res://assets/backgrounds/", ("webp", "png", "jpg", "jpeg")
)
PORTRAIT = AssetKindSpec("portrait", "res://assets/portraits/", ("webp", "png"))
ICON = AssetKindSpec("icon", "res://assets/evidence/", ("webp", "png"))
DETAIL = AssetKindSpec("detail", "res://assets/evidence/detail/", ("webp", "png"))
BGM = AssetKindSpec("bgm", "res://assets/audio/bgm/", ("ogg", "mp3", "wav"))
SFX = AssetKindSpec("sfx", "res://assets/audio/sfx/", ("ogg", "wav", "mp3"))

ASSET_KINDS: tuple[AssetKindSpec, ...] = (
    BACKGROUND,
    PORTRAIT,
    ICON,
    DETAIL,
    BGM,
    SFX,
)


def candidate_paths(kind: AssetKindSpec, asset_id: str) -> tuple[str, ...]:
    return tuple(f"{kind.root}{asset_id}.{extension}" for extension in kind.extensions)


def portrait_id(character_id: str, expression_id: str) -> str:
    return f"{character_id}_{expression_id}"


def is_resource_path(path: str) -> bool:
    return path.startswith(RESOURCE_PREFIX) and len(path) > len(RESOURCE_PREFIX)


def resource_exists(repo_root: Path, resource_path: str) -> bool:
    if not is_resource_path(resource_path):
        return False
    return (repo_root / resource_path[len(RESOURCE_PREFIX) :]).is_file()


def resolve(repo_root: Path, kind: AssetKindSpec, asset_id: str) -> str:
    """First existing convention path, or "" when the asset is still missing."""
    for candidate in candidate_paths(kind, asset_id):
        if resource_exists(repo_root, candidate):
            return candidate
    return ""


def validate_assets(
    repo_root: Path,
    catalog: ContentCatalog,
    *,
    strict: bool = False,
) -> list[Diagnostic]:
    """Check every catalog-visible asset reference against the convention.

    An authored explicit path must exist (ERROR). A convention-only ID that is
    missing is a WARNING because placeholder presentation ships before the art;
    `strict=True` turns those misses into errors for CI.
    """
    diagnostics: list[Diagnostic] = []
    for background in catalog.backgrounds:
        _check(
            repo_root,
            BACKGROUND,
            background.id,
            background.path,
            background.source,
            diagnostics,
            strict,
        )
    for audio in catalog.bgm:
        _check(repo_root, BGM, audio.id, audio.path, audio.source, diagnostics, strict)
    for audio in catalog.sfx:
        _check(repo_root, SFX, audio.id, audio.path, audio.source, diagnostics, strict)
    for expression in catalog.expressions:
        character = catalog.character(expression.character_id)
        authored = expression.portrait or (
            character.portraits.get(expression.id, "") if character is not None else ""
        )
        _check(
            repo_root,
            PORTRAIT,
            portrait_id(expression.character_id, expression.id),
            authored,
            expression.source,
            diagnostics,
            strict,
        )
    for evidence in catalog.evidence:
        _check(repo_root, ICON, evidence.id, evidence.icon, evidence.source, diagnostics, strict)
        if evidence.detail_image:
            _check(
                repo_root,
                DETAIL,
                evidence.id,
                evidence.detail_image,
                evidence.source,
                diagnostics,
                strict,
            )
    for inspection in catalog.inspections:
        if not inspection.image:
            continue
        evidence = catalog.evidence_def(inspection.evidence_id)
        if evidence is not None and evidence.detail_image:
            # The authored evidence detail path already covers this evidence.
            continue
        _check(
            repo_root,
            DETAIL,
            inspection.image,
            "",
            inspection.source or SourceLocation("data/evidence_inspections.json", 1),
            diagnostics,
            strict,
        )
    return diagnostics


def _check(
    repo_root: Path,
    kind: AssetKindSpec,
    asset_id: str,
    authored_path: str,
    source: SourceLocation,
    diagnostics: list[Diagnostic],
    strict: bool,
) -> None:
    if authored_path:
        if not is_resource_path(authored_path):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.INVALID_ASSET_PATH,
                    source,
                    f"Invalid {kind.name} path for '{asset_id}'. "
                    f"Found: {authored_path!r}; expected: a res:// path.",
                )
            )
            return
        if not resource_exists(repo_root, authored_path):
            diagnostics.append(
                Diagnostic(
                    DiagnosticCode.MISSING_ASSET,
                    source,
                    f"Missing {kind.name} asset for '{asset_id}'. "
                    f"Found: none; expected the authored path {authored_path} to exist.",
                )
            )
        return

    candidates = candidate_paths(kind, asset_id)
    if any(resource_exists(repo_root, candidate) for candidate in candidates):
        return
    message = (
        f"Missing {kind.name} asset for '{asset_id}'. "
        f"Found: none; expected one of: {', '.join(candidates)}."
    )
    if strict:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.MISSING_ASSET,
                source,
                f"{message} (promoted by --strict-assets)",
            )
        )
    else:
        diagnostics.append(
            Diagnostic(
                DiagnosticCode.MISSING_CONVENTION_ASSET,
                source,
                f"{message} Placeholder presentation is used until the asset lands.",
                DiagnosticSeverity.WARNING,
            )
        )
