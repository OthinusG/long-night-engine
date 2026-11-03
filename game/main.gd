class_name Main
extends Control

## Player input, UI state and the wiring between the runtimes and the
## presentation layer. Gameplay truth lives in GameState and the runtimes;
## "how it looks" lives in PresentationCoordinator.

enum UIState {
	DIALOGUE,
	COURT,
	COURT_RECORD,
	INVESTIGATION,
	INVESTIGATION_RECORD,
	PROCEDURE,
	INSPECTION,
	MENU,
	TITLE,
	PAUSE_MENU,
	SAVE_LOAD,
	GALLERY,
	BLOCKED,
	GAMEOVER,
	FINISHED,
	CREDITS,
	ERROR,
}

const STORY_PATH: String = "res://story_build/story.json"
const MANIFEST_PATH: String = "res://story_build/manifest.json"
const EVIDENCE_PATH: String = "res://data/evidence.json"
const PROCEDURE_PATH: String = "res://data/procedure.json"
const INSPECTION_PATH: String = "res://data/evidence_inspections.json"
const DATA_ROOT: String = "res://data"
## scripts/smoke_test.sh runs the shipped build with this flag.
const SMOKE_TEST_ARG: String = "--smoke-test"
const FEEDBACK_DURATION: float = 2.5
const COURT_TITLE_DURATION: float = 2.0

@onready var background_view: ColorRect = %BackgroundView
@onready var background_label: Label = %BackgroundLabel
@onready var game_title_label: Label = %GameTitle
@onready var character_stage_root: Control = %CharacterStage
@onready var camera: Camera2D = %Camera
@onready var dialogue_ui: DialogueUI = %DialogueUI
@onready var court_ui: CourtUI = %CourtUI
@onready var evidence_panel: EvidencePanel = %EvidencePanel
@onready var evidence_inspection_ui: EvidenceInspectionUI = %EvidenceInspectionUI
@onready var investigation_ui: InvestigationUI = %InvestigationUI
@onready var procedure_panel: ProcedurePanel = %ProcedurePanel
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var save_load_panel: SaveLoadPanel = %SaveLoadPanel
@onready var gallery_ui: GalleryUI = %GalleryUI
@onready var title_screen: TitleScreen = %TitleScreen
@onready var settings_ui: SettingsUI = %SettingsUI
@onready var debug_overlay: DebugOverlay = %DebugOverlay
@onready var menu_gear_button: Button = %MenuGearButton
@onready var auto_button: Button = %AutoButton
@onready var feedback_label: Label = %FeedbackLabel

@onready var status_label: Label = %StatusLabel


var ui_state: UIState = UIState.BLOCKED
var game_state: GameState
var story_vm: StoryVM
var court_runtime: CourtRuntime
var investigation_runtime: InvestigationRuntime
var procedure_runtime: ProcedureRuntime
var inspection_runtime: EvidenceInspectionRuntime
var evidence_repository: EvidenceRepository
var inspection_repository: EvidenceInspectionRepository
var content_registry: ContentRegistry
var asset_registry: AssetRegistry
var content_manifest: ContentManifest
var presentation: PresentationCoordinator
var coordinator: GameCoordinator
var save_manager: SaveManager
var story_debugger: StoryDebugger
var settings_manager: SettingsManager
var gallery_manager: GalleryManager
## Held only while --smoke-test runs, so the coroutine cannot be collected.
var smoke_runner: SmokeRunner
var input_router: InputRouter

var _advance_locked: bool = false
var _gameplay_state_before_pause: UIState = UIState.BLOCKED
var _subpanel_caller: UIState = UIState.TITLE
var _auto_play: bool = false
var _auto_timer: float = 0.0
var _dialogue_read: bool = false
var _ending_timer: float = -1.0
var _court_intro_timer: float = -1.0
var _court_preview_visible: bool = false
var _questioning_title_timer: float = -1.0
var _questioning_transition_ready: bool = false
var _fast_forward_timer: float = 0.0
var _feedback_timer: float = -1.0


func _ready() -> void:
	input_router = InputRouter.new()
	input_router.action_requested.connect(_on_input_action)
	settings_manager = SettingsManager.new()
	gallery_manager = GalleryManager.new()
	if not _initialize_runtime():
		return
	_initialize_presentation()
	_connect_ui()
	_connect_runtime()
	gallery_ui.configure(gallery_manager)
	settings_manager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed(settings_manager.settings)
	settings_ui.configure(settings_manager)
	# SettingsManager is constructed before the scene is fully active; apply the
	# persisted native window state again once the main scene owns the window.
	settings_manager.apply_display()

	settings_ui.closed.connect(_close_settings)
	evidence_panel.configure(evidence_repository, game_state, inspection_repository)
	if OS.is_debug_build():
		debug_overlay.configure(story_debugger)
		story_debugger.state_changed.connect(_refresh_from_state)
	_update_auto_button_visuals()
	_set_ui_state(UIState.BLOCKED)
	story_vm.start(story_vm.program.entry_scene)
	if _is_smoke_test():
		smoke_runner = SmokeRunner.new(self)
		smoke_runner.run()
	else:
		open_title_screen()


func _unhandled_input(event: InputEvent) -> void:
	if input_router != null and input_router.handle_event(event):
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if ui_state == UIState.DIALOGUE and presentation != null and event is InputEventMouseButton:
		var notice_mouse_event := event as InputEventMouseButton
		if notice_mouse_event.pressed and notice_mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if presentation.fx.dismiss_notice():
				get_viewport().set_input_as_handled()
				return
	# GAMEOVER is intentionally outside InputRouter's gameplay contexts. Handle
	# the mouse at the root so child panels cannot consume the return action.
	if ui_state != UIState.GAMEOVER or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		return_to_title()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if game_state != null:
		game_state.playtime_seconds += delta
	if _feedback_timer >= 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0:
			_clear_feedback()
	if presentation != null:
		presentation.tick(delta)
		if ui_state == UIState.DIALOGUE and presentation.dialogue != null and not presentation.dialogue.is_revealing():
			_dialogue_read = true
	if ui_state == UIState.BLOCKED and story_vm != null:
		if story_vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
			_set_ui_state(UIState.DIALOGUE)
	_process_auto_play(delta)
	_process_ending(delta)
	if court_runtime != null and court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW and not _court_preview_visible and _court_intro_timer < 0.0:
		_court_intro_timer = 0.0
	_process_court_intro(delta)
	_process_questioning_title(delta)
	_process_fast_forward(delta)


