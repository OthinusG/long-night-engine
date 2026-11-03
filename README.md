# Long Night Engine (Godot 4)

A clean, modular, typed Godot 4.7.2 implementation of a classic courtroom investigation and trial engine inspired by *Ace Attorney* (逆转裁判).

This repository contains the **pure engine framework**, decoupled from any specific story content, copyrighted art, or proprietary audio assets.

---

## Architecture Overview

The engine strictly adheres to data-driven, unidirectional flow:

```text
Markdown Story Source (story_src/)
              ↓
Python Story Compiler (tools/story_compiler/)
              ↓
Validated Story IR JSON (story_build/)
              ↓
           StoryVM
       ┌──────┴──────┐
  CourtRuntime  InvestigationRuntime  ProcedureRuntime  InspectionRuntime
       └──────┬──────┘
       Presentation Layer (FXDirector, CharacterStage, Audio)
              ↓
         Godot UI Nodes
```

### Key Principles

1. **Zero Story Hardcoding**: Characters, expressions, locations, evidence, testimonies, and inspection hotspots are defined entirely via Markdown DSL and structured JSON (`data/`).
2. **UI is Never Authoritative**: Game state lives strictly in typed domain objects (`GameState`, `EvidenceState`, `TestimonySession`, `InvestigationState`). UI only reads domain state and dispatches user actions.
3. **Graceful Asset Fallbacks**: Absence of character portraits, backgrounds, audio tracks, or special cut-in textures automatically degrades gracefully (e.g. typography cut-ins, missing art placeholders, silent fallback) without crashing or hanging.
4. **Call / Return Branches**: Pressing testimony statements, examining investigation hotspots, presenting evidence, and procedural crises run via explicit `CALL` and `RETURN` branch semantics rather than monolithic gotos or coroutine nesting.

---

## Features

- **Story DSL & Compiler**:
  - Author story chapters in intuitive, human-readable Markdown.
  - Compile-time static analysis: validates scene references, jump targets, testimony completeness, asset references, and evidence bindings before running the game.
- **Courtroom System (`CourtRuntime`)**:
  - Testimony preview loop & statement-by-statement navigation.
  - **Press (威慑)**: temporary branch execution with seamless stack restoration.
  - **Present (举证)**: evidence validation, multi-version gating, penalty deduction, and breakthrough branches.
  - Health / Penalty bar with customizable deduction rates.
- **Investigation System (`InvestigationRuntime`)**:
  - Location graph with movement constraints.
  - **Examine (调查)**: normalized coordinate bounding boxes (`[x, y, w, h]`) resolution across resolutions.
  - **Talk (交谈)**: dynamic topic unlocking via `@talk_unlock`.
  - **Present (出示)**: character-specific reactions with generic fallbacks.
  - Investigation completion guards ensuring all required clues are discovered before court transitions.
- **Evidence Detail Inspection (`EvidenceInspectionRuntime`)**:
  - Normalized interactive inspection hotspots on evidence items.
  - Evidence version transitions (e.g., upgrading an item after discovering critical details).
- **Procedural Crisis Support (`ProcedureRuntime`)**:
  - Branching procedural arguments and choices during high-stakes courtroom moments.
- **Story Debugger**:
  - Full in-game debug overlay: scene jump, testimony skip, dynamic flag manipulation, evidence injection, and hotspot state toggling.
- **Persistence System (`SaveManager`)**:
  - Versioned JSON saves capturing only typed domain states (Story, Court, Investigation, Evidence, Flags, Settings).

---

## Directory Layout

