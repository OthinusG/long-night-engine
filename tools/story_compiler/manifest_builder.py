"""Deterministic content manifest for story_build/manifest.json.

The manifest is an index, not a copy of the catalogs: it lists the stable IDs a
build contains so the runtime can verify it loaded the build it expects. Sorted
keys and sorted ID lists only, no timestamps, no machine paths, no random IDs.
"""

from __future__ import annotations

from .content_loader import ContentCatalog
from .models import StoryDocument


def build_manifest(
    document: StoryDocument,
    catalog: ContentCatalog,
) -> dict[str, object]:
    return {
        "format_version": 1,
        "chapters": sorted(
            {
                scene.source.file.split("/", maxsplit=1)[0]
                for scene in document.scenes
                if "/" in scene.source.file
            }
        ),
        "scenes": sorted(scene.id for scene in document.scenes),
        "testimonies": sorted(testimony.id for testimony in document.testimonies),
        "characters": sorted(character.id for character in catalog.characters),
        "expressions": {
            character.id: sorted(catalog.expressions_of(character.id))
            for character in sorted(catalog.characters, key=lambda item: item.id)
        },
        "evidence": sorted(evidence.id for evidence in catalog.evidence),
        "evidence_versions": {
            evidence.id: sorted(evidence.versions)
            for evidence in sorted(catalog.evidence, key=lambda item: item.id)
        },
        "locations": sorted(location.id for location in document.locations),
        "backgrounds": sorted(background.id for background in catalog.backgrounds),
        "bgm": sorted(audio.id for audio in catalog.bgm),
        "sfx": sorted(audio.id for audio in catalog.sfx),
        "procedures": sorted(context.id for context in catalog.procedures),
        "inspections": sorted(
            inspection.evidence_id for inspection in catalog.inspections
        ),
    }