func _initialize_runtime() -> bool:
	var loader := StoryProgramLoader.new()
	var program: StoryProgram = loader.load_file(STORY_PATH)
	if program == null:
		return _fatal(loader.error_message)

	content_manifest = ContentManifest.new()
	if not content_manifest.load_file(MANIFEST_PATH):
		return _fatal(content_manifest.error_message)

	evidence_repository = EvidenceRepository.new()
	if not evidence_repository.load_file(EVIDENCE_PATH):
		return _fatal(evidence_repository.error_message)

	content_registry = ContentRegistry.new()
	if not content_registry.load_catalogs(DATA_ROOT):
		return _fatal(content_registry.error_message)
	content_registry.attach(program, evidence_repository)
	asset_registry = AssetRegistry.new(content_registry)

	game_state = GameState.new()
	story_vm = StoryVM.new(game_state)
	court_runtime = CourtRuntime.new(game_state, evidence_repository)
	investigation_runtime = InvestigationRuntime.new(game_state, program, evidence_repository)

	var procedure_repository := ProcedureRepository.new()
	if not procedure_repository.load_file(PROCEDURE_PATH):
		return _fatal(procedure_repository.error_message)
	procedure_runtime = ProcedureRuntime.new(game_state, procedure_repository)

	inspection_repository = EvidenceInspectionRepository.new()
	if not inspection_repository.load_file(INSPECTION_PATH):
		return _fatal(inspection_repository.error_message)
	inspection_runtime = EvidenceInspectionRuntime.new(game_state, inspection_repository)

	coordinator = GameCoordinator.new(
		story_vm,
		court_runtime,
		investigation_runtime,
		procedure_runtime,
		inspection_runtime,
	)
	story_vm.load_program(program)
	save_manager = SaveManager.new(
		game_state,
		story_vm,
		court_runtime,
		investigation_runtime,
		procedure_runtime,
		program,
		evidence_repository,
	)
	story_debugger = StoryDebugger.new(
		game_state,
		story_vm,
		court_runtime,
		investigation_runtime,
		procedure_runtime,
		inspection_runtime,
		program,
		evidence_repository,
	)
	# Debug presets are development content and are not shipped in release
	# exports; a broken file must never stop the game from running.
	if OS.is_debug_build() and not story_debugger.load_presets():
		push_error("[Main] %s" % story_debugger.error_message)
	return true


func _initialize_presentation() -> void:
	presentation = PresentationCoordinator.new(
		self,
		background_view,
		background_label,
		character_stage_root,
		camera,
		content_registry,
		asset_registry,
	)
	presentation.bind_ui(dialogue_ui, court_ui)
	presentation.connect_runtimes(story_vm, court_runtime, investigation_runtime)
	presentation.dialogue_presented.connect(_on_dialogue_presented)
	presentation.court_presented.connect(_on_court_presented)
	presentation.investigation_presented.connect(_on_investigation_presented)
	presentation.feedback_changed.connect(_on_feedback_changed)
	presentation.fx.notice_dismissed.connect(_on_notice_dismissed)
	presentation.presentation_changed.connect(_refresh_status)
	# The debugger is built with the runtime, before any node exists; it only
	# reads presentation, so it can be handed the layer once it is built.
	story_debugger.presentation = presentation


func _connect_ui() -> void:
	dialogue_ui.advance_requested.connect(_advance_dialogue)
	court_ui.previous_requested.connect(_previous_statement)
	court_ui.next_requested.connect(_next_statement)
	court_ui.press_requested.connect(_press_statement)
	court_ui.present_requested.connect(_open_court_record)
	evidence_panel.present_requested.connect(_present_evidence)
	evidence_panel.inspect_requested.connect(_open_inspection)
	evidence_panel.back_requested.connect(_close_court_record)
	evidence_inspection_ui.hotspot_selected.connect(_inspection_hotspot)
	evidence_inspection_ui.back_requested.connect(_close_inspection)
	procedure_panel.action_selected.connect(_procedure_select)
	investigation_ui.examine_requested.connect(_investigation_examine)
	investigation_ui.talk_requested.connect(_investigation_talk)
	investigation_ui.move_requested.connect(_investigation_move)
	investigation_ui.present_requested.connect(_open_investigation_record)
	investigation_ui.mode_requested.connect(_investigation_mode)

	title_screen.start_game_requested.connect(start_new_game)
	title_screen.continue_game_requested.connect(open_load_panel_from_title)
	title_screen.gallery_requested.connect(open_gallery)
	title_screen.settings_requested.connect(_open_settings)
	title_screen.quit_requested.connect(func() -> void: get_tree().quit())

	pause_menu.resume_requested.connect(_close_pause_menu)
	pause_menu.save_requested.connect(open_save_panel)
	pause_menu.load_requested.connect(open_load_panel)
	pause_menu.settings_requested.connect(_open_settings)
	pause_menu.title_requested.connect(return_to_title)
	pause_menu.quit_requested.connect(func() -> void: get_tree().quit())

	menu_gear_button.pressed.connect(_toggle_pause_menu)
	auto_button.pressed.connect(_toggle_auto_play)

	save_load_panel.save_slot_selected.connect(func(slot: int) -> void:

		request_save(slot)
	)
	save_load_panel.load_slot_selected.connect(func(slot: int) -> void:
		if request_load(slot):
			pause_menu.close_menu()
			title_screen.close_title()
			save_load_panel.close_panel()
			_gameplay_state_before_pause = ui_state
	)
	save_load_panel.closed.connect(_close_save_load_panel)

	gallery_ui.closed.connect(_close_gallery)


