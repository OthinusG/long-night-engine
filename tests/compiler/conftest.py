import pytest

from tools.story_compiler.registry import (
    CharacterRegistry,
    ExpressionRegistry,
    IdRegistry,
    Registries,
)


@pytest.fixture
def registries() -> Registries:
    return Registries(
        characters=CharacterRegistry(
            {
                "辩护律师": "protagonist",
                "助手": "assistant",
                "证人": "witness",
                "法官": "judge",
                "陆长庚": "lu_changgeng",
                "赵廷禄": "zhao_tinglu",
                "沈星阑": "shen_xinglan",
            }
        ),
        expressions=ExpressionRegistry(
            {
                "protagonist": frozenset({"normal", "thinking", "confident"}),
                "assistant": frozenset({"normal", "thinking", "cheerful"}),
                "witness": frozenset({"normal", "nervous", "sweat"}),
                "judge": frozenset({"normal", "stern", "gavel"}),
                "lu_changgeng": frozenset({"calm", "thinking"}),
                "zhao_tinglu": frozenset({"calm", "angry"}),
                "shen_xinglan": frozenset({"calm", "guarded"}),
            }
        ),
        evidence=IdRegistry(
            frozenset({"crime_report", "attorney_badge", "night_duty_log", "paper_knife", "wrong_evidence"})
        ),
        backgrounds=IdRegistry(frozenset({"office", "courtroom_witness", "crime_scene", "county_court_day", "inn_room", "inn_hall"})),
        bgm=IdRegistry(frozenset({"bgm_trial", "bgm_testimony", "bgm_investigation", "testimony"})),
        sfx=IdRegistry(frozenset({"sfx_objection", "sfx_hold_it", "sfx_gavel", "gavel_light"})),
    )
