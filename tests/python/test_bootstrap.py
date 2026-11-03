def test_story_compiler_package_is_importable() -> None:
    import tools.story_compiler

    assert tools.story_compiler.__doc__