func _connect_runtime() -> void:
	story_vm.runtime_error.connect(_fatal)
	story_vm.background_requested.connect(_on_story_background_requested)
	story_vm.bgm_requested.connect(_on_story_bgm_requested)
	court_runtime.testimony_started.connect(_on_testimony_started)
	court_runtime.preview_statement_changed.connect(_on_preview_statement_changed)
	court_runtime.preview_finished.connect(_on_preview_finished)
	court_runtime.testimony_suspended.connect(_on_testimony_suspended)
	court_runtime.testimony_resumed.connect(_on_testimony_resumed)
	court_runtime.testimony_completed.connect(_on_testimony_completed)
	court_runtime.court_failed.connect(_on_court_failed)
	investigation_runtime.investigation_started.connect(_on_investigation_started)
	investigation_runtime.location_changed.connect(_on_location_changed)
	investigation_runtime.branch_resumed.connect(_on_investigation_branch_resumed)
	investigation_runtime.investigation_completed.connect(_on_investigation_completed)
	investigation_runtime.action_rejected.connect(_on_investigation_action_rejected)
	investigation_runtime.tools_changed.connect(_refresh_investigation)
	procedure_runtime.procedure_started.connect(_on_procedure_started)
	procedure_runtime.procedure_completed.connect(_on_procedure_completed)
	procedure_runtime.action_resolved.connect(_on_procedure_action_resolved)
	procedure_runtime.branch_resumed.connect(_on_procedure_resumed)
	inspection_runtime.inspection_opened.connect(_on_inspection_opened)
	inspection_runtime.hotspot_inspected.connect(_on_hotspot_inspected)
	inspection_runtime.branch_resumed.connect(_on_inspection_branch_resumed)
	inspection_runtime.inspection_completed.connect(_on_inspection_completed)


func _on_story_background_requested(background_id: StringName) -> void:
	if gallery_manager != null and (String(background_id).begins_with("cg_") or String(background_id).begins_with("bg_")):
		gallery_manager.unlock_cg(String(background_id))


func _on_story_bgm_requested(bgm_id: StringName) -> void:
	if gallery_manager != null:
		gallery_manager.unlock_bgm(String(bgm_id))



func _on_input_action(action: StringName) -> void:
	match action:
		&"story_advance":
			_advance_dialogue()
		&"auto_play":
			_toggle_auto_play()
		&"fast_forward":
			_fast_forward_dialogue()
		&"court_next":
			_next_statement()
		&"court_previous":
			_previous_statement()
		&"court_press":
			_press_statement()
		&"court_present", &"court_record":
			_open_court_record()
		&"investigation_examine":
			_investigation_mode(InvestigationState.Mode.LOCATION_ACTIVE)
		&"investigation_talk":
			_investigation_mode(InvestigationState.Mode.TALK_MODE)
		&"investigation_move":
			_investigation_mode(InvestigationState.Mode.MOVE_MODE)
		&"investigation_present":
			_open_investigation_record()
		&"ui_cancel":
			_cancel()
		&"pause":
			_toggle_pause_menu()
		&"debug_story_tools":
			# Release builds must not expose the Story Debugger (spec 14.11).
			if OS.is_debug_build():
				debug_overlay.toggle()
		_:
			pass


## Escape closes whatever panel is on top; it never leaves focus nowhere.
func _cancel() -> void:
	match ui_state:
		UIState.COURT_RECORD, UIState.INVESTIGATION_RECORD:
			_close_court_record()
		UIState.INSPECTION:
			_close_inspection()
		UIState.MENU:
			_close_settings()
		UIState.SAVE_LOAD:
			_close_save_load_panel()
		UIState.GALLERY:
			if gallery_ui != null and gallery_ui.is_preview_open():
				gallery_ui.close_preview()
			else:
				_close_gallery()
		UIState.PAUSE_MENU:
			_close_pause_menu()
		UIState.DIALOGUE, UIState.COURT, UIState.INVESTIGATION, UIState.PROCEDURE:
			_open_pause_menu()
		_:
			pass


func _toggle_pause_menu() -> void:
	if ui_state == UIState.PAUSE_MENU:
		_close_pause_menu()
	elif ui_state in [UIState.MENU, UIState.SAVE_LOAD, UIState.GALLERY]:
		_cancel()
	elif ui_state in [
		UIState.DIALOGUE,
		UIState.COURT,
		UIState.INVESTIGATION,
		UIState.PROCEDURE,
		UIState.COURT_RECORD,
		UIState.INVESTIGATION_RECORD,
		UIState.INSPECTION,
	]:
		_open_pause_menu()


func _open_pause_menu() -> void:
	if ui_state in [UIState.TITLE, UIState.PAUSE_MENU, UIState.FINISHED, UIState.ERROR]:
		return
	if ui_state not in [UIState.MENU, UIState.SAVE_LOAD, UIState.GALLERY]:
		_gameplay_state_before_pause = ui_state
	pause_menu.set_save_enabled(save_manager != null and save_manager.can_save())
	pause_menu.open_menu()
	_set_ui_state(UIState.PAUSE_MENU)


func _close_pause_menu() -> void:
	if ui_state != UIState.PAUSE_MENU:
		return
	pause_menu.close_menu()
	if _gameplay_state_before_pause in [
		UIState.DIALOGUE,
		UIState.COURT,
		UIState.COURT_RECORD,
		UIState.INVESTIGATION,
		UIState.INVESTIGATION_RECORD,
		UIState.PROCEDURE,
		UIState.INSPECTION,
	]:
		_set_ui_state(_gameplay_state_before_pause)
	else:
		_refresh_from_state()