```text
long-night-engine/
├── assets/                  # Minimal fallback placeholders
├── data/                    # Engine definitions (schema templates)
│   ├── characters.json      # Archetype characters (protagonist, prosecutor, witness, judge, assistant)
│   ├── expressions.json     # Standard expressions (normal, thinking, point, sweat, etc.)
│   ├── backgrounds.json     # Generic scene slots
│   ├── bgm.json / sfx.json  # Audio cues
│   ├── evidence.json        # Template evidence definitions & version rules
│   ├── evidence_inspections.json # Hotspot inspection configs
│   ├── procedure.json       # Procedural crisis contexts
│   └── gallery.json         # CG / Music gallery unlocks
├── game/                    # Godot GDScript runtime
│   ├── audio/               # Audio managers & volume routing
│   ├── commands/            # StoryVM instruction handlers
│   ├── content/             # Asset registry & loader
│   ├── core/                # StoryVM, GameState, GameCoordinator, StoryProgram
│   ├── court/               # CourtRuntime & Testimony models
│   ├── debug/               # StoryDebugger UI & tools
│   ├── input/               # InputRouter & action bindings
│   ├── investigation/       # InvestigationRuntime & models
│   ├── inspection/          # Evidence detail inspection runtime
│   ├── presentation/        # FXDirector, character staging, screen shakes
│   ├── procedure/           # Procedural crisis runtime
│   ├── save/                # SaveManager & serialization
│   ├── settings/            # User settings & configuration
│   └── ui/                  # Clean decouple UI scenes & scripts
├── project.godot            # Godot 4.7.2 project file
├── pyproject.toml           # Python compiler configuration
├── scripts/                 # CLI validation & build scripts
│   ├── build_story.sh       # Compiles Markdown to Story IR
│   ├── check.sh             # Full CI check (compiler + pytest + Godot headless)
│   └── test.sh              # Runs automated test suites
├── story_build/             # Compiled story IR (story.json & manifest.json)
├── story_src/               # Authored Markdown story DSL source
│   └── demo/main.md         # Reference demo story showing all engine features
├── tests/                   # Automated tests
│   ├── compiler/            # Pytest test suite for DSL compiler
│   └── godot/               # Godot headless test suite for runtime systems
└── tools/
    └── story_compiler/      # Python story compiler implementation
```

---

## Quickstart

### Requirements

- **Godot Engine**: `v4.7.2.stable`
- **Python**: `3.10+` with `pytest` installed

### 1. Build the Story IR

To compile story sources from `story_src/` into `story_build/story.json`:

```bash
./scripts/build_story.sh
```

### 2. Run All Automated Checks

Runs the compiler validations, pytest suite, and all headless Godot runtime tests:

```bash
./scripts/check.sh
```

### 3. Run the Game

Open the repository root in Godot 4.7.2 or run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

---

## Writing Stories (DSL Guide)

Story sources live in `story_src/` as `.md` files.

### Basic Dialogue & Presentation

```md
#scene scene_office_start

@bg office
@bgm bgm_investigation
@char protagonist center normal

辩护律师[normal]:
今天是我接手案件的第一天。

@char protagonist center point
@sfx sfx_desk_slam

辩护律师[point]:
我一定会查明真相！

@goto scene_investigation
```

### Investigation Scene

```md
#scene scene_investigation
@investigation location_office

#location location_office
@name 律师事务所
@bg office
@character 助手
@move -> location_crime_scene
@present attorney_badge -> scene_present_badge

## topic case_overview
@title 关于案情
@scene scene_talk_case

## topic secret_clue
@title 隐藏线索
@scene scene_talk_secret
@locked
```

### Courtroom & Cross-Examination

```md
#scene scene_court_trial

@bg courtroom_witness
@char witness center nervous

证人[nervous]:
我当时确实看到了被告人！

@testimony testimony_case_01
@penalty 20
@wrong -> scene_court_penalty

## statement stmt_01
证人[normal]:
昨晚九点，我路过现场门前。
@press -> scene_press_stmt_01

## statement stmt_02
证人[nervous]:
屋里很黑，但我清楚看到了凶手。
@press -> scene_press_stmt_02
@present crime_report -> scene_break_testimony

@endtestimony
```

For press branches and correct presentation branches, use `@return` to return control to the testimony loop. When the testimony is broken, `@endtestimony` will continue to the subsequent scene.

---

## License

The engine source code is released under the [MIT License](LICENSE).

Bundled third-party assets:

- `assets/fonts/SourceHanSansSC-Regular.otf` — Source Han Sans SC, Copyright 2014-2025 Adobe, licensed under the [SIL Open Font License 1.1](assets/fonts/LICENSE-OFL.txt).

Designed for easy integration into custom narrative and adventure games.
