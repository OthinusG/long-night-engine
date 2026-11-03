from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import check_all
from .compiler import build_project, validate_project
from .diagnostics import CompilationError


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m tools.story_compiler")
    parser.add_argument("command", choices=("validate", "build", "check-all"))
    parser.add_argument(
        "--strict-assets",
        action="store_true",
        help="check-all: treat missing convention assets as errors",
    )
    parser.add_argument(
        "--skip-build-check",
        action="store_true",
        help="check-all: do not compare story_build/ with the current sources",
    )
    args = parser.parse_args(argv)

    root = Path.cwd()
    if args.command == "check-all":
        return check_all.main(
            root,
            strict_assets=args.strict_assets,
            check_build=not args.skip_build_check,
        )

    try:
        if args.command == "validate":
            summary = validate_project(root / "story_src", root / "data")
            print(
                f"Validated {summary.scene_count} scenes and "
                f"{summary.testimony_count} {_testimony_label(summary.testimony_count)}."
            )
        else:
            summary = build_project(
                root / "story_src",
                root / "data",
                root / "story_build",
            )
            print(
                f"Built {summary.scene_count} scenes and "
                f"{summary.testimony_count} {_testimony_label(summary.testimony_count)} "
                "into story_build/."
            )
    except CompilationError as error:
        print("\n\n".join(item.render() for item in error.diagnostics), file=sys.stderr)
        return 1
    return 0


def _testimony_label(count: int) -> str:
    return "testimony" if count == 1 else "testimonies"


if __name__ == "__main__":
    raise SystemExit(main())