func start_new_game() -> void:
	title_screen.close_title()
	_set_ui_state(UIState.BLOCKED)
	_gameplay_state_before_pause = UIState.BLOCKED
	_auto_play = false
	_auto_timer = 0.0
	_ending_timer = -1.0
	_clear_feedback()
	if presentation != null:
		presentation.stage.clear_stage()
		presentation.background.set_court_active(false)
	_update_auto_button_visuals()
	court_runtime.clear_runtime()
	investigation_runtime.clear_runtime()
	if procedure_runtime != null:
		procedure_runtime.clear_runtime()
	if inspection_runtime != null and inspection_runtime.is_open():
		inspection_runtime.close()
	game_state.reset()
	story_vm.start(story_vm.program.entry_scene)



func open_title_screen() -> void:
	var has_saves := false
	if save_manager != null:
		for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
			if save_manager.has_slot(slot):
				has_saves = true
				break
	pause_menu.close_menu()
	save_load_panel.close_panel()
	gallery_ui.close_gallery()
	settings_ui.close_panel()
	_gameplay_state_before_pause = UIState.BLOCKED
	_auto_play = false
	_auto_timer = 0.0
	_ending_timer = -1.0
	_clear_feedback()
	if presentation != null:
		presentation.stage.clear_stage()
	_update_auto_button_visuals()
	title_screen.open_title(has_saves)
	_set_ui_state(UIState.TITLE)


func open_load_panel_from_title() -> void:
	_subpanel_caller = UIState.TITLE
	save_load_panel.open_panel(SaveLoadPanel.Mode.LOAD, save_manager)
	_set_ui_state(UIState.SAVE_LOAD)


func open_save_panel() -> void:
	_subpanel_caller = UIState.PAUSE_MENU
	save_load_panel.open_panel(SaveLoadPanel.Mode.SAVE, save_manager)
	_set_ui_state(UIState.SAVE_LOAD)


func open_load_panel() -> void:
	_subpanel_caller = UIState.PAUSE_MENU
	save_load_panel.open_panel(SaveLoadPanel.Mode.LOAD, save_manager)
	_set_ui_state(UIState.SAVE_LOAD)


func _close_save_load_panel() -> void:
	save_load_panel.close_panel()
	if _subpanel_caller == UIState.TITLE:
		open_title_screen()
	else:
		_open_pause_menu()


func open_gallery() -> void:
	_subpanel_caller = ui_state
	gallery_ui.open_gallery()
	_set_ui_state(UIState.GALLERY)


func _close_gallery() -> void:
	gallery_ui.close_gallery()
	if _subpanel_caller == UIState.TITLE:
		open_title_screen()
	elif _subpanel_caller == UIState.PAUSE_MENU:
		_open_pause_menu()
	else:
		_set_ui_state(_subpanel_caller)


func return_to_title() -> void:
	pause_menu.close_menu()
	save_load_panel.close_panel()
	evidence_panel.close_panel()
	settings_ui.close_panel()
	_gameplay_state_before_pause = UIState.BLOCKED
	_subpanel_caller = UIState.TITLE
	if court_runtime != null and court_runtime.has_active_testimony():
		court_runtime.abort_testimony()

	if investigation_runtime != null and investigation_runtime.state.active:
		investigation_runtime.end_investigation()
	open_title_screen()


func _open_settings() -> void:
	if ui_state == UIState.MENU:
		_close_settings()
		return
	if ui_state in [UIState.FINISHED, UIState.ERROR]:
		return
	_subpanel_caller = ui_state
	settings_ui.open_panel()
	_set_ui_state(UIState.MENU)


func _close_settings() -> void:
	if ui_state != UIState.MENU:
		return
	settings_ui.close_panel()
	if _subpanel_caller == UIState.TITLE:
		open_title_screen()
	elif _subpanel_caller == UIState.PAUSE_MENU:
		_open_pause_menu()
	else:
		_set_ui_state(_subpanel_caller)


## Text speed only affects how dialogue is revealed.
func _on_settings_changed(settings: GameSettings) -> void:
	if presentation != null:
		presentation.apply_text_speed(settings.text_speed)


func _on_dialogue_presented() -> void:
	_advance_locked = false
	_dialogue_read = presentation == null or presentation.dialogue == null or not presentation.dialogue.is_revealing()
	if court_runtime.runtime_state != CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		_set_ui_state(UIState.DIALOGUE)
		if presentation != null and presentation.fx.has_dismissible_notice():
			dialogue_ui.set_active(false)


func _on_court_presented() -> void:
	_set_ui_state(UIState.COURT)


func _on_investigation_presented() -> void:
	_set_ui_state(UIState.INVESTIGATION)


func _on_feedback_changed(text: String) -> void:
	_set_feedback(text)
	if text in ["威慑", "反对"] and presentation != null:
		dialogue_ui.set_active(false)


func _on_notice_dismissed() -> void:
	if ui_state != UIState.DIALOGUE or story_vm == null:
		return
	dialogue_ui.set_active(true)
	dialogue_ui.continue_button.grab_focus()
	_dialogue_read = presentation.dialogue == null or not presentation.dialogue.is_revealing()


func _advance_dialogue() -> void:
	if ui_state != UIState.DIALOGUE or _advance_locked or debug_overlay.visible:
		return
	if presentation != null and presentation.fx.dismiss_notice():
		_auto_timer = 0.0
		return
	if court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		if presentation.dialogue.is_revealing():
			presentation.dialogue.complete_reveal()
			_dialogue_read = true
			_auto_timer = 0.0
			return
		court_runtime.advance_preview()
		_auto_timer = 0.0
		return
	if story_vm.game_state.story.runtime_state != StoryState.RuntimeState.WAIT_DIALOGUE:
		return
	if presentation.dialogue.is_revealing():
		# The first input completes the line instead of skipping it.
		presentation.dialogue.complete_reveal()
		_dialogue_read = true
		_auto_timer = 0.0
		return
	_auto_timer = 0.0
	_advance_locked = true
	_set_ui_state(UIState.BLOCKED)
	story_vm.resume_dialogue()
	if story_vm.game_state.story.runtime_state == StoryState.RuntimeState.FINISHED:
		_begin_ending()


func _begin_ending() -> void:
	if _ending_timer >= 0.0:
		return
	_auto_play = false
	_auto_timer = 0.0
	_ending_timer = 0.0
	_clear_feedback()
	if presentation != null:
		presentation.stage.clear_stage()
		presentation.background.set_court_active(false)
		presentation.background.clear()
	background_view.color = Color.BLACK
	_set_feedback("FIN\n第一章完", 2.0)
	_set_ui_state(UIState.FINISHED)


func _process_ending(delta: float) -> void:
	if _ending_timer < 0.0:
		return
	_ending_timer += delta
	if ui_state == UIState.FINISHED and _ending_timer >= 2.0:
		_set_feedback("制作人员名单\n\n企划与剧本  OthinusG\n程序与系统  Long Night Team\n美术与演出  Long Night Team\n\n感谢游玩", -1.0)
		_set_ui_state(UIState.CREDITS)
	elif ui_state == UIState.CREDITS and _ending_timer >= 8.0:
		_ending_timer = -1.0
		open_title_screen()


func _fast_forward_dialogue() -> void:
	if ui_state != UIState.DIALOGUE or not _dialogue_read or _advance_locked:
		return
	if story_vm.is_in_story_branch() or court_runtime.has_active_testimony():
		return
	_advance_dialogue()
	_fast_forward_timer = 0.0


func _process_fast_forward(delta: float) -> void:
	if ui_state != UIState.DIALOGUE or not Input.is_action_pressed(&"fast_forward"):
		_fast_forward_timer = 0.0
		return
	if not _dialogue_read or _advance_locked or story_vm.is_in_story_branch() or court_runtime.has_active_testimony():
		return
	_fast_forward_timer += delta
	if _fast_forward_timer >= 0.12:
		_fast_forward_timer = 0.0
		_advance_dialogue()


func _process_auto_play(delta: float) -> void:
	if not _auto_play:
		return
	if ui_state != UIState.DIALOGUE or _advance_locked or (debug_overlay != null and debug_overlay.visible):
		_auto_timer = 0.0
		return
	if story_vm == null or story_vm.game_state == null:
		return
	if court_runtime.runtime_state == CourtRuntime.RuntimeState.TESTIMONY_PREVIEW:
		if presentation.dialogue != null and presentation.dialogue.is_revealing():
			_auto_timer = 0.0
			return
		_auto_timer += delta
		if _auto_timer >= _get_auto_delay():
			_auto_timer = 0.0
			_advance_dialogue()
		return
	if story_vm.game_state.story.runtime_state != StoryState.RuntimeState.WAIT_DIALOGUE:
		return
	if presentation != null and presentation.dialogue != null and presentation.dialogue.is_revealing():
		_auto_timer = 0.0
		return

	_auto_timer += delta
	if _auto_timer >= _get_auto_delay():
		_auto_timer = 0.0
		_advance_dialogue()


func _get_auto_delay() -> float:
	var delay: float = GameSettings.DEFAULT_AUTO_SPEED
	if settings_manager != null and settings_manager.settings != null:
		delay = settings_manager.settings.auto_speed
	return delay


func _toggle_auto_play() -> void:
	_auto_play = not _auto_play
	_auto_timer = 0.0
	_update_auto_button_visuals()


func _update_auto_button_visuals() -> void:
	if auto_button == null:
		return
	if _auto_play:
		auto_button.text = "▶ AUTO"
		auto_button.add_theme_color_override("font_color", Color(0.98, 0.85, 0.35, 1.0))
		auto_button.tooltip_text = "自动播放中 (按 A 或点击关闭)"
	else:
		auto_button.text = "AUTO"
		auto_button.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.8))
		auto_button.tooltip_text = "开启自动播放 (快捷键 A)"


func _on_testimony_started(_testimony_id: StringName) -> void:
	_court_intro_timer = 0.0
	_court_preview_visible = false
	_questioning_title_timer = -1.0
	_questioning_transition_ready = false
	dialogue_ui.set_active(false)
	_set_feedback("开始证言", 1.2)
	_set_ui_state(UIState.BLOCKED)


func _process_court_intro(delta: float) -> void:
	if _court_intro_timer < 0.0:
		return
	_court_intro_timer += delta
	if _court_intro_timer >= COURT_TITLE_DURATION:
		_court_intro_timer = -1.0
		_court_preview_visible = true
		_clear_feedback()
		var statement := court_runtime.preview_statement()
		if statement != null:
			_on_preview_statement_changed(statement.id)
			_set_ui_state(UIState.DIALOGUE)


func _on_preview_statement_changed(_statement_id: StringName) -> void:
	if not _court_preview_visible:
		return
	var statement := court_runtime.preview_statement()
	if statement == null:
		return
	_advance_locked = false
	presentation.dialogue.show_line(statement.speaker_id, statement.expression_id, statement.text)
	_dialogue_read = not presentation.dialogue.is_revealing()


func _on_preview_finished(_testimony_id: StringName) -> void:
	_court_intro_timer = -1.0
	_questioning_title_timer = -1.0
	_questioning_transition_ready = false
	_set_ui_state(UIState.BLOCKED)
	presentation.transition.fade_to_black(0.35)
	presentation.transition.veil_covered.connect(_on_preview_veil_covered, CONNECT_ONE_SHOT)


func _on_preview_veil_covered() -> void:
	_questioning_title_timer = 0.0
	_questioning_transition_ready = false
	dialogue_ui.set_active(false)
	_set_feedback("询问证言", COURT_TITLE_DURATION)
	presentation.fx.notice("询问证言", 1.6)
	presentation.transition.fade_from_black(0.35)
	presentation.transition.veil_cleared.connect(_on_preview_transition_finished, CONNECT_ONE_SHOT)


func _on_preview_transition_finished() -> void:
	_questioning_transition_ready = true


func _process_questioning_title(delta: float) -> void:
	if _questioning_title_timer < 0.0:
		return
	_questioning_title_timer += delta
	if _questioning_title_timer < COURT_TITLE_DURATION or not _questioning_transition_ready:
		return
	_questioning_title_timer = -1.0
	_clear_feedback()
	_set_ui_state(UIState.COURT)


func _previous_statement() -> void:
	if ui_state == UIState.COURT:
		court_runtime.previous_statement()


func _next_statement() -> void:
	if ui_state == UIState.COURT:
		court_runtime.next_statement()


func _press_statement() -> void:
	if ui_state != UIState.COURT:
		return
	_set_ui_state(UIState.BLOCKED)
	if court_runtime.press_current_statement().is_empty():
		_set_feedback("NO PRESS BRANCH")
		_set_ui_state(UIState.COURT)


func _open_court_record() -> void:
	if ui_state != UIState.COURT:
		return
	_clear_feedback()
	evidence_panel.open_panel()
	_set_ui_state(UIState.COURT_RECORD)


func _close_court_record() -> void:
	if ui_state == UIState.INVESTIGATION_RECORD:
		evidence_panel.close_panel()
		investigation_runtime.set_mode(InvestigationState.Mode.DEFAULT)
		_set_ui_state(UIState.INVESTIGATION)
		return
	if ui_state != UIState.COURT_RECORD:
		return
	evidence_panel.close_panel()
	_set_ui_state(UIState.COURT)
	court_ui.present_button.grab_focus()


func _open_investigation_record() -> void:
	if ui_state != UIState.INVESTIGATION:
		return
	investigation_runtime.set_mode(InvestigationState.Mode.PRESENT_MODE)
	_clear_feedback()
	evidence_panel.open_panel()
	_set_ui_state(UIState.INVESTIGATION_RECORD)


func _investigation_examine(hotspot_id: StringName) -> void:
	if ui_state != UIState.INVESTIGATION:
		return
	_set_ui_state(UIState.BLOCKED)
	if investigation_runtime.examine(hotspot_id).is_empty():
		_set_feedback("INVALID EXAMINE")
		_refresh_investigation()
		_set_ui_state(UIState.INVESTIGATION)
	else:
		_set_ui_state(UIState.DIALOGUE)


func _investigation_talk(topic_id: StringName) -> void:
	if ui_state != UIState.INVESTIGATION:
		return
	_set_ui_state(UIState.BLOCKED)
	if investigation_runtime.talk(topic_id).is_empty():
		_set_feedback("INVALID TOPIC")
		_refresh_investigation()
		_set_ui_state(UIState.INVESTIGATION)
	else:
		_set_ui_state(UIState.DIALOGUE)


func _investigation_move(location_id: StringName) -> void:
	if ui_state != UIState.INVESTIGATION:
		return
	if not investigation_runtime.move(location_id):
		_set_feedback("INVALID MOVE")
		_refresh_investigation()


func _investigation_mode(mode: InvestigationState.Mode) -> void:
	if ui_state != UIState.INVESTIGATION:
		return
	_clear_feedback()
	investigation_runtime.set_mode(mode)
	presentation.investigation.refresh()
	_refresh_investigation()


func _on_investigation_started(_location_id: StringName) -> void:
	_set_feedback("INVESTIGATION")
	_refresh_investigation()
	_set_ui_state(UIState.INVESTIGATION)


## The location owns the background and the investigation surface; the presenter
## draws it, the UI mirrors it.
func _on_location_changed(_location_id: StringName) -> void:
	_refresh_investigation()


func _on_investigation_action_rejected(message: String) -> void:
	_set_feedback(message)


func _on_investigation_branch_resumed(_context: InvestigationBranchContext) -> void:
	if investigation_runtime.last_error.begins_with("Investigation is incomplete"):
		_set_feedback(investigation_runtime.last_error)
	else:
		_clear_feedback()
	presentation.investigation.refresh()
	_refresh_investigation()
	_set_ui_state(UIState.INVESTIGATION)


func _on_investigation_completed() -> void:
	evidence_panel.close_panel()
	_set_ui_state(UIState.BLOCKED)
	call_deferred("_refresh_status")


func _refresh_investigation() -> void:
	var character_id: StringName = investigation_runtime.state.current_character
	var character: String = (
		content_registry.get_display_name(character_id) if not character_id.is_empty() else ""
	)
	investigation_ui.refresh(
		investigation_runtime,
		investigation_runtime.current_location(),
		character,
	)
	_refresh_status()


# --- procedure support -------------------------------------------------------

func _procedure_select(action_id: StringName) -> void:
	if ui_state != UIState.PROCEDURE:
		return
	var result: ProcedureResult = procedure_runtime.select_action(action_id)
	if result == null:
		_set_feedback("INVALID ACTION")
		_refresh_procedure()
		return
	# A resolved action runs its branch; presentation follows the branch signals.
	_set_feedback(ProcedureResult.Type.keys()[result.type])


func _on_procedure_started(_context_id: StringName) -> void:
	_set_feedback("PROCEDURE")
	_refresh_procedure()
	_set_ui_state(UIState.PROCEDURE)


func _on_procedure_action_resolved(_result: ProcedureResult) -> void:
	_refresh_procedure()


func _on_procedure_resumed(_action_id: StringName) -> void:
	_clear_feedback()
	_refresh_procedure()
	if procedure_runtime.state.active:
		_set_ui_state(UIState.PROCEDURE)


func _on_procedure_completed() -> void:
	_set_ui_state(UIState.BLOCKED)


func _refresh_procedure() -> void:
	procedure_panel.refresh(procedure_runtime)
	_refresh_status()


# --- evidence inspection -----------------------------------------------------

func _open_inspection(evidence_id: StringName) -> void:
	if not inspection_runtime.open(evidence_id):
		_set_feedback("CANNOT INSPECT")
		return
	evidence_panel.close_panel()
	_set_ui_state(UIState.INSPECTION)


func _close_inspection() -> void:
	if inspection_runtime.is_open():
		inspection_runtime.close()
	_set_ui_state(UIState.BLOCKED)
	_refresh_from_state()


func _inspection_hotspot(hotspot_id: StringName) -> void:
	if ui_state != UIState.INSPECTION:
		return
	if inspection_runtime.inspect(hotspot_id).is_empty():
		_set_feedback("INVALID HOTSPOT")
		_refresh_inspection()


func _on_inspection_opened(_evidence_id: StringName) -> void:
	_set_feedback("INSPECTION")
	_refresh_inspection()
	_set_ui_state(UIState.INSPECTION)


func _on_hotspot_inspected(_evidence_id: StringName, _hotspot_id: StringName) -> void:
	_refresh_inspection()


## A hotspot branch returned: the inspection is the active surface again.
func _on_inspection_branch_resumed(_hotspot_id: StringName) -> void:
	_refresh_inspection()
	if inspection_runtime.is_open():
		_set_ui_state(UIState.INSPECTION)


func _on_inspection_completed(_evidence_id: StringName) -> void:
	_set_feedback("INSPECTION COMPLETE")
	_refresh_inspection()


func _refresh_inspection() -> void:
	evidence_inspection_ui.refresh(inspection_runtime, evidence_repository)
	_refresh_status()


func request_save(slot: int) -> bool:
	if save_manager == null:
		return false
	if not save_manager.save_slot(slot):
		_set_feedback("SAVE FAILED\n%s" % save_manager.error_message)
		_refresh_status()
		return false
	_set_feedback("SAVED SLOT %d" % slot)
	return true


func request_load(slot: int) -> bool:
	if save_manager == null:
		return false
	if not save_manager.load_slot(slot):
		# A rejected save must leave the running session untouched.
		_set_feedback("LOAD FAILED\n%s" % save_manager.error_message)
		push_warning("[Main] %s" % save_manager.error_message)
		return false
	_refresh_from_state()
	_set_feedback("LOADED SLOT %d" % slot)
	return true


## Rebuilds presentation from canonical state after a save load or a debug jump.
func _refresh_from_state() -> void:
	evidence_panel.close_panel()
	presentation.refresh_from_state(game_state)
	if gallery_manager != null and game_state != null and game_state.story.current_background != &"":
		if String(game_state.story.current_background).begins_with("cg_"):
			gallery_manager.unlock_cg(String(game_state.story.current_background))
	match game_state.story.runtime_state:

		StoryState.RuntimeState.WAIT_COURT:
			_set_ui_state(UIState.COURT)
		StoryState.RuntimeState.WAIT_INVESTIGATION:
			# The investigation location owns the background, not the story.
			_refresh_investigation()
			_set_ui_state(UIState.INVESTIGATION)
		StoryState.RuntimeState.WAIT_PROCEDURE:
			_refresh_procedure()
			_set_ui_state(UIState.PROCEDURE)
		StoryState.RuntimeState.WAIT_DIALOGUE:
			# The restored position already re-emitted its dialogue line.
			_set_ui_state(UIState.DIALOGUE)
		StoryState.RuntimeState.FINISHED:
			_begin_ending()
		_:
			_set_ui_state(UIState.BLOCKED)


func _present_evidence(evidence_id: StringName) -> void:
	if ui_state == UIState.INVESTIGATION_RECORD:
		evidence_panel.close_panel()
		_set_ui_state(UIState.BLOCKED)
		if investigation_runtime.present(evidence_id).is_empty():
			_set_feedback("INVALID PRESENT")
			investigation_runtime.set_mode(InvestigationState.Mode.DEFAULT)
			_refresh_investigation()
			_set_ui_state(UIState.INVESTIGATION)
		return
	if ui_state != UIState.COURT_RECORD:
		return
	var statement: StatementDef = court_runtime.get_current_statement()
	if statement == null:
		_fatal("Cannot present evidence without a current statement.")
		return
	evidence_panel.close_panel()
	_set_ui_state(UIState.BLOCKED)
	var result: PresentResult = court_runtime.present_evidence(statement.id, evidence_id)
	if result.type == PresentResultType.Value.INVALID:
		_set_feedback("INVALID ACTION")
		presentation.court.refresh()
		_set_ui_state(UIState.COURT)


func _on_testimony_suspended(_context: CourtBranchContext) -> void:
	_set_ui_state(UIState.BLOCKED)


func _on_testimony_resumed(_testimony_id: StringName, _statement_id: StringName) -> void:
	_clear_feedback()
	presentation.court.refresh()
	_set_ui_state(UIState.COURT)


func _on_testimony_completed(_testimony_id: StringName) -> void:
	evidence_panel.close_panel()
	if story_vm.game_state.story.runtime_state == StoryState.RuntimeState.WAIT_DIALOGUE:
		_set_ui_state(UIState.DIALOGUE)
		if presentation != null and presentation.fx.has_dismissible_notice():
			dialogue_ui.set_active(false)
	else:
		_set_ui_state(UIState.BLOCKED)
	call_deferred("_refresh_status")


func _on_court_failed(_testimony_id: StringName) -> void:
	_clear_feedback()
	if presentation != null:
		presentation.stage.clear_stage()
		presentation.background.set_court_active(false)
		presentation.background.clear()
	background_view.color = Color.BLACK
	_set_feedback("GAME OVER\n点击鼠标返回主菜单", -1.0)
	_set_ui_state(UIState.GAMEOVER)


func _set_ui_state(next_state: UIState) -> void:
	ui_state = next_state
	var terminal_screen: bool = next_state in [
		UIState.GAMEOVER,
		UIState.FINISHED,
		UIState.CREDITS,
	]
	if terminal_screen and presentation != null:
		presentation.stage.clear_stage()
		presentation.background.set_court_active(false)
		presentation.background.clear()
		background_view.color = Color.BLACK
	dialogue_ui.set_active(next_state == UIState.DIALOGUE)
	var show_court: bool = next_state in [UIState.COURT, UIState.COURT_RECORD]
	court_ui.visible = show_court
	court_ui.set_interaction_enabled(next_state == UIState.COURT)
	court_ui.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if next_state == UIState.COURT
		else Control.MOUSE_FILTER_IGNORE
	)
	var show_investigation: bool = next_state in [
		UIState.INVESTIGATION,
		UIState.INVESTIGATION_RECORD,
	]
	investigation_ui.visible = show_investigation
	investigation_ui.set_interaction_enabled(next_state == UIState.INVESTIGATION)
	investigation_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	procedure_panel.visible = next_state == UIState.PROCEDURE
	procedure_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if next_state == UIState.PROCEDURE
		else Control.MOUSE_FILTER_IGNORE
	)
	evidence_inspection_ui.visible = next_state == UIState.INSPECTION
	settings_ui.visible = next_state == UIState.MENU
	title_screen.visible = next_state == UIState.TITLE
	pause_menu.visible = next_state == UIState.PAUSE_MENU
	save_load_panel.visible = next_state == UIState.SAVE_LOAD
	gallery_ui.visible = next_state == UIState.GALLERY

	var in_game := next_state not in [
		UIState.TITLE,
		UIState.BLOCKED,
		UIState.GAMEOVER,
		UIState.FINISHED,
		UIState.CREDITS,
		UIState.ERROR,
	]
	game_title_label.visible = in_game
	background_label.visible = in_game
	status_label.visible = false
	character_stage_root.visible = next_state not in [
		UIState.TITLE,
		UIState.GALLERY,
		UIState.GAMEOVER,
		UIState.FINISHED,
		UIState.CREDITS,
		UIState.ERROR,
	]
	var buttons_visible := in_game and next_state not in [
		UIState.PAUSE_MENU,
		UIState.MENU,
		UIState.SAVE_LOAD,
		UIState.GALLERY,
	]
	menu_gear_button.visible = buttons_visible
	auto_button.visible = buttons_visible
	if next_state != UIState.DIALOGUE:
		_auto_timer = 0.0


	# Panels own focus while they are the active surface (spec 12.10); the calls
	# come after `visible` so a hidden control is never asked to grab focus.
	procedure_panel.set_interaction_enabled(next_state == UIState.PROCEDURE)
	evidence_inspection_ui.set_interaction_enabled(next_state == UIState.INSPECTION)
	if next_state not in [UIState.COURT_RECORD, UIState.INVESTIGATION_RECORD]:
		evidence_panel.close_panel()
	if input_router != null:
		input_router.set_context(_input_context_for(next_state))
	_refresh_status()


func _input_context_for(state: UIState) -> InputContext.Kind:
	match state:
		UIState.DIALOGUE:
			return InputContext.Kind.DIALOGUE
		UIState.COURT:
			return InputContext.Kind.COURT
		UIState.COURT_RECORD, UIState.INVESTIGATION_RECORD:
			return InputContext.Kind.COURT_RECORD
		UIState.INVESTIGATION:
			return InputContext.Kind.INVESTIGATION
		UIState.PROCEDURE:
			return InputContext.Kind.PROCEDURE
		UIState.INSPECTION:
			return InputContext.Kind.EVIDENCE_INSPECTION
		UIState.MENU, UIState.TITLE, UIState.PAUSE_MENU, UIState.SAVE_LOAD, UIState.GALLERY:
			return InputContext.Kind.MENU
		_:
			return InputContext.Kind.BLOCKED


func _refresh_status() -> void:
	var story_state: String = (
		StoryState.RuntimeState.keys()[game_state.story.runtime_state]
		if game_state != null
		else "NOT_LOADED"
	)
	var court_state: String = (
		CourtRuntime.RuntimeState.keys()[court_runtime.runtime_state]
		if court_runtime != null
		else "NOT_LOADED"
	)
	var investigation_state: String = (
		InvestigationState.Mode.keys()[game_state.investigation.mode]
		if game_state != null
		else "NOT_LOADED"
	)
	var procedure_state: String = (
		String(game_state.procedure.context_id)
		if game_state != null and game_state.procedure.active
		else "INACTIVE"
	)
	status_label.text = (
		"StoryVM: %s   Court: %s   Investigation: %s   Procedure: %s   UI: %s   (F12 debugger)"
		% [
			story_state,
			court_state,
			investigation_state,
			procedure_state,
			UIState.keys()[ui_state],
		]
	)
	if pause_menu != null:
		pause_menu.set_save_enabled(save_manager != null and save_manager.can_save())


func _set_feedback(text: String, duration: float = FEEDBACK_DURATION) -> void:
	feedback_label.text = text
	_feedback_timer = duration if not text.is_empty() else -1.0


func _clear_feedback() -> void:
	feedback_label.text = ""
	_feedback_timer = -1.0


func _is_smoke_test() -> bool:
	return (
		OS.get_cmdline_args().has(SMOKE_TEST_ARG)
		or OS.get_cmdline_user_args().has(SMOKE_TEST_ARG)
	)


func _fatal(message: String) -> bool:
	_clear_feedback()
	_set_feedback("ERROR\n%s" % message, -1.0)
	_set_ui_state(UIState.ERROR)
	push_error("[Main] %s" % message)
	return false
