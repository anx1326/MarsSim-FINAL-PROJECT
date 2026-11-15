extends Node3D
## ═══════════════════════════════════════════════════════════════════════════
##  MARS SIMULATOR — MASTER EDITION II   (Godot 4.2+ / GDScript, single script)
## ═══════════════════════════════════════════════════════════════════════════
##  SETUP: one root Node3D, attach this script, run. Everything is built in code.
##
##  MENU    : drag = orbit Mars | wheel = zoom | age slider | Launch
##  INTRO   : capsule drop from orbit  •  Space / Enter = skip
##  SURFACE : WASD / arrows = move or drive | Shift = sprint | drag = camera
##            F = interact (HOLD F on glowing deposits to mine)
##            I / Tab = inventory | E = eat best food | Q = use Power Cell
##            R = board / exit rover | H = back to landing pad
##            Backspace = skip training | F9 = trigger hazard | Esc = pause
## ═══════════════════════════════════════════════════════════════════════════

enum SimState { MENU_ORBIT, SURFACE }
enum Hazard { NONE, DUST_STORM, SOLAR_FLARE }
enum Intro { NONE, ENTRY, CHUTE, RETRO, LANDED, EGRESS }

# ─────────────────────────────── TUNABLES ───────────────────────────────────
const EVENT_TEXT := "LIVE EVENT  •  SUN 15 NOV 2026"
const GALE_LAT_DEG := -5.4
const GALE_LON_DEG := 137.8
const GLOBE_RADIUS := 5.0
const WORLD_LIMIT := 260.0
const PLAYER_Y := 0.5
const WALK_SPEED := 4.5
const SPRINT_SPEED := 9.0
const ROVER_MAX_SPEED := 16.0
const ROVER_ACCEL := 9.0
const ROVER_TURN := 1.5
const HAB_POS := Vector3(0.0, 0.0, -20.0)
const PAD_POS := Vector3(0.0, 0.0, 14.0)
const SPAWN_POS := Vector3(0.0, 0.5, 10.6)
const ROVER_START := Vector3(14.0, 0.5, 10.0)
const BASE_MIN := Vector2(-25.0, -27.0)
const BASE_MAX := Vector2(25.0, 9.0)
const WALL_H := 3.2
const SLEEP_TIME := 4.0
const FOOD_DRAIN := 0.45
const REST_DRAIN := 0.35
const POWER_DRAIN := 0.15
const ROVER_POWER := 0.9
const INV_SLOTS := 20
const STACK_MAX := 99
const MAX_DEPOSITS := 28
const COMBO_WINDOW := 10.0
const CAPSULE_START_Y := 320.0
const SAVE_PATH := "user://mars_sim_save.cfg"
const DEMO_STREAK := 0          # >0 forces a streak value for demos
const FOG_BASE := 0.0014
const FOG_STORM := 0.016
const COL_FOG_CLEAR := Color(0.80, 0.56, 0.42)
const COL_FOG_STORM := Color(0.72, 0.44, 0.27)

const ATMO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.3, 1.0);
void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(f * 0.95, 0.0, 1.0);
}
"""

# ─────────────────────────────── DATA TABLES ────────────────────────────────
const ITEMS := {
	"ration":     {"name": "Ration Pack",    "cat": "food",     "col": Color(0.95, 0.62, 0.22), "food": 30.0, "rest": 0.0,  "desc": "Freeze-dried meal. +30 Food."},
	"greens":     {"name": "Fresh Greens",   "cat": "food",     "col": Color(0.40, 0.85, 0.35), "food": 18.0, "rest": 6.0,  "desc": "Greenhouse crop. +18 Food, +6 Rest."},
	"energy_bar": {"name": "Energy Bar",     "cat": "food",     "col": Color(0.85, 0.45, 0.65), "food": 12.0, "rest": 14.0, "desc": "Fabricated snack. +12 Food, +14 Rest."},
	"power_cell": {"name": "Power Cell",     "cat": "tool",     "col": Color(1.00, 0.85, 0.25), "power": 35.0, "desc": "Portable battery. +35 Power (Q)."},
	"iron":       {"name": "Iron Ore",       "cat": "material", "col": Color(0.85, 0.38, 0.22), "desc": "Iron oxide — why Mars is red."},
	"silica":     {"name": "Silica Crystal", "cat": "material", "col": Color(0.92, 0.88, 0.98), "desc": "For solar cells and glass."},
	"ice":        {"name": "Water Ice",      "cat": "material", "col": Color(0.55, 0.85, 1.00), "desc": "Buried ice: water and oxygen."},
	"titanium":   {"name": "Titanium",       "cat": "material", "col": Color(0.72, 0.55, 1.00), "desc": "Rare metal for upgrades."},
	"gem":        {"name": "Isotope Gem",    "cat": "material", "col": Color(0.30, 1.00, 0.50), "desc": "Expedition objective."},
}
const RECIPES := [
	{"id": "power_cell", "name": "Power Cell",     "cost": {"iron": 2, "silica": 1},   "out": {"power_cell": 1}},
	{"id": "energy_bar", "name": "Energy Bar x2",  "cost": {"greens": 1, "ice": 1},    "out": {"energy_bar": 2}},
	{"id": "ration",     "name": "Ration Pack x2", "cost": {"ice": 1, "greens": 2},    "out": {"ration": 2}},
	{"id": "drill",      "name": "Drill Upgrade",  "cost": {"iron": 4, "titanium": 1}, "out": {}},
]
const PALETTE := [
	{"name": "Polar White", "col": Color(0.93, 0.93, 0.95), "lvl": 1,  "streak": 0},
	{"name": "Mars Orange", "col": Color(0.95, 0.45, 0.15), "lvl": 2,  "streak": 0},
	{"name": "Cobalt",      "col": Color(0.20, 0.40, 0.90), "lvl": 3,  "streak": 0},
	{"name": "Moss",        "col": Color(0.30, 0.60, 0.30), "lvl": 4,  "streak": 0},
	{"name": "Crimson",     "col": Color(0.80, 0.12, 0.15), "lvl": 6,  "streak": 0},
	{"name": "Midnight",    "col": Color(0.14, 0.14, 0.22), "lvl": 8,  "streak": 0},
	{"name": "Streak Gold", "col": Color(1.00, 0.78, 0.25), "lvl": 1,  "streak": 7},
	{"name": "Aurora",      "col": Color(0.85, 0.40, 0.95), "lvl": 12, "streak": 0},
]
const VISORS := [
	{"name": "Gold",    "col": Color(1.0, 0.78, 0.25),  "lvl": 1, "streak": 0},
	{"name": "Silver",  "col": Color(0.80, 0.85, 0.90), "lvl": 2, "streak": 0},
	{"name": "Cyan",    "col": Color(0.20, 0.90, 1.00), "lvl": 4, "streak": 0},
	{"name": "Emerald", "col": Color(0.20, 1.00, 0.50), "lvl": 1, "streak": 3},
	{"name": "Rose",    "col": Color(1.00, 0.40, 0.60), "lvl": 7, "streak": 0},
]
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color(0.85, 0.85, 0.85), Color(0.3, 0.6, 1.0), Color(0.8, 0.35, 1.0), Color(1.0, 0.75, 0.15)]
const ACHIEVEMENTS := {
	"tutorial":  ["First Steps", "Finish the training"],
	"miner25":   ["Rock Breaker", "Mine 25 times"],
	"miner100":  ["Geologist", "Mine 100 times"],
	"gems10":    ["Gem Hunter", "Collect 10 Isotope Gems"],
	"drive1k":   ["Road Trip", "Drive 1 km in the rover"],
	"harvest10": ["Green Thumb", "Harvest 10 plants"],
	"legendary": ["Jackpot", "Open a legendary supply drop"],
	"combo":     ["Unstoppable", "Reach a x3.0 combo"],
	"streak3":   ["Habit Forming", "3-day streak"],
	"streak7":   ["Dedicated", "7-day streak"],
	"exped3":    ["Veteran", "Complete 3 expeditions"],
	"crafter":   ["Maker", "Craft 10 items"],
}
const DAILY_POOL := [
	{"type": "mine",    "goal": 12,  "text": "Mine %d deposits"},
	{"type": "gems",    "goal": 4,   "text": "Collect %d Isotope Gems"},
	{"type": "drive",   "goal": 600, "text": "Drive %d m in the rover"},
	{"type": "harvest", "goal": 4,   "text": "Harvest %d plants"},
	{"type": "drops",   "goal": 2,   "text": "Open %d supply drops"},
	{"type": "craft",   "goal": 3,   "text": "Craft %d items"},
]
# ── age decision branch ──
const BRACKETS := [
	{"name": "Junior Explorer",    "max": 10, "drain": 0.55, "hazard": 0.5,  "flare": false, "gems": 5,  "hints": true,  "break_min": 20, "xp": 1.25, "goal_mult": 0.5,
		"desc": "Friendly step-by-step training, guide arrows, gentle storms (no solar flares), simple Mars facts and stretch-break reminders."},
	{"name": "Space Cadet",        "max": 13, "drain": 0.75, "hazard": 0.75, "flare": true,  "gems": 6,  "hints": true,  "break_min": 30, "xp": 1.1,  "goal_mult": 0.75,
		"desc": "Guided training, guide arrows, mild storms and flares, Mars facts, break reminder every 30 min."},
	{"name": "Mission Specialist", "max": 17, "drain": 1.0,  "hazard": 1.0,  "flare": true,  "gems": 8,  "hints": false, "break_min": 45, "xp": 1.0,  "goal_mult": 1.0,
		"desc": "Full training, standard survival drain, all hazards, more gems to find."},
	{"name": "Commander",          "max": 999, "drain": 1.3, "hazard": 1.35, "flare": true,  "gems": 10, "hints": false, "break_min": 0,  "xp": 1.0,  "goal_mult": 1.3,
		"desc": "Condensed technical briefing, heavy drain, frequent hazards, 10 gems, no guide arrows."},
]
const FACTS := [
	["Mars looks red because its dust is full of rusty iron!", "Mars' red colour comes from iron oxide (rust) in the surface dust."],
	["You'd weigh much less on Mars — you could jump almost 3 times higher!", "Surface gravity on Mars is about 38% of Earth's."],
	["A day on Mars is only about 40 minutes longer than on Earth.", "A Martian solar day (sol) lasts about 24 h 40 min."],
	["Mars has the biggest volcano we know of: Olympus Mons!", "Olympus Mons rises about 22 km — roughly 2.5 times Everest."],
	["Mars has two little moons called Phobos and Deimos.", "Phobos and Deimos are small, lumpy moons, possibly captured asteroids."],
	["The air on Mars is super thin, so astronauts need space suits.", "The atmosphere is ~95% carbon dioxide, at under 1% of Earth's pressure."],
	["The Curiosity rover landed in Gale Crater in 2012!", "NASA's Curiosity landed in Gale Crater in August 2012 and has explored Mount Sharp since."],
	["Some Mars dust storms can cover the whole planet!", "Global dust storms can last weeks; one in 2018 ended the Opportunity rover's mission."],
	["Mars is usually colder than the North Pole!", "Average surface temperature is around −60 °C."],
	["Messages to Earth take minutes, so astronauts solve problems themselves.", "Radio signals take roughly 3–22 minutes between Mars and Earth."],
]
# texts per bracket: [Explorer, Cadet, Specialist, Commander]; "skip" lists brackets that skip the step
const TUTORIAL := [
	{"id": "look", "title": "Look around", "skip": [3], "t": [
		"Hold a mouse button and drag to spin the camera. Wow — you're on Mars!",
		"Click and drag to rotate the camera. Scroll the wheel to zoom.",
		"Drag to orbit the camera and scroll to zoom. Take in the crater.", ""]},
	{"id": "move", "title": "Walk", "skip": [], "t": [
		"Press W A S D (or the arrow keys) to walk. Walk a little way!",
		"Use W A S D or the arrow keys to walk. Movement follows the camera.",
		"WASD / arrows move relative to the camera. Walk 10 metres.",
		"WASD to move (camera-relative). Walk 10 m to calibrate the suit."]},
	{"id": "sprint", "title": "Sprint", "skip": [3], "t": [
		"Hold SHIFT while walking to run super fast!",
		"Hold Shift while moving to sprint. Sprinting uses more food and rest.",
		"Hold Shift to sprint — it drains Food and Rest faster.", ""]},
	{"id": "crate", "title": "Interact", "skip": [], "t": [
		"See the glowing box? Walk to it and press F to open it!",
		"Walk to the glowing supply crate on the landing pad and press F to open it.",
		"Approach the supply crate (marked ▼) and press F to interact.",
		"Recover the supply crate at the marker. F = interact."]},
	{"id": "inventory", "title": "Inventory", "skip": [], "t": [
		"Press I to open your backpack and see what you found!",
		"Press I or Tab to open your inventory. Food and materials live here.",
		"Open your inventory (I / Tab): 20 slots, stacks of up to 99.",
		"Inventory: I / Tab. 20 slots, stacks of 99."]},
	{"id": "eat", "title": "Eat", "skip": [], "t": [
		"Yum! Click the Ration Pack in your backpack, or press E, to eat.",
		"Eat something: click a food item in the inventory, or press E.",
		"Eat from the inventory (click a food) or press E to eat the best food you carry.",
		"Consume a ration (E). Food drains constantly; starving halves your speed."]},
	{"id": "mine", "title": "Mine", "skip": [], "t": [
		"Find the sparkly rock nearby. Stand next to it and HOLD F to mine it!",
		"Find a glowing mineral deposit and HOLD F next to it to mine.",
		"Deposits glow by mineral type. HOLD F beside one to mine — each gives several yields.",
		"Hold F at a deposit to extract ore. Chain actions within 10 s to build a combo."]},
	{"id": "base", "title": "Enter the base", "skip": [], "t": [
		"Follow the arrow to your Mars base and walk in through the big door!",
		"Follow the marker to Base Alpha and enter through the airlock.",
		"Enter Base Alpha via the south airlock. Inside, power recharges and you're safe from flares.",
		"Enter Base Alpha. Habitat = power recharge + radiation shelter."]},
	{"id": "craft", "title": "Craft", "skip": [], "t": [
		"Go to the Workshop. Use the big orange machine (F) to make a Power Cell!",
		"Go to the Workshop and use the Fabricator (F). Craft a Power Cell from iron and silica.",
		"Workshop → Fabricator (F). Turn 2 Iron + 1 Silica into a Power Cell.",
		"Fabricate a Power Cell (2 iron, 1 silica) in the Workshop."]},
	{"id": "locker", "title": "Customise", "skip": [], "t": [
		"Go to the bedroom and open your locker (F) to pick your space-suit colour!",
		"Visit Crew Quarters and open your locker (F) to customise your suit and rover.",
		"Crew Quarters → your locker (F): suit, visor, accents, rover paint and callsign.",
		"Cosmetics at your locker (Crew Quarters). Levels and streaks unlock more."]},
	{"id": "sleep", "title": "Sleep", "skip": [], "t": [
		"Feeling sleepy? Lie down in a bunk bed (F) for a nap.",
		"Rest in one of the bunks (F) to refill your Rest bar.",
		"Sleep in a bunk (F) to restore Rest. Sleeping costs a little Food.",
		"Sleep cycle at a bunk (F). Rest at 0 halves your speed."]},
	{"id": "rover", "title": "Drive", "skip": [], "t": [
		"Go outside to the big rover. Press R to hop in and drive around!",
		"Head outside to the ARES rover, press R to board, then drive 40 m.",
		"Board the ARES rover (R) and drive 40 m. Driving drains power faster.",
		"Rover: R to board/exit. Drive 40 m. Watch power draw at speed."]},
	{"id": "gem", "title": "Find a gem", "skip": [], "t": [
		"Look for the tall green lights and drive into a gem to grab it!",
		"Follow a green beam and collect an Isotope Gem — your main objective.",
		"Collect an Isotope Gem (green beams). Gems finish the expedition and restore power.",
		"Recover one Isotope Gem. The full set ends the expedition."]},
	{"id": "done", "title": "Training complete", "skip": [], "t": [
		"You did it, Space Explorer! Watch for supply drops and come back tomorrow for your streak bonus!",
		"Training complete! Supply drops fall from the sky — open them for loot. Daily streaks give bonus supplies.",
		"Training complete. Open supply drops, complete daily missions and keep your streak alive for rewards.",
		"Briefing complete. Daily missions, drops and streak bonuses are live. Good hunting, Commander."]},
]

# ─────────────────────────────── STATE ──────────────────────────────────────
var state: int = SimState.MENU_ORBIT
var rng := RandomNumberGenerator.new()
var transitioning := false
var dragging := false
var time_accum := 0.0
var ui_modal := ""
var autosave_timer := 30.0

# hardware profile
var q_tier := "HIGH"
var q_os := ""
var q_cores := 4
var q_shadows := true
var q_globe_seg := 128
var q_globe_rings := 64
var q_tex_w := 768
var q_tex_h := 384
var q_ground := 256
var q_rocks := 450
var q_pebbles := 800
var q_stars := 500
var q_glow := true
var q_particles := true
var q_ssao := true
var q_volumetric := false
var q_lights := true
var q_msaa: int = Viewport.MSAA_4X

# scene
var menu_root: Node3D
var surface_root: Node3D
var menu_pivot: Node3D
var menu_camera: Camera3D
var surface_camera: Camera3D
var globe_spin: Node3D
var beacon_pin: Node3D
var beacon_halo: MeshInstance3D
var beacon_ring: MeshInstance3D
var beacon_ring_mat: StandardMaterial3D
var surface_env: Environment
var surface_sun: DirectionalLight3D
var mars_tex: ImageTexture
var dust_particles: CPUParticles3D
var motes: CPUParticles3D
var burst_fx: CPUParticles3D
var rover_dust: CPUParticles3D
var step_dust: CPUParticles3D
var hab_root: Node3D
var roof_root: Node3D
var hab_beacon_mat: StandardMaterial3D
var pad_light_mat: StandardMaterial3D
var holo_globe: Node3D
var drone: Node3D
var o2_fans: Array[Node3D] = []
var hm_hull: StandardMaterial3D
var hm_trim: StandardMaterial3D
var hm_glow: StandardMaterial3D
var hm_amber: StandardMaterial3D
var hm_dark: StandardMaterial3D
var hm_screen: StandardMaterial3D
var hm_wood: StandardMaterial3D
var circles: Array[Vector3] = []     # x, z, radius
var rects: Array[Rect2] = []         # world XZ boxes
var rooms: Array[Dictionary] = []
var base_rect := Rect2()
var objective_marker: Node3D
var objective_label: Label3D
var objective_pos := Vector3.ZERO
var has_objective := false

# capsule / intro
var capsule: Node3D
var capsule_glow: MeshInstance3D
var capsule_trail: CPUParticles3D
var capsule_flame: CPUParticles3D
var capsule_light: OmniLight3D
var hatch_hinge: Node3D
var chute: Node3D
var chute_attached := true
var chute_drift := Vector3.ZERO
var chute_age := 0.0
var landing_dust: CPUParticles3D
var intro_phase: int = Intro.NONE
var intro_timer := 0.0
var cap_y := 0.0
var cap_vel := 0.0
var intro_orbit := 0.0
var intro_dist := 26.0
var shake := 0.0

# player / vehicles
var astro: Node3D
var astro_model: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var callsign_label: Label3D
var helmet_light: SpotLight3D
var suit_mat: StandardMaterial3D
var visor_mat: StandardMaterial3D
var accent_mat: StandardMaterial3D
var rover_paint_mat: StandardMaterial3D
var player_pos := SPAWN_POS
var player_heading := 0.0
var walk_phase := 0.0
var is_moving := false
var sprinting := false
var rover: Node3D
var rover_wheels: Array[Node3D] = []
var rover_speed := 0.0
var rover_heading := 0.5
var driving := false
var inside_base := false

# cameras
var cam_yaw := 0.0
var cam_pitch := 0.38
var cam_dist := 8.0
var cam_eff_dist := 8.0
var cam_eff_pitch := 0.38
var cam_target := Vector3.ZERO
var menu_yaw := 0.0
var menu_pitch := 0.12
var menu_dist := 13.0
var menu_dist_target := 13.0

# mission
var cadet_age := 16
var bracket := 2
var difficulty := 1.0
var ease := 1.0
var exhaust_events := 0
var was_exhausted := false
var power := 100.0
var food := 100.0
var rest := 100.0
var gems := 0
var gem_target := 8
var expedition := 1
var mission_time := 0.0
var mission_complete := false
var hazard: int = Hazard.NONE
var hazard_timer := 70.0
var sleeping := false
var sleep_timer := 0.0
var sleep_rest_from := 0.0
var power_warned := false
var collectibles: Array[Dictionary] = []
var interactables: Array[Dictionary] = []
var inventory := {}
var focus: Dictionary = {}
var mine_target: Dictionary = {}
var mine_progress := 0.0
var combo := 0
var combo_timer := 0.0
var drop_timer := 75.0
var deposit_timer := 25.0
var fact_timer := 35.0
var fact_index := 0
var fact_time := 0.0
var play_time := 0.0
var break_at := 0.0

# persistent progression
var level := 1
var xp := 0
var drill_level := 1
var total_gems := 0
var total_mined := 0
var total_harvest := 0
var total_crafted := 0
var total_drive := 0.0
var expeditions_done := 0
var streak := 1
var best_streak := 1
var streak_last_day := 0
var claimed_day := 0
var achievements: Array = []
var tutorial_done := false
var play_tutorial := true
var suit_idx := 0
var visor_idx := 0
var accent_idx := 1
var rover_idx := 1
var callsign := "CADET"
var daily_day := 0
var daily: Array = []

# tutorial
var tut_active := false
var tut_steps: Array = []
var tut_index := 0
var tut_cam_drag := 0.0
var tut_walk := 0.0
var tut_sprint := 0.0
var tut_drive := 0.0
var tut_flags := {}
var tut_done_timer := 0.0
var tut_crate_pos := Vector3.ZERO

# UI
var menu_layer: CanvasLayer
var hud_layer: CanvasLayer
var intro_layer: CanvasLayer
var modal_layer: CanvasLayer
var fade_layer: CanvasLayer
var fade_rect: ColorRect
var hud_root: Control
var menu_panel: PanelContainer
var launch_btn: Button
var age_slider: HSlider
var age_label: Label
var diff_label: Label
var branch_label: Label
var profile_label: Label
var streak_badge: Label
var tut_check: CheckBox
var pin_label: Label
var power_bar: ProgressBar
var food_bar: ProgressBar
var rest_bar: ProgressBar
var cadet_label: Label
var hazard_label: Label
var mode_label: Label
var room_label: Label
var mission_label: Label
var daily_label: Label
var toast_label: Label
var level_label: Label
var rank_label: Label
var streak_label: Label
var xp_bar: ProgressBar
var xp_text: Label
var combo_label: Label
var radar: RadarView
var tut_panel: PanelContainer
var tut_title: Label
var tut_text: Label
var tut_prog: ProgressBar
var prompt_panel: PanelContainer
var prompt_label: Label
var mine_bar: ProgressBar
var hot_food: Label
var hot_cell: Label
var hot_inv: Label
var fact_panel: PanelContainer
var fact_label: Label
var flash_rect: ColorRect
var sleep_overlay: ColorRect
var sleep_label: Label
var letter_top: ColorRect
var letter_bot: ColorRect
var intro_label: Label
var intro_msg: Label
var modal_dim: ColorRect
var modal_panel: PanelContainer
var modal_title: Label
var modal_body: VBoxContainer
var modal_close: Button
var toast_time := 0.0
var hud_timer := 0.0

# ═══════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	rng.seed = 20261115
	var win := get_window()
	win.title = "Mars Simulator — Master Edition II"
	win.content_scale_size = Vector2i(1280, 720)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_detect_hardware()
	get_viewport().msaa_3d = q_msaa
	_load_save()
	streak = _compute_streak()
	best_streak = maxi(best_streak, streak)
	_ensure_daily()

	mars_tex = _make_mars_texture(q_tex_w, q_tex_h)
	_build_menu_world()
	_build_surface_world()
	rng.randomize()
	_build_menu_ui()
	_build_hud()
	_build_intro_overlay()
	_build_modal()
	_build_fade_layer()
	_check_streak_unlocks()

	age_slider.value = float(cadet_age)
	_on_age_changed(float(cadet_age))
	_apply_customization()
	_enter_state(SimState.MENU_ORBIT)

	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, 1.6)
	var tw2 := create_tween()
	tw2.tween_property(menu_panel, "modulate:a", 1.0, 1.4).set_delay(0.7)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


func _process(delta: float) -> void:
	time_accum += delta
	if dragging and not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		dragging = false
	match state:
		SimState.MENU_ORBIT:
			_process_menu(delta)
		SimState.SURFACE:
			_process_surface(delta)
	_update_toast(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
	elif event is InputEventMouseMotion and dragging:
		_orbit((event as InputEventMouseMotion).relative)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if state == SimState.SURFACE and not transitioning:
			_handle_surface_key(k.physical_keycode)


func _handle_surface_key(code: int) -> void:
	if intro_phase != Intro.NONE:
		if code == KEY_SPACE or code == KEY_ENTER or code == KEY_ESCAPE:
			_skip_intro()
		return
	if ui_modal != "":
		var closes := code == KEY_ESCAPE or ((code == KEY_I or code == KEY_TAB) and ui_modal == "inventory")
		if closes and ui_modal != "summary":
			_close_modal()
		return
	match code:
		KEY_F:
			_on_interact_pressed()
		KEY_E:
			_eat_best()
		KEY_Q:
			_use_item("power_cell")
		KEY_R:
			_toggle_rover()
		KEY_I, KEY_TAB:
			_open_modal("inventory")
		KEY_H:
			_on_reset_spawn()
		KEY_BACKSPACE:
			if tut_active:
				_end_tutorial(false)
				_toast("Training skipped — replay it from the pause menu (Esc)", 4.0)
		KEY_F9:
			hazard = Hazard.DUST_STORM if hazard != Hazard.DUST_STORM else Hazard.SOLAR_FLARE
			hazard_timer = 25.0
			_toast("Hazard triggered (demo)")
		KEY_ESCAPE:
			_open_modal("pause")


func _zoom(dir: float) -> void:
	if state == SimState.MENU_ORBIT:
		menu_dist_target = clampf(menu_dist_target + dir * 1.2, 8.5, 26.0)
	else:
		cam_dist = clampf(cam_dist + dir * 0.9, 3.5, 22.0)


func _orbit(rel: Vector2) -> void:
	if state == SimState.MENU_ORBIT:
		menu_yaw -= rel.x * 0.006
		menu_pitch = clampf(menu_pitch + rel.y * 0.006, -1.2, 1.2)
	else:
		cam_yaw -= rel.x * 0.005
		cam_pitch = clampf(cam_pitch + rel.y * 0.005, 0.08, 1.25)
		tut_cam_drag += rel.length()


# ═══════════════════════════════════════════════════════════════════════════
#  HARDWARE / AGE BRANCH
# ═══════════════════════════════════════════════════════════════════════════
func _detect_hardware() -> void:
	q_os = OS.get_name()
	q_cores = OS.get_processor_count()
	if q_os in ["Android", "iOS", "Web"] or q_cores <= 2:
		q_tier = "LOW"
	elif q_cores <= 4:
		q_tier = "MEDIUM"
	else:
		q_tier = "HIGH"
	match q_tier:
		"HIGH":
			q_globe_seg = 160
			q_globe_rings = 80
			q_rocks = 600
			q_pebbles = 1400
			q_stars = 600
			q_volumetric = true
		"MEDIUM":
			q_globe_seg = 96
			q_globe_rings = 48
			q_tex_w = 512
			q_tex_h = 256
			q_ground = 192
			q_rocks = 320
			q_pebbles = 700
			q_stars = 350
			q_msaa = Viewport.MSAA_2X
		_:
			q_shadows = false
			q_globe_seg = 48
			q_globe_rings = 24
			q_tex_w = 384
			q_tex_h = 192
			q_ground = 128
			q_rocks = 140
			q_pebbles = 250
			q_stars = 200
			q_glow = false
			q_particles = false
			q_ssao = false
			q_lights = false
			q_msaa = Viewport.MSAA_DISABLED


func _bracket_for(age: int) -> int:
	for i in BRACKETS.size():
		var b: Dictionary = BRACKETS[i]
		if age <= int(b["max"]):
			return i
	return BRACKETS.size() - 1


func _br() -> Dictionary:
	return BRACKETS[bracket]


func _difficulty_for() -> float:
	return float(_br()["drain"]) * (1.0 + 0.08 * float(expedition - 1))


# ═══════════════════════════════════════════════════════════════════════════
#  SMALL BUILDERS
# ═══════════════════════════════════════════════════════════════════════════
func _mat(color: Color, metallic := 0.0, rough := 0.8, emit := Color.BLACK, emit_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emit_energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_energy
	return m


func _glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.3
	return m


func _additive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


func _add_mesh(parent: Node, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(r_top: float, r_bottom: float, h: float, seg := 24) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _sph(r: float, seg := 24, rings := 12, hemi := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r if hemi else r * 2.0
	m.is_hemisphere = hemi
	m.radial_segments = seg
	m.rings = rings
	return m


func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0 + 0.01)
	m.radial_segments = 16
	m.rings = 6
	return m


func _line_mesh(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var d := b - a
	var seg_len := d.length()
	if seg_len < 0.001:
		return
	var y := d / seg_len
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl(r, r, seg_len, 6)
	mi.material_override = mat
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(mi)


func _make_particles(amount: int, life: float, col: Color, smin: float, smax: float, additive := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	p.color = col
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = g
	return p


func _make_env(bg: Color, ambient: Color, ambient_energy: float) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_energy
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if q_glow:
		e.glow_enabled = true
		e.glow_intensity = 0.8
		e.glow_strength = 1.0
	return e


func _w(x: float, z: float) -> Vector3:
	return HAB_POS + Vector3(x, 0.0, z)


# ═══════════════════════════════════════════════════════════════════════════
#  PROCEDURAL TEXTURES
# ═══════════════════════════════════════════════════════════════════════════
func _make_mars_texture(w: int, h: int) -> ImageTexture:
	var big := FastNoiseLite.new()
	big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	big.seed = 4242
	big.frequency = 1.5
	big.fractal_type = FastNoiseLite.FRACTAL_FBM
	big.fractal_octaves = 5
	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.seed = 99
	fine.frequency = 9.0
	var rust_dark := Color(0.36, 0.17, 0.10)
	var rust_light := Color(0.80, 0.46, 0.26)
	var basalt := Color(0.20, 0.12, 0.10)
	var ice := Color(0.95, 0.93, 0.92)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var lat := (0.5 - (float(y) + 0.5) / float(h)) * PI
		var cl := cos(lat)
		var sl := sin(lat)
		for x in w:
			var lon := ((float(x) + 0.5) / float(w) - 0.5) * TAU
			var px := cl * sin(lon)
			var pz := cl * cos(lon)
			var n := big.get_noise_3d(px, sl, pz)
			var d := fine.get_noise_3d(px, sl, pz)
			var t := clampf(n * 0.5 + 0.5 + d * 0.10, 0.0, 1.0)
			var col := rust_dark.lerp(rust_light, smoothstep(0.25, 0.75, t))
			if n < -0.22:
				col = col.lerp(basalt, clampf((-0.22 - n) * 2.4, 0.0, 1.0) * 0.8)
			col = col.lerp(ice, smoothstep(0.86, 0.94, absf(sl)))
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_ground_textures(size: int) -> Array:
	var a := FastNoiseLite.new()
	a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	a.seed = 77
	a.frequency = 0.02
	a.fractal_type = FastNoiseLite.FRACTAL_FBM
	a.fractal_octaves = 4
	var b := FastNoiseLite.new()
	b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	b.seed = 78
	b.frequency = 0.16
	var base := Color(0.60, 0.33, 0.19)
	var dark := Color(0.38, 0.20, 0.12)
	var light := Color(0.76, 0.48, 0.29)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var bump := Image.create(size, size, false, Image.FORMAT_RGB8)
	var s := float(size)
	for y in size:
		var fy := float(y) / s
		for x in size:
			var fx := float(x) / s
			# 4-sample blend => seamless tiling
			var big := lerpf(
				lerpf(a.get_noise_2d(x, y), a.get_noise_2d(x - size, y), fx),
				lerpf(a.get_noise_2d(x, y - size), a.get_noise_2d(x - size, y - size), fx), fy)
			var grain := lerpf(
				lerpf(b.get_noise_2d(x, y), b.get_noise_2d(x - size, y), fx),
				lerpf(b.get_noise_2d(x, y - size), b.get_noise_2d(x - size, y - size), fx), fy)
			var ripple := sin(fx * TAU * 12.0 + fy * TAU * 3.0 + big * 6.0) * 0.5 + 0.5
			var t := clampf(big * 1.6 + 0.5, 0.0, 1.0)
			var col := dark.lerp(base, smoothstep(0.0, 0.5, t)).lerp(light, smoothstep(0.5, 1.0, t))
			col = col * (1.0 + grain * 0.18 + (ripple - 0.5) * 0.06)
			img.set_pixel(x, y, col)
			var hgt := clampf(0.5 + big * 0.6 + grain * 0.25 + (ripple - 0.5) * 0.25, 0.0, 1.0)
			bump.set_pixel(x, y, Color(hgt, hgt, hgt))
	img.generate_mipmaps()
	bump.bump_map_to_normal_map(6.0)
	bump.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(bump)]


# ═══════════════════════════════════════════════════════════════════════════
#  MENU WORLD  (spinning Mars + Gale beacon)
# ═══════════════════════════════════════════════════════════════════════════
func _build_menu_world() -> void:
	menu_root = Node3D.new()
	menu_root.name = "MenuWorld"
	add_child(menu_root)

	var star_mm := MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	star_mm.mesh = _sph(0.12, 4, 2)
	star_mm.instance_count = q_stars
	for i in q_stars:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if dir.length() < 0.01:
			dir = Vector3.UP
		var s := rng.randf_range(0.4, 1.5)
		star_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), dir.normalized() * 95.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = star_mm
	stars.material_override = _mat(Color(1, 0.95, 0.9), 0.0, 1.0, Color(1, 0.95, 0.9), 2.0)
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	menu_root.add_child(stars)

	globe_spin = Node3D.new()
	menu_root.add_child(globe_spin)
	var gm := _mat(Color.WHITE, 0.0, 1.0)
	gm.albedo_texture = mars_tex
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	gm.rim_enabled = true
	gm.rim = 0.7
	gm.rim_tint = 0.6
	_add_mesh(globe_spin, _sph(GLOBE_RADIUS, q_globe_seg, q_globe_rings), gm)

	var sh := Shader.new()
	sh.code = ATMO_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	var atmo := _add_mesh(menu_root, _sph(GLOBE_RADIUS * 1.04, maxi(q_globe_seg / 2, 32), maxi(q_globe_rings / 2, 16)), smat)
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var lat := deg_to_rad(GALE_LAT_DEG)
	var lon := deg_to_rad(GALE_LON_DEG)
	var n := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var bx := ref.cross(n).normalized()
	var bz := bx.cross(n).normalized()
	beacon_pin = Node3D.new()
	beacon_pin.transform = Transform3D(Basis(bx, n, bz), n * GLOBE_RADIUS)
	globe_spin.add_child(beacon_pin)
	var red := _mat(Color(1.0, 0.15, 0.1), 0.0, 0.4, Color(1.0, 0.15, 0.1), 4.0)
	_add_mesh(beacon_pin, _cyl(0.02, 0.02, 0.7, 8), red, Vector3(0, 0.35, 0))
	_add_mesh(beacon_pin, _sph(0.09, 16, 8), red, Vector3(0, 0.72, 0))
	beacon_halo = _add_mesh(beacon_pin, _sph(0.2, 16, 8), _additive(Color(1.0, 0.2, 0.1, 0.35)), Vector3(0, 0.72, 0))
	beacon_ring_mat = StandardMaterial3D.new()
	beacon_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_ring_mat.albedo_color = Color(1.0, 0.3, 0.2, 1.0)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.2
	torus.rings = 32
	torus.ring_segments = 8
	beacon_ring = _add_mesh(beacon_pin, torus, beacon_ring_mat, Vector3(0, 0.02, 0))
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.25, 0.15)
	bl.light_energy = 1.6
	bl.omni_range = 2.5
	bl.position = Vector3(0, 0.75, 0)
	beacon_pin.add_child(bl)

	menu_pivot = Node3D.new()
	menu_root.add_child(menu_pivot)
	menu_camera = Camera3D.new()
	menu_camera.fov = 42.0
	menu_camera.far = 400.0
	menu_camera.position = Vector3(0, 0, menu_dist)
	menu_camera.environment = _make_env(Color(0.008, 0.004, 0.012), Color(0.20, 0.10, 0.08), 0.35)
	menu_pivot.add_child(menu_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-18.0, 38.0, 0.0)
	key.light_color = Color(1.0, 0.93, 0.85)
	key.light_energy = 1.7
	menu_pivot.add_child(key)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(14.0, 200.0, 0.0)
	back.light_color = Color(1.0, 0.45, 0.25)
	back.light_energy = 0.55
	menu_pivot.add_child(back)


func _process_menu(delta: float) -> void:
	globe_spin.rotate_y(delta * 0.12)
	if not dragging:
		menu_yaw += delta * 0.03
	menu_dist = lerpf(menu_dist, menu_dist_target, clampf(delta * 5.0, 0.0, 1.0))
	menu_camera.position.z = menu_dist
	menu_pivot.rotation = Vector3(menu_pitch, menu_yaw, 0.0)
	var s := 1.0 + 0.35 * sin(time_accum * 4.0)
	beacon_halo.scale = Vector3(s, s, s)
	var f := fmod(time_accum * 0.9, 1.0)
	var rs := 1.0 + f * 2.6
	beacon_ring.scale = Vector3(rs, 1.0, rs)
	beacon_ring_mat.albedo_color = Color(1.0, 0.3, 0.2, 1.0 - f)
	var wp := beacon_pin.global_position
	var out_n := (wp - globe_spin.global_position).normalized()
	var to_cam := (menu_camera.global_position - wp).normalized()
	var facing := out_n.dot(to_cam) > 0.12 and not menu_camera.is_position_behind(wp)
	pin_label.visible = facing
	if facing:
		pin_label.position = menu_camera.unproject_position(wp) + Vector2(20.0, -44.0)


# ═══════════════════════════════════════════════════════════════════════════
#  SURFACE WORLD  (flat crater floor — the old rim / Mount Sharp relief is gone)
# ═══════════════════════════════════════════════════════════════════════════
func _build_surface_world() -> void:
	surface_root = Node3D.new()
	surface_root.name = "SurfaceWorld"
	add_child(surface_root)
	base_rect = Rect2(HAB_POS.x + BASE_MIN.x, HAB_POS.z + BASE_MIN.y, BASE_MAX.x - BASE_MIN.x, BASE_MAX.y - BASE_MIN.y)

	surface_env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.20, 0.18)
	sky_mat.sky_horizon_color = Color(0.86, 0.62, 0.44)
	sky_mat.ground_horizon_color = Color(0.74, 0.50, 0.36)
	sky_mat.ground_bottom_color = Color(0.40, 0.26, 0.19)
	sky_mat.sky_curve = 0.15
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	surface_env.background_mode = Environment.BG_SKY
	surface_env.sky = sky
	surface_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	surface_env.ambient_light_color = Color(0.62, 0.44, 0.34)
	surface_env.ambient_light_energy = 0.75
	surface_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	surface_env.tonemap_exposure = 1.05
	surface_env.fog_enabled = true
	surface_env.fog_light_color = COL_FOG_CLEAR
	surface_env.fog_density = FOG_BASE
	surface_env.fog_sky_affect = 0.35
	surface_env.adjustment_enabled = true
	surface_env.adjustment_contrast = 1.08
	surface_env.adjustment_saturation = 1.12
	if q_glow:
		surface_env.glow_enabled = true
		surface_env.glow_intensity = 0.65
		surface_env.glow_bloom = 0.06
	if q_ssao:
		surface_env.ssao_enabled = true
		surface_env.ssao_radius = 1.2
		surface_env.ssao_intensity = 1.6
	if q_volumetric:
		surface_env.volumetric_fog_enabled = true
		surface_env.volumetric_fog_density = 0.005
		surface_env.volumetric_fog_albedo = Color(0.88, 0.62, 0.46)
		surface_env.volumetric_fog_length = 90.0

	surface_camera = Camera3D.new()
	surface_camera.fov = 65.0
	surface_camera.near = 0.1
	surface_camera.far = 3000.0
	surface_camera.environment = surface_env
	surface_root.add_child(surface_camera)

	surface_sun = DirectionalLight3D.new()
	surface_sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	surface_sun.light_color = Color(1.0, 0.88, 0.75)
	surface_sun.light_energy = 1.25
	surface_sun.shadow_enabled = q_shadows
	surface_sun.shadow_blur = 1.5
	surface_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	surface_sun.directional_shadow_max_distance = 120.0
	surface_root.add_child(surface_sun)

	var plane := PlaneMesh.new()
	plane.size = Vector2(1200, 1200)
	var tex := _make_ground_textures(q_ground)
	var gmat := _mat(Color.WHITE, 0.0, 1.0)
	gmat.albedo_texture = tex[0]
	gmat.normal_enabled = true
	gmat.normal_texture = tex[1]
	gmat.normal_scale = 0.8
	gmat.uv1_scale = Vector3(90, 90, 1)
	gmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_add_mesh(surface_root, plane, gmat).name = "CraterFloor"

	_build_habitat()
	_build_outdoor()
	_build_capsule()
	_build_rocks()
	_build_astronaut()
	_build_rover()
	_build_objective_marker()

	dust_particles = _make_particles(120, 2.2, Color(0.82, 0.55, 0.34, 0.2), 3.0, 7.0)
	dust_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust_particles.emission_box_extents = Vector3(25, 4, 25)
	dust_particles.direction = Vector3(1, 0.05, 0.25)
	dust_particles.spread = 12.0
	dust_particles.gravity = Vector3.ZERO
	dust_particles.initial_velocity_min = 20.0
	dust_particles.initial_velocity_max = 32.0
	dust_particles.position = Vector3(0, 0, -8)
	surface_camera.add_child(dust_particles)

	motes = _make_particles(60, 6.0, Color(1.0, 0.8, 0.6, 0.35), 0.04, 0.09)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(10, 4, 10)
	motes.direction = Vector3(1, 0.2, 0)
	motes.gravity = Vector3(0, -0.05, 0)
	motes.initial_velocity_min = 0.3
	motes.initial_velocity_max = 0.9
	motes.position = Vector3(0, 0, -5)
	motes.emitting = q_particles
	surface_camera.add_child(motes)

	burst_fx = _make_particles(40, 0.9, Color.WHITE, 0.12, 0.3, true)
	burst_fx.one_shot = true
	burst_fx.explosiveness = 0.95
	burst_fx.direction = Vector3.UP
	burst_fx.spread = 70.0
	burst_fx.initial_velocity_min = 3.0
	burst_fx.initial_velocity_max = 7.0
	burst_fx.gravity = Vector3(0, -6, 0)
	surface_root.add_child(burst_fx)


func _build_rocks() -> void:
	var rock_mat := _mat(Color.WHITE, 0.0, 1.0)
	rock_mat.vertex_color_use_as_albedo = true
	for pass_i in 2:
		var count := q_rocks if pass_i == 0 else q_pebbles
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _sph(0.5, 8 if pass_i == 0 else 5, 5 if pass_i == 0 else 3)
		mm.instance_count = count
		for i in count:
			var pos := Vector3.ZERO
			for attempt in 20:
				var ang := rng.randf() * TAU
				var rad := sqrt(rng.randf()) * (300.0 if pass_i == 0 else 90.0)
				pos = Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
				if _clear_of_structures(pos, 1.5):
					break
			var sc := rng.randf_range(0.4, 2.2) if pass_i == 0 else rng.randf_range(0.08, 0.28)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * rng.randf_range(0.8, 1.5), sc * rng.randf_range(0.4, 0.8), sc))
			mm.set_instance_transform(i, Transform3D(b, Vector3(pos.x, 0.03, pos.z)))
			mm.set_instance_color(i, Color(0.28, 0.17, 0.12).lerp(Color(0.52, 0.32, 0.21), rng.randf()))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rock_mat
		if pass_i == 1:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface_root.add_child(mmi)


# ───────────────────────────── HABITAT ──────────────────────────────────────
func _build_habitat() -> void:
	hab_root = Node3D.new()
	hab_root.name = "BaseAlpha"
	hab_root.position = HAB_POS
	surface_root.add_child(hab_root)
	roof_root = Node3D.new()
	hab_root.add_child(roof_root)

	hm_hull = _mat(Color(0.90, 0.90, 0.92), 0.25, 0.45)
	hm_trim = _mat(Color(0.30, 0.32, 0.37), 0.6, 0.4)
	hm_glow = _mat(Color(0.2, 0.8, 1.0), 0.0, 0.3, Color(0.2, 0.8, 1.0), 2.2)
	hm_amber = _mat(Color(1.0, 0.7, 0.3), 0.0, 0.3, Color(1.0, 0.7, 0.3), 2.5)
	hm_dark = _mat(Color(0.14, 0.14, 0.17), 0.4, 0.6)
	hm_screen = _mat(Color(0.05, 0.12, 0.2), 0.2, 0.2, Color(0.25, 0.75, 1.0), 1.6)
	hm_wood = _mat(Color(0.55, 0.38, 0.24), 0.0, 0.7)

	_room("COMMAND HUB", -9, -9, 9, 9, Color(0.26, 0.27, 0.30), Color(0.75, 0.9, 1.0))
	_room("CREW QUARTERS", -25, -7, -9, 7, Color(0.42, 0.30, 0.22), Color(1.0, 0.8, 0.6))
	_room("GALLEY", 9, -7, 25, 7, Color(0.70, 0.70, 0.68), Color(1.0, 0.95, 0.85))
	_room("GREENHOUSE", -8, -27, 8, -9, Color(0.30, 0.22, 0.14), Color(1.0, 0.55, 0.95), true)
	_room("WORKSHOP", 9, -23, 25, -7, Color(0.35, 0.35, 0.36), Color(1.0, 0.85, 0.6))
	_room("STORAGE BAY", -25, -23, -9, -7, Color(0.24, 0.23, 0.24), Color(0.8, 0.85, 1.0))

	_hwall(9.0, -9.0, 9.0, [Vector2(0.0, 3.2)])       # hub south = airlock
	_hwall(-9.0, -9.0, 9.0, [Vector2(0.0, 3.0)])      # hub / greenhouse
	_vwall(-9.0, -9.0, 9.0, [Vector2(0.0, 3.0)])      # hub / quarters
	_vwall(9.0, -9.0, 9.0, [Vector2(0.0, 3.0)])       # hub / galley
	_hwall(-7.0, -25.0, -9.0, [Vector2(-17.0, 3.0)])  # quarters / storage
	_hwall(7.0, -25.0, -9.0, [])
	_vwall(-25.0, -7.0, 7.0, [])
	_hwall(-7.0, 9.0, 25.0, [Vector2(17.0, 3.0)])     # galley / workshop
	_hwall(7.0, 9.0, 25.0, [])
	_vwall(25.0, -7.0, 7.0, [])
	_vwall(-8.0, -27.0, -9.0, [])
	_vwall(8.0, -27.0, -9.0, [])
	_hwall(-27.0, -8.0, 8.0, [])
	_hwall(-23.0, 9.0, 25.0, [])
	_vwall(25.0, -23.0, -7.0, [])
	_vwall(9.0, -23.0, -9.0, [])
	_hwall(-23.0, -25.0, -9.0, [])
	_vwall(-25.0, -23.0, -7.0, [Vector2(-15.0, 3.6)]) # storage bay exterior door
	_vwall(-9.0, -23.0, -9.0, [])

	# central dome on the roof
	_add_mesh(roof_root, _sph(6.5, 40, 12, true), hm_hull, Vector3(0, WALL_H + 0.3, 0))
	_add_mesh(roof_root, _cyl(6.6, 6.6, 0.3, 40), hm_glow, Vector3(0, WALL_H + 0.45, 0))
	_add_mesh(roof_root, _cyl(1.4, 1.4, 0.3, 24), _glass(Color(0.6, 0.9, 1.0, 0.5)), Vector3(0, WALL_H + 6.7, 0))

	_build_hub_props()
	_build_quarters_props()
	_build_galley_props()
	_build_greenhouse_props()
	_build_workshop_props()
	_build_storage_props()


func _room(title: String, x0: float, z0: float, x1: float, z1: float, floor_col: Color, light_col: Color, glass := false) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var sx := x1 - x0
	var sz := z1 - z0
	_add_mesh(hab_root, _box(Vector3(sx, 0.1, sz)), _mat(floor_col, 0.15, 0.7), Vector3(cx, 0.05, cz))
	var roof_mat: Material = _glass(Color(0.6, 0.9, 1.0, 0.3)) if glass else hm_hull
	_add_mesh(roof_root, _box(Vector3(sx + 0.4, 0.3, sz + 0.4)), roof_mat, Vector3(cx, WALL_H + 0.15, cz))
	_add_mesh(roof_root, _box(Vector3(sx * 0.6, 0.06, 0.4)), hm_glow, Vector3(cx, WALL_H + 0.33, cz))
	if q_lights:
		var l := OmniLight3D.new()
		l.light_color = light_col
		l.light_energy = 1.7
		l.omni_range = maxf(sx, sz) * 0.85
		l.position = Vector3(cx, WALL_H - 0.4, cz)
		hab_root.add_child(l)
	rooms.append({"name": title, "rect": Rect2(HAB_POS.x + x0, HAB_POS.z + z0, sx, sz)})


func _wall_seg(x0: float, z0: float, x1: float, z1: float) -> void:
	var sx := maxf(absf(x1 - x0), 0.35)
	var sz := maxf(absf(z1 - z0), 0.35)
	var c := Vector3((x0 + x1) * 0.5, WALL_H * 0.5, (z0 + z1) * 0.5)
	_add_mesh(hab_root, _box(Vector3(sx, WALL_H, sz)), hm_hull, c)
	_add_mesh(hab_root, _box(Vector3(sx + 0.06, 0.35, sz + 0.06)), hm_trim, Vector3(c.x, 0.18, c.z))
	_add_mesh(hab_root, _box(Vector3(sx + 0.04, 0.12, sz + 0.04)), hm_glow, Vector3(c.x, WALL_H - 0.35, c.z))
	_add_rect_local(c.x, c.z, sx, sz)


func _door_frame(c: Vector3, w: float, along_x: bool) -> void:
	var off := w * 0.5 + 0.15
	var post := Vector3(0.3, WALL_H, 0.5) if along_x else Vector3(0.5, WALL_H, 0.3)
	for sgn in [-1.0, 1.0]:
		var p := Vector3(c.x + off * sgn, WALL_H * 0.5, c.z) if along_x else Vector3(c.x, WALL_H * 0.5, c.z + off * sgn)
		_add_mesh(hab_root, _box(post), hm_trim, p)
	var lintel := Vector3(w, 0.6, 0.45) if along_x else Vector3(0.45, 0.6, w)
	_add_mesh(hab_root, _box(lintel), hm_trim, Vector3(c.x, WALL_H - 0.3, c.z))
	var strip := Vector3(w, 0.08, 0.5) if along_x else Vector3(0.5, 0.08, w)
	_add_mesh(hab_root, _box(strip), hm_amber, Vector3(c.x, WALL_H - 0.62, c.z))


func _hwall(z: float, x0: float, x1: float, gaps: Array) -> void:
	var cur := x0
	for g in gaps:
		var gv: Vector2 = g
		var a := gv.x - gv.y * 0.5
		if a > cur + 0.05:
			_wall_seg(cur, z, a, z)
		_door_frame(Vector3(gv.x, 0.0, z), gv.y, true)
		cur = gv.x + gv.y * 0.5
	if x1 > cur + 0.05:
		_wall_seg(cur, z, x1, z)


func _vwall(x: float, z0: float, z1: float, gaps: Array) -> void:
	var cur := z0
	for g in gaps:
		var gv: Vector2 = g
		var a := gv.x - gv.y * 0.5
		if a > cur + 0.05:
			_wall_seg(x, cur, x, a)
		_door_frame(Vector3(x, 0.0, gv.x), gv.y, false)
		cur = gv.x + gv.y * 0.5
	if z1 > cur + 0.05:
		_wall_seg(x, cur, x, z1)


func _pbox(size: Vector3, mat: Material, lp: Vector3, collide := false) -> MeshInstance3D:
	var mi := _add_mesh(hab_root, _box(size), mat, lp)
	if collide:
		_add_rect_local(lp.x, lp.z, size.x, size.z)
	return mi


func _plant_pot(lp: Vector3) -> void:
	_add_mesh(hab_root, _cyl(0.45, 0.35, 0.7, 16), hm_trim, lp + Vector3(0, 0.35, 0))
	var leaf := _mat(Color(0.2, 0.55, 0.25), 0.0, 0.8)
	for i in 4:
		var o := Vector3(rng.randf_range(-0.25, 0.25), 0.9 + float(i) * 0.18, rng.randf_range(-0.25, 0.25))
		_add_mesh(hab_root, _sph(0.38 - float(i) * 0.05, 10, 6), leaf, lp + o)
	_add_circle(HAB_POS.x + lp.x, HAB_POS.z + lp.z, 0.6)


func _sign(text: String, lp: Vector3, rot_y: float, size := 48, col := Color(0.1, 0.1, 0.15)) -> void:
	var s := Label3D.new()
	s.text = text
	s.font_size = size
	s.pixel_size = 0.01
	s.modulate = col
	s.outline_size = 0
	s.position = lp
	s.rotation_degrees = Vector3(0, rot_y, 0)
	hab_root.add_child(s)


func _build_hub_props() -> void:
	# holo-table with spinning Mars hologram
	_add_mesh(hab_root, _cyl(1.45, 1.7, 0.9, 32), hm_trim, Vector3(0, 0.45, 0))
	_add_mesh(hab_root, _cyl(1.5, 1.5, 0.07, 32), hm_glow, Vector3(0, 0.93, 0))
	_add_mesh(hab_root, _cyl(0.9, 1.3, 1.1, 24), _additive(Color(0.2, 0.7, 1.0, 0.12)), Vector3(0, 1.5, 0))
	holo_globe = Node3D.new()
	holo_globe.position = Vector3(0, 2.15, 0)
	hab_root.add_child(holo_globe)
	var gm := _mat(Color.WHITE, 0.0, 0.8, Color(1.0, 0.55, 0.35), 0.5)
	gm.albedo_texture = mars_tex
	_add_mesh(holo_globe, _sph(0.7, 32, 16), gm)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.95
	ring.outer_radius = 1.0
	_add_mesh(holo_globe, ring, hm_glow, Vector3.ZERO, Vector3(18, 0, 0))
	_add_circle(HAB_POS.x, HAB_POS.z, 1.9)
	var floor_ring := TorusMesh.new()
	floor_ring.inner_radius = 4.0
	floor_ring.outer_radius = 4.2
	floor_ring.rings = 64
	_add_mesh(hab_root, floor_ring, hm_amber, Vector3(0, 0.1, 0)).scale = Vector3(1, 0.2, 1)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var px: float = sx * 5.0
			var pz: float = sz * 5.0
			_add_mesh(hab_root, _cyl(0.28, 0.32, WALL_H, 16), hm_trim, Vector3(px, WALL_H * 0.5, pz))
			_add_mesh(hab_root, _cyl(0.33, 0.33, 0.1, 16), hm_glow, Vector3(px, 2.4, pz))
			_add_circle(HAB_POS.x + px, HAB_POS.z + pz, 0.4)
	# mission control terminal
	_pbox(Vector3(2.4, 1.0, 0.9), hm_trim, Vector3(-6.0, 0.5, -7.6), true)
	_add_mesh(hab_root, _box(Vector3(2.2, 0.9, 0.06)), hm_screen, Vector3(-6.0, 1.55, -7.85), Vector3(-15, 0, 0))
	_add_interact("terminal", _w(-6.0, -6.4), "Mission Control terminal", 2.0)
	_add_mesh(hab_root, _box(Vector3(3.0, 1.6, 0.05)), hm_screen, Vector3(5.0, 1.8, -8.8))
	# benches
	for bx in [-6.0, 6.0]:
		var bxf: float = bx
		_pbox(Vector3(3.0, 0.45, 0.9), hm_dark, Vector3(bxf, 0.25, 7.8), true)
		_add_mesh(hab_root, _box(Vector3(2.9, 0.12, 0.85)), _mat(Color(0.9, 0.42, 0.15), 0.0, 0.7), Vector3(bxf, 0.52, 7.8))
	_plant_pot(Vector3(7.8, 0, -7.8))
	_plant_pot(Vector3(7.8, 0, 4.0))
	_plant_pot(Vector3(-7.8, 0, 4.0))
	# airlock porch outside
	_sign("BASE ALPHA  •  GALE OUTPOST", Vector3(0, 3.9, 9.25), 0.0)
	for px in [-2.4, 2.4]:
		var pxf: float = px
		_add_mesh(hab_root, _cyl(0.12, 0.12, 3.0, 10), hm_trim, Vector3(pxf, 1.5, 11.6))
		_add_circle(HAB_POS.x + pxf, HAB_POS.z + 11.6, 0.3)
	_add_mesh(hab_root, _box(Vector3(5.4, 0.15, 3.0)), hm_hull, Vector3(0, 3.05, 10.6))
	_add_mesh(hab_root, _box(Vector3(5.0, 0.05, 0.2)), hm_amber, Vector3(0, 2.96, 11.9))
	var door_light := OmniLight3D.new()
	door_light.light_color = Color(1.0, 0.75, 0.45)
	door_light.light_energy = 2.4
	door_light.omni_range = 12.0
	door_light.position = Vector3(0, 2.7, 10.8)
	hab_root.add_child(door_light)


func _build_quarters_props() -> void:
	var mattress := _mat(Color(0.25, 0.35, 0.6), 0.0, 0.9)
	var pillow := _mat(Color(0.95, 0.95, 0.95), 0.0, 0.9)
	var blanket := _mat(Color(0.9, 0.45, 0.2), 0.0, 0.9)
	for i in 4:
		var bx := -22.5 + float(i) * 3.2
		var bz := 5.8
		_pbox(Vector3(2.4, 0.45, 1.3), hm_trim, Vector3(bx, 0.25, bz), true)
		_add_mesh(hab_root, _box(Vector3(2.3, 0.2, 1.2)), mattress, Vector3(bx, 0.57, bz))
		_add_mesh(hab_root, _box(Vector3(1.4, 0.06, 1.22)), blanket, Vector3(bx + 0.4, 0.69, bz))
		_add_mesh(hab_root, _box(Vector3(0.5, 0.15, 0.8)), pillow, Vector3(bx - 0.85, 0.74, bz))
		for cx in [-1.15, 1.15]:
			for cz in [-0.6, 0.6]:
				var cxf: float = cx
				var czf: float = cz
				_add_mesh(hab_root, _cyl(0.05, 0.05, 2.1, 6), hm_trim, Vector3(bx + cxf, 1.05, bz + czf))
		_add_mesh(hab_root, _box(Vector3(2.4, 0.15, 1.3)), hm_trim, Vector3(bx, 1.55, bz))
		_add_mesh(hab_root, _box(Vector3(2.3, 0.18, 1.2)), mattress, Vector3(bx, 1.72, bz))
		_add_interact("bunk", _w(bx, 4.5), "Sleep in bunk", 1.7)
	# lockers
	var locker := _mat(Color(0.45, 0.5, 0.58), 0.6, 0.35)
	for i in 5:
		var lz := -5.6 + float(i) * 0.95
		_pbox(Vector3(0.7, 2.1, 0.9), locker, Vector3(-24.4, 1.05, lz))
		var hmat: StandardMaterial3D = hm_amber if i == 2 else hm_glow
		_add_mesh(hab_root, _box(Vector3(0.05, 0.3, 0.06)), hmat, Vector3(-24.03, 1.1, lz + 0.3))
	_add_rect_local(-24.4, -3.7, 0.7, 4.8)
	_add_interact("locker", _w(-23.3, -3.7), "Open your locker (customise)", 2.0)
	# desk
	_pbox(Vector3(2.6, 0.08, 1.1), hm_wood, Vector3(-12.0, 0.85, -5.9), true)
	for lx in [-1.2, 1.2]:
		var lxf: float = lx
		_add_mesh(hab_root, _box(Vector3(0.08, 0.85, 1.0)), hm_trim, Vector3(-12.0 + lxf, 0.42, -5.9))
	_add_mesh(hab_root, _box(Vector3(1.1, 0.65, 0.05)), hm_screen, Vector3(-12.0, 1.3, -6.3))
	_add_mesh(hab_root, _box(Vector3(0.6, 0.08, 0.6)), hm_dark, Vector3(-12.0, 0.5, -4.8))
	_add_mesh(hab_root, _sph(0.12, 10, 6), hm_amber, Vector3(-13.0, 1.25, -6.1))
	# rug, shelf, window
	_add_mesh(hab_root, _box(Vector3(5.0, 0.02, 3.4)), _mat(Color(0.55, 0.22, 0.18), 0.0, 1.0), Vector3(-17.0, 0.11, 0.5))
	_pbox(Vector3(0.5, 1.8, 2.0), hm_wood, Vector3(-24.5, 0.9, 2.2), true)
	for i in 8:
		var bc := Color.from_hsv(rng.randf(), 0.6, 0.8)
		_add_mesh(hab_root, _box(Vector3(0.3, 0.38, 0.12)), _mat(bc, 0.0, 0.8), Vector3(-24.35, 0.6 + float(i / 4) * 0.6, 1.5 + float(i % 4) * 0.4))
	_add_mesh(hab_root, _box(Vector3(0.05, 1.2, 2.6)), _mat(Color(0.9, 0.55, 0.35), 0.0, 0.2, Color(1.0, 0.55, 0.3), 0.9), Vector3(-24.8, 1.8, -0.3))


func _build_galley_props() -> void:
	var counter := _mat(Color(0.75, 0.76, 0.8), 0.5, 0.3)
	_pbox(Vector3(1.2, 1.0, 7.5), hm_trim, Vector3(24.1, 0.5, -1.25), true)
	_add_mesh(hab_root, _box(Vector3(1.3, 0.08, 7.6)), counter, Vector3(24.1, 1.04, -1.25))
	_add_mesh(hab_root, _box(Vector3(0.9, 1.1, 1.2)), hm_hull, Vector3(24.1, 1.63, -3.5))
	_add_mesh(hab_root, _box(Vector3(0.05, 0.4, 0.6)), _mat(Color(0.2, 1.0, 0.4), 0.0, 0.3, Color(0.2, 1.0, 0.4), 2.0), Vector3(23.63, 1.75, -3.5))
	_add_interact("dispenser", _w(22.8, -3.5), "Food dispenser (Ration Pack)", 1.8)
	_add_mesh(hab_root, _box(Vector3(0.5, 0.6, 0.5)), hm_dark, Vector3(24.1, 1.38, 0.5))
	_add_mesh(hab_root, _cyl(0.08, 0.07, 0.15, 10), pillow_mat(), Vector3(23.8, 1.16, 0.5))
	_add_interact("coffee", _w(22.8, 0.5), "Coffee machine (+Rest)", 1.6)
	_add_mesh(hab_root, _box(Vector3(0.8, 0.1, 0.9)), hm_dark, Vector3(24.1, 1.05, -1.5))
	_add_mesh(hab_root, _cyl(0.03, 0.03, 0.4, 6), counter, Vector3(24.35, 1.25, -1.5))
	_pbox(Vector3(1.3, 2.3, 1.4), counter, Vector3(24.0, 1.15, 4.6), true)
	_add_mesh(hab_root, _box(Vector3(0.05, 0.9, 0.06)), hm_glow, Vector3(23.33, 1.4, 4.1))
	_add_interact("fridge", _w(22.7, 4.6), "Fridge (fresh food)", 1.8)
	_add_mesh(hab_root, _cyl(1.5, 1.5, 0.1, 32), hm_wood, Vector3(15, 0.9, 0))
	_add_mesh(hab_root, _cyl(0.15, 0.4, 0.85, 12), hm_trim, Vector3(15, 0.43, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		_add_mesh(hab_root, _box(Vector3(0.55, 0.5, 0.55)), _mat(Color(0.9, 0.42, 0.15), 0.0, 0.7), Vector3(15 + cos(a) * 2.0, 0.25, sin(a) * 2.0))
	_add_circle(HAB_POS.x + 15.0, HAB_POS.z, 2.2)
	_add_mesh(hab_root, _cyl(0.01, 0.01, 0.6, 4), hm_trim, Vector3(15, 2.9, 0))
	_add_mesh(hab_root, _sph(0.3, 16, 8, true), hm_amber, Vector3(15, 2.45, 0), Vector3(180, 0, 0))
	_add_mesh(hab_root, _box(Vector3(2.4, 1.2, 0.05)), hm_screen, Vector3(16.0, 1.9, 6.78))
	_plant_pot(Vector3(10.6, 0, -5.6))


func pillow_mat() -> StandardMaterial3D:
	return _mat(Color(0.95, 0.95, 0.95), 0.0, 0.6)


func _build_greenhouse_props() -> void:
	var planter := _mat(Color(0.85, 0.85, 0.88), 0.3, 0.5)
	var soil := _mat(Color(0.22, 0.14, 0.09), 0.0, 1.0)
	var stem := _mat(Color(0.25, 0.5, 0.2), 0.0, 0.8)
	var leaf := _mat(Color(0.3, 0.75, 0.3), 0.0, 0.7)
	var fruit := _mat(Color(0.95, 0.25, 0.15), 0.0, 0.4)
	var grow := _mat(Color(1.0, 0.3, 0.9), 0.0, 0.3, Color(1.0, 0.3, 0.9), 3.0)
	for col in [-4.5, 4.5]:
		var cx: float = col
		_add_mesh(hab_root, _box(Vector3(0.3, 0.08, 15.0)), grow, Vector3(cx, 2.75, -18.3))
		for row in 4:
			var pz := -12.5 - float(row) * 3.9
			_pbox(Vector3(2.6, 0.7, 2.8), planter, Vector3(cx, 0.35, pz), true)
			_add_mesh(hab_root, _box(Vector3(2.4, 0.05, 2.6)), soil, Vector3(cx, 0.72, pz))
			var pr := Node3D.new()
			pr.position = Vector3(cx, 0.72, pz)
			hab_root.add_child(pr)
			for k in 6:
				var ox := rng.randf_range(-0.9, 0.9)
				var oz := rng.randf_range(-1.0, 1.0)
				_add_mesh(pr, _cyl(0.03, 0.04, 0.5, 5), stem, Vector3(ox, 0.25, oz))
				_add_mesh(pr, _sph(0.28, 8, 5), leaf, Vector3(ox, 0.55, oz)).scale = Vector3(1, 0.7, 1)
				if k % 3 == 0:
					_add_mesh(pr, _sph(0.09, 8, 4), fruit, Vector3(ox + 0.15, 0.5, oz))
			_add_interact("plant", _w(signf(cx) * 2.5, pz), "Harvest Fresh Greens", 1.9, {"grow": rng.randf_range(0.6, 1.0), "plant_node": pr})
	for tx in [-6.9, 6.9]:
		var txf: float = tx
		_add_mesh(hab_root, _cyl(0.6, 0.6, 2.2, 16), _glass(Color(0.3, 0.6, 1.0, 0.55)), Vector3(txf, 1.1, -10.6))
		_add_circle(HAB_POS.x + txf, HAB_POS.z - 10.6, 0.7)
	_sign("GREENHOUSE", Vector3(0, 2.75, -8.8), 0.0, 40, Color(0.2, 0.6, 0.25))


func _build_workshop_props() -> void:
	_pbox(Vector3(3.4, 2.2, 1.6), hm_trim, Vector3(17.0, 1.1, -21.9), true)
	_add_mesh(hab_root, _box(Vector3(2.0, 0.9, 0.05)), _mat(Color(1.0, 0.5, 0.15), 0.0, 0.2, Color(1.0, 0.5, 0.15), 2.6), Vector3(17.0, 1.3, -21.08))
	_add_mesh(hab_root, _box(Vector3(3.6, 0.2, 1.8)), hm_amber, Vector3(17.0, 2.3, -21.9))
	for i in 6:
		var m: StandardMaterial3D = _mat(Color(1.0, 0.85, 0.1), 0.0, 0.6) if i % 2 == 0 else hm_dark
		_add_mesh(hab_root, _box(Vector3(0.6, 0.02, 1.0)), m, Vector3(15.5 + float(i) * 0.6, 0.11, -20.4))
	_add_interact("fabricator", _w(17.0, -20.0), "Fabricator (craft)", 2.2)
	_pbox(Vector3(1.2, 0.95, 4.5), hm_wood, Vector3(24.0, 0.48, -15.0), true)
	for i in 5:
		_add_mesh(hab_root, _box(Vector3(0.3, 0.15, 0.5)), _mat(Color.from_hsv(0.05 * float(i), 0.7, 0.8), 0.6, 0.4), Vector3(24.0, 1.03, -16.8 + float(i) * 0.8))
	_add_mesh(hab_root, _box(Vector3(0.05, 1.4, 3.0)), hm_dark, Vector3(9.22, 1.6, -15.0))
	for i in 6:
		_add_mesh(hab_root, _box(Vector3(0.06, 0.5, 0.1)), hm_trim, Vector3(9.3, 1.6, -16.2 + float(i) * 0.5))
	_pbox(Vector3(1.4, 1.6, 1.4), _glass(Color(0.6, 0.9, 1.0, 0.3)), Vector3(11.5, 0.8, -20.5), true)
	_add_mesh(hab_root, _box(Vector3(0.5, 0.5, 0.5)), hm_glow, Vector3(11.5, 0.6, -20.5))
	for i in 3:
		_add_mesh(hab_root, _cyl(0.5, 0.5, 0.45, 18), _mat(Color(0.09, 0.09, 0.1), 0.0, 0.9), Vector3(22.5, 0.25 + float(i) * 0.46, -9.2))
	_add_circle(HAB_POS.x + 22.5, HAB_POS.z - 9.2, 0.6)
	_sign("WORKSHOP", Vector3(17.0, 2.75, -7.2), 180.0, 40)


func _build_storage_props() -> void:
	for sx in [-22.0, -17.5, -13.0]:
		var sxf: float = sx
		_pbox(Vector3(3.6, 0.08, 1.0), hm_trim, Vector3(sxf, 0.9, -22.3), true)
		_add_mesh(hab_root, _box(Vector3(3.6, 0.08, 1.0)), hm_trim, Vector3(sxf, 1.8, -22.3))
		for k in 4:
			var cc := Color(0.75, 0.6, 0.35) if k % 2 == 0 else Color(0.4, 0.45, 0.5)
			_add_mesh(hab_root, _box(Vector3(0.7, 0.6, 0.7)), _mat(cc, 0.2, 0.7), Vector3(sxf - 1.2 + float(k) * 0.8, 1.25 + float(k % 2) * 0.9, -22.3))
	for i in 5:
		_pbox(Vector3(1.1, 1.0, 1.1), _mat(Color(0.75, 0.6, 0.35), 0.1, 0.8), Vector3(-11.0 - float(i % 2) * 1.3, 0.5 + float(i / 2) * 1.0 * 0.0, -10.0 - float(i) * 1.2), i < 3)
	_pbox(Vector3(0.5, 2.0, 2.4), hm_trim, Vector3(-9.7, 1.0, -15.0), true)
	for i in 3:
		_add_mesh(hab_root, _cyl(0.08, 0.12, 1.1, 10), hm_hull, Vector3(-10.05, 1.1, -15.8 + float(i) * 0.8))
		_add_mesh(hab_root, _sph(0.1, 8, 4), hm_amber, Vector3(-10.05, 0.5, -15.8 + float(i) * 0.8))
	_add_interact("drill_rack", _w(-10.9, -15.0), "Drill upgrade rack", 1.9)
	for i in 3:
		_add_mesh(hab_root, _cyl(0.4, 0.4, 1.0, 14), _mat(Color(0.85, 0.3, 0.12), 0.4, 0.5), Vector3(-23.6, 0.5, -9.0 - float(i) * 0.9))
	_add_rect_local(-23.6, -9.9, 0.9, 2.8)
	drone = Node3D.new()
	drone.position = Vector3(-17.0, 2.0, -15.0)
	hab_root.add_child(drone)
	_add_mesh(drone, _box(Vector3(0.6, 0.18, 0.6)), hm_hull)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		_add_mesh(drone, _cyl(0.22, 0.22, 0.03, 12), hm_trim, Vector3(cos(a) * 0.45, 0.1, sin(a) * 0.45))
	_add_mesh(drone, _sph(0.06, 8, 4), hm_glow, Vector3(0, -0.1, -0.3))
	_sign("STORAGE BAY", Vector3(-25.2, 3.0, -15.0), -90.0, 40)


# ───────────────────────────── OUTDOOR PROPS ────────────────────────────────
func _build_outdoor() -> void:
	var trim := hm_trim
	var amber := hm_amber
	# landing pad
	var pad := Node3D.new()
	pad.position = PAD_POS
	surface_root.add_child(pad)
	_add_mesh(pad, _cyl(8.0, 8.2, 0.14, 48), _mat(Color(0.5, 0.45, 0.42), 0.1, 0.85), Vector3(0, 0.07, 0))
	_add_mesh(pad, _cyl(7.4, 7.4, 0.16, 48), _mat(Color(0.32, 0.30, 0.30), 0.2, 0.8), Vector3(0, 0.08, 0))
	_add_mesh(pad, _box(Vector3(0.5, 0.18, 5.0)), amber, Vector3(-1.8, 0.09, 0))
	_add_mesh(pad, _box(Vector3(0.5, 0.18, 5.0)), amber, Vector3(1.8, 0.09, 0))
	_add_mesh(pad, _box(Vector3(3.1, 0.18, 0.5)), amber, Vector3(0, 0.09, 0))
	pad_light_mat = _mat(Color(1.0, 0.3, 0.1), 0.0, 0.3, Color(1.0, 0.3, 0.1), 3.0)
	for i in 16:
		var a := TAU * float(i) / 16.0
		_add_mesh(pad, _sph(0.14, 8, 4), pad_light_mat, Vector3(cos(a) * 7.8, 0.2, sin(a) * 7.8))
	_add_circle(PAD_POS.x, PAD_POS.z, 2.2)   # capsule footprint
	# path lights pad -> airlock
	var z := 6.0
	while z > -10.0:
		for px in [-2.4, 2.4]:
			var pxf: float = px
			_add_mesh(surface_root, _cyl(0.06, 0.08, 0.6, 8), trim, Vector3(pxf, 0.3, z))
			_add_mesh(surface_root, _sph(0.09, 8, 4), hm_glow, Vector3(pxf, 0.65, z))
		z -= 3.0
	# solar farm
	var panel_mat := _mat(Color(0.08, 0.16, 0.42), 0.7, 0.2, Color(0.1, 0.3, 0.9), 0.25)
	for c in 3:
		for r in 4:
			var px := 36.0 + float(c) * 8.0
			var pz := -16.0 - float(r) * 7.0
			_add_mesh(surface_root, _box(Vector3(6.0, 0.12, 3.4)), panel_mat, Vector3(px, 1.9, pz), Vector3(-30, 0, 0))
			_add_mesh(surface_root, _box(Vector3(6.1, 0.05, 0.08)), trim, Vector3(px, 2.75, pz - 1.45), Vector3(-30, 0, 0))
			_add_mesh(surface_root, _cyl(0.1, 0.12, 1.8, 8), trim, Vector3(px, 0.9, pz))
			_add_circle(px, pz, 2.6)
	# fuel / water tanks
	for i in 4:
		var tx := -12.0 + float(i) * 8.0
		_add_mesh(surface_root, _cyl(1.6, 1.6, 4.0, 24), hm_hull, Vector3(tx, 2.0, -52.0))
		_add_mesh(surface_root, _sph(1.6, 24, 8, true), hm_hull, Vector3(tx, 4.0, -52.0))
		_add_mesh(surface_root, _cyl(1.65, 1.65, 0.3, 24), _mat(Color(0.9, 0.45, 0.15), 0.2, 0.5), Vector3(tx, 2.6, -52.0))
		_add_circle(tx, -52.0, 1.9)
	# antenna tower with blinking beacon
	var tower := Vector3(-34.0, 0.0, -6.0)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		_line_mesh(surface_root, tower + Vector3(cos(a) * 1.4, 0, sin(a) * 1.4), tower + Vector3(cos(a) * 0.3, 14.0, sin(a) * 0.3), 0.07, trim)
	for h in 5:
		_add_mesh(surface_root, _cyl(1.3 - float(h) * 0.22, 1.3 - float(h) * 0.22, 0.06, 8), trim, tower + Vector3(0, 2.5 + float(h) * 2.6, 0))
	_add_mesh(surface_root, _sph(1.3, 20, 8, true), hm_hull, tower + Vector3(0, 13.0, 0.6), Vector3(120, 0, 0))
	hab_beacon_mat = _mat(Color(1.0, 0.1, 0.1), 0.0, 0.3, Color(1.0, 0.1, 0.1), 2.0)
	_add_mesh(surface_root, _sph(0.2, 10, 6), hab_beacon_mat, tower + Vector3(0, 14.3, 0))
	_add_circle(tower.x, tower.z, 1.8)
	# comms dish
	var dish := Vector3(30.0, 0.0, -4.0)
	_add_mesh(surface_root, _cyl(0.4, 0.6, 3.0, 12), trim, dish + Vector3(0, 1.5, 0))
	var dish_mat := hm_hull.duplicate() as StandardMaterial3D
	dish_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(surface_root, _sph(2.6, 28, 10, true), dish_mat, dish + Vector3(0, 3.6, 0), Vector3(140, 30, 0))
	_add_circle(dish.x, dish.z, 1.0)
	# oxygen generator with spinning fans
	var o2 := Vector3(-16.0, 0.0, -6.0)
	_add_mesh(surface_root, _box(Vector3(3.2, 2.0, 2.2)), hm_hull, o2 + Vector3(0, 1.0, 0))
	_add_mesh(surface_root, _box(Vector3(3.25, 0.15, 2.25)), hm_glow, o2 + Vector3(0, 1.6, 0))
	for fx in [-0.8, 0.8]:
		var fxf: float = fx
		var fan := Node3D.new()
		fan.position = o2 + Vector3(fxf, 2.05, 0)
		surface_root.add_child(fan)
		_add_mesh(fan, _box(Vector3(1.2, 0.05, 0.18)), trim)
		_add_mesh(fan, _box(Vector3(0.18, 0.05, 1.2)), trim)
		o2_fans.append(fan)
	_add_rect_world(o2.x, o2.z, 3.2, 2.2)
	# flags & rover bay
	var flag_mat := _mat(Color(0.95, 0.42, 0.12), 0.0, 0.7)
	for fx in [-6.5, 6.5]:
		var fxf: float = fx
		_add_mesh(surface_root, _cyl(0.05, 0.05, 4.0, 8), trim, Vector3(fxf, 2.0, 5.0))
		_add_mesh(surface_root, _box(Vector3(1.4, 0.8, 0.03)), flag_mat, Vector3(fxf + 0.72, 3.5, 5.0))
		_add_circle(fxf, 5.0, 0.2)
	_add_mesh(surface_root, _box(Vector3(5.0, 0.06, 6.0)), _mat(Color(0.3, 0.29, 0.29), 0.2, 0.8), Vector3(ROVER_START.x, 0.03, ROVER_START.z))
	_add_mesh(surface_root, _box(Vector3(5.1, 0.08, 0.15)), amber, Vector3(ROVER_START.x, 0.04, ROVER_START.z + 3.0))
	_add_mesh(surface_root, _box(Vector3(5.1, 0.08, 0.15)), amber, Vector3(ROVER_START.x, 0.04, ROVER_START.z - 3.0))


# ───────────────────────────── DROP CAPSULE ─────────────────────────────────
func _build_capsule() -> void:
	capsule = Node3D.new()
	capsule.name = "Ares7Capsule"
	capsule.position = PAD_POS
	surface_root.add_child(capsule)
	var hull := _mat(Color(0.92, 0.92, 0.94), 0.3, 0.45)
	var shield := _mat(Color(0.32, 0.22, 0.16), 0.2, 0.9)
	var stripe := _mat(Color(0.95, 0.42, 0.12), 0.2, 0.5)
	var win := _mat(Color(0.1, 0.2, 0.3), 0.8, 0.1, Color(0.3, 0.7, 1.0), 0.8)
	_add_mesh(capsule, _cyl(2.0, 2.0, 0.35, 32), shield, Vector3(0, 0.38, 0))
	_add_mesh(capsule, _cyl(0.95, 1.9, 2.6, 32), hull, Vector3(0, 1.85, 0))
	_add_mesh(capsule, _cyl(1.86, 1.93, 0.22, 32), stripe, Vector3(0, 0.72, 0))
	_add_mesh(capsule, _cyl(0.6, 0.95, 0.45, 24), hm_dark, Vector3(0, 3.37, 0))
	_add_mesh(capsule, _cyl(0.45, 0.45, 0.25, 16), hull, Vector3(0, 3.72, 0))
	for a in [1.2, -1.2, PI]:
		var af: float = a
		_add_mesh(capsule, _box(Vector3(0.45, 0.35, 0.06)), win, Vector3(sin(af) * 1.36, 2.4, -cos(af) * 1.36), Vector3(20, rad_to_deg(-af), 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		_line_mesh(capsule, Vector3(cos(a) * 1.5, 1.0, sin(a) * 1.5), Vector3(cos(a) * 2.6, 0.08, sin(a) * 2.6), 0.07, hm_trim)
		_add_mesh(capsule, _cyl(0.3, 0.35, 0.08, 12), hm_trim, Vector3(cos(a) * 2.6, 0.04, sin(a) * 2.6))
	var lab := Label3D.new()
	lab.text = "ARES-7"
	lab.font_size = 96
	lab.pixel_size = 0.006
	lab.modulate = Color(0.1, 0.1, 0.15)
	lab.outline_size = 0
	lab.position = Vector3(1.55, 1.9, 0)
	lab.rotation_degrees = Vector3(0, 90, 20)
	capsule.add_child(lab)
	# hatch (faces -Z, toward the base)
	_add_mesh(capsule, _box(Vector3(1.15, 1.35, 0.05)), hm_dark, Vector3(0, 1.45, -1.55), Vector3(20, 0, 0))
	hatch_hinge = Node3D.new()
	hatch_hinge.position = Vector3(-0.58, 1.45, -1.63)
	capsule.add_child(hatch_hinge)
	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(20, 0, 0)
	hatch_hinge.add_child(tilt)
	_add_mesh(tilt, _box(Vector3(1.1, 1.3, 0.1)), hull, Vector3(0.55, 0, 0))
	_add_mesh(tilt, _cyl(0.18, 0.18, 0.12, 16), win, Vector3(0.55, 0.25, 0), Vector3(90, 0, 0))
	# re-entry glow, trail, retro flame
	capsule_glow = _add_mesh(capsule, _sph(2.4, 24, 12), _additive(Color(1.0, 0.45, 0.15, 0.55)), Vector3(0, 0.2, 0))
	capsule_glow.scale = Vector3(1.0, 0.55, 1.0)
	capsule_trail = _make_particles(90, 1.6, Color(1.0, 0.55, 0.2, 0.8), 1.5, 3.0, true)
	capsule_trail.direction = Vector3.UP
	capsule_trail.spread = 15.0
	capsule_trail.gravity = Vector3.ZERO
	capsule_trail.initial_velocity_min = 2.0
	capsule_trail.initial_velocity_max = 6.0
	capsule.add_child(capsule_trail)
	capsule_flame = _make_particles(70, 0.45, Color(1.0, 0.6, 0.25, 0.9), 0.5, 1.2, true)
	capsule_flame.direction = Vector3.DOWN
	capsule_flame.spread = 25.0
	capsule_flame.gravity = Vector3.ZERO
	capsule_flame.initial_velocity_min = 10.0
	capsule_flame.initial_velocity_max = 16.0
	capsule_flame.position = Vector3(0, 0.15, 0)
	capsule.add_child(capsule_flame)
	capsule_light = OmniLight3D.new()
	capsule_light.light_color = Color(1.0, 0.6, 0.3)
	capsule_light.omni_range = 20.0
	capsule_light.position = Vector3(0, -0.5, 0)
	capsule_light.visible = false
	capsule.add_child(capsule_light)
	# parachute (separate node so it can detach and drift away)
	chute = Node3D.new()
	surface_root.add_child(chute)
	var cm := _mat(Color(0.95, 0.45, 0.15), 0.0, 0.7)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(chute, _sph(6.0, 24, 8, true), cm)
	var band := TorusMesh.new()
	band.inner_radius = 5.8
	band.outer_radius = 6.1
	_add_mesh(chute, band, _mat(Color.WHITE, 0.0, 0.7))
	var line_mat := _mat(Color(0.9, 0.9, 0.9), 0.0, 0.8)
	for i in 8:
		var a := TAU * float(i) / 8.0
		_line_mesh(chute, Vector3(cos(a) * 5.9, 0, sin(a) * 5.9), Vector3(0, -10.3, 0), 0.03, line_mat)
	chute.visible = false
	landing_dust = _make_particles(140, 2.5, Color(0.8, 0.56, 0.38, 0.55), 3.0, 6.0)
	landing_dust.one_shot = true
	landing_dust.explosiveness = 0.95
	landing_dust.direction = Vector3(1, 0, 0)
	landing_dust.spread = 180.0
	landing_dust.flatness = 0.92
	landing_dust.initial_velocity_min = 9.0
	landing_dust.initial_velocity_max = 18.0
	landing_dust.damping_min = 6.0
	landing_dust.damping_max = 9.0
	landing_dust.gravity = Vector3(0, 0.3, 0)
	landing_dust.position = PAD_POS + Vector3(0, 0.4, 0)
	surface_root.add_child(landing_dust)


# ───────────────────────────── ASTRONAUT ────────────────────────────────────
func _make_limb(parent: Node3D, pivot_pos: Vector3, radius: float, length: float, mat: Material, end_mat: Material, end_r: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	_add_mesh(pivot, _cap(radius, length), mat, Vector3(0, -length * 0.5, 0))
	_add_mesh(pivot, _sph(end_r, 12, 6), end_mat, Vector3(0, -length, 0))
	return pivot


func _build_astronaut() -> void:
	astro = Node3D.new()
	astro.name = "Astronaut"
	surface_root.add_child(astro)
	astro_model = Node3D.new()
	astro.add_child(astro_model)
	suit_mat = _mat(Color(0.93, 0.93, 0.95), 0.1, 0.55)
	var dark := _mat(Color(0.20, 0.20, 0.24), 0.3, 0.6)
	visor_mat = _mat(Color(1.0, 0.78, 0.25), 1.0, 0.06, Color(0.9, 0.6, 0.1), 0.35)
	var pack := _mat(Color(0.62, 0.63, 0.68), 0.3, 0.6)
	accent_mat = _mat(Color(1.0, 0.4, 0.15), 0.0, 0.5, Color(1.0, 0.4, 0.15), 0.6)
	_add_mesh(astro_model, _cap(0.32, 1.3), suit_mat, Vector3(0, 0.15, 0))
	_add_mesh(astro_model, _sph(0.31, 24, 12), suit_mat, Vector3(0, 1.02, 0))
	_add_mesh(astro_model, _sph(0.24, 24, 12), visor_mat, Vector3(0, 1.03, -0.13)).scale = Vector3(1.0, 0.82, 0.7)
	_add_mesh(astro_model, _box(Vector3(0.5, 0.7, 0.26)), pack, Vector3(0, 0.3, 0.33))
	_add_mesh(astro_model, _box(Vector3(0.52, 0.08, 0.28)), accent_mat, Vector3(0, 0.55, 0.33))
	_add_mesh(astro_model, _box(Vector3(0.22, 0.14, 0.05)), accent_mat, Vector3(0, 0.5, -0.32))
	_add_mesh(astro_model, _cyl(0.325, 0.325, 0.1, 20), dark, Vector3(0, -0.05, 0))
	_add_mesh(astro_model, _cyl(0.33, 0.33, 0.06, 20), accent_mat, Vector3(0, 0.78, 0))
	arm_l = _make_limb(astro_model, Vector3(-0.42, 0.62, 0), 0.1, 0.55, suit_mat, dark, 0.11)
	arm_r = _make_limb(astro_model, Vector3(0.42, 0.62, 0), 0.1, 0.55, suit_mat, dark, 0.11)
	leg_l = _make_limb(astro_model, Vector3(-0.16, 0.0, 0), 0.13, 0.38, suit_mat, dark, 0.12)
	leg_r = _make_limb(astro_model, Vector3(0.16, 0.0, 0), 0.13, 0.38, suit_mat, dark, 0.12)
	helmet_light = SpotLight3D.new()
	helmet_light.position = Vector3(0, 1.2, -0.3)
	helmet_light.spot_range = 18.0
	helmet_light.spot_angle = 28.0
	helmet_light.light_energy = 2.5
	helmet_light.visible = false
	astro_model.add_child(helmet_light)
	callsign_label = Label3D.new()
	callsign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	callsign_label.font_size = 40
	callsign_label.pixel_size = 0.006
	callsign_label.outline_size = 10
	callsign_label.modulate = Color(1.0, 0.85, 0.6)
	callsign_label.position = Vector3(0, 1.75, 0)
	astro.add_child(callsign_label)
	step_dust = _make_particles(24, 0.9, Color(0.75, 0.52, 0.36, 0.5), 0.25, 0.6)
	step_dust.direction = Vector3.UP
	step_dust.spread = 60.0
	step_dust.initial_velocity_min = 0.5
	step_dust.initial_velocity_max = 1.2
	step_dust.gravity = Vector3(0, -0.6, 0)
	step_dust.position = Vector3(0, -0.45, 0)
	astro.add_child(step_dust)


# ───────────────────────────── ROVER ────────────────────────────────────────
func _build_rover() -> void:
	rover = Node3D.new()
	rover.name = "AresScoutRover"
	rover.position = ROVER_START
	rover.rotation.y = rover_heading
	surface_root.add_child(rover)
	var body := _mat(Color(0.92, 0.90, 0.86), 0.25, 0.5)
	rover_paint_mat = _mat(Color(0.95, 0.42, 0.12), 0.3, 0.4)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.4, 0.7)
	var tire := _mat(Color(0.09, 0.09, 0.10), 0.0, 0.9)
	var glass := _mat(Color(0.15, 0.20, 0.28), 0.8, 0.1)
	var panel_mat := _mat(Color(0.10, 0.20, 0.50), 0.6, 0.25, Color(0.1, 0.3, 0.9), 0.25)
	var lamp := _mat(Color(1.0, 1.0, 0.85), 0.0, 0.2, Color(1.0, 0.95, 0.8), 3.0)
	_add_mesh(rover, _box(Vector3(2.0, 0.45, 3.8)), body, Vector3(0, 0.55, 0))
	_add_mesh(rover, _box(Vector3(2.04, 0.2, 3.7)), dark, Vector3(0, 0.35, 0))
	_add_mesh(rover, _box(Vector3(2.02, 0.14, 3.0)), rover_paint_mat, Vector3(0, 0.62, 0.2))
	_add_mesh(rover, _box(Vector3(1.6, 0.7, 1.6)), body, Vector3(0, 1.1, 0.3))
	_add_mesh(rover, _box(Vector3(1.62, 0.12, 1.62)), rover_paint_mat, Vector3(0, 1.4, 0.3))
	_add_mesh(rover, _box(Vector3(1.5, 0.4, 0.05)), glass, Vector3(0, 1.2, -0.52))
	_add_mesh(rover, _box(Vector3(1.9, 0.05, 1.2)), panel_mat, Vector3(0, 1.58, 0.65), Vector3(-8, 0, 0))
	_add_mesh(rover, _cyl(0.04, 0.04, 1.0, 8), dark, Vector3(0.55, 1.95, -0.3))
	_add_mesh(rover, _box(Vector3(0.3, 0.18, 0.22)), dark, Vector3(0.55, 2.5, -0.3))
	_add_mesh(rover, _box(Vector3(0.1, 0.1, 0.05)), lamp, Vector3(0.55, 2.5, -0.42))
	_add_mesh(rover, _sph(0.35, 16, 6, true), body, Vector3(-0.6, 1.5, -0.1), Vector3(150, 0, 0))
	_add_mesh(rover, _box(Vector3(2.0, 0.25, 0.2)), dark, Vector3(0, 0.45, -1.95))
	_add_mesh(rover, _box(Vector3(0.3, 0.14, 0.05)), lamp, Vector3(0.7, 0.62, -1.92))
	_add_mesh(rover, _box(Vector3(0.3, 0.14, 0.05)), lamp, Vector3(-0.7, 0.62, -1.92))
	for side in [-1.0, 1.0]:
		var sf: float = side
		var lab := Label3D.new()
		lab.text = "ARES"
		lab.font_size = 96
		lab.pixel_size = 0.0045
		lab.modulate = Color(0.12, 0.12, 0.15)
		lab.outline_size = 0
		lab.position = Vector3(0.81 * sf, 1.1, 0.3)
		lab.rotation_degrees = Vector3(0, 90.0 * sf, 0)
		rover.add_child(lab)
	for wz in [-1.4, 0.0, 1.4]:
		for wx in [-1.2, 1.2]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx, 0.0, wz)
			rover.add_child(pivot)
			_add_mesh(pivot, _cyl(0.5, 0.5, 0.5, 20), tire, Vector3.ZERO, Vector3(0, 0, 90))
			_add_mesh(pivot, _cyl(0.25, 0.25, 0.52, 12), rover_paint_mat, Vector3.ZERO, Vector3(0, 0, 90))
			_add_mesh(pivot, _box(Vector3(0.54, 0.06, 0.9)), dark, Vector3.ZERO)
			rover_wheels.append(pivot)
	var head := SpotLight3D.new()
	head.position = Vector3(0, 0.9, -2.0)
	head.rotation_degrees = Vector3(-6, 0, 0)
	head.spot_range = 30.0
	head.spot_angle = 32.0
	head.light_energy = 3.0
	head.light_color = Color(1.0, 0.95, 0.85)
	rover.add_child(head)
	rover_dust = _make_particles(50, 1.6, Color(0.8, 0.55, 0.36, 0.45), 1.0, 2.6)
	rover_dust.direction = Vector3(0, 0.5, 1)
	rover_dust.spread = 30.0
	rover_dust.initial_velocity_min = 1.5
	rover_dust.initial_velocity_max = 3.5
	rover_dust.gravity = Vector3(0, -0.4, 0)
	rover_dust.position = Vector3(0, 0.1, 1.9)
	rover.add_child(rover_dust)


func _build_objective_marker() -> void:
	objective_marker = Node3D.new()
	surface_root.add_child(objective_marker)
	objective_label = Label3D.new()
	objective_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	objective_label.no_depth_test = true
	objective_label.fixed_size = true
	objective_label.pixel_size = 0.0018
	objective_label.font_size = 56
	objective_label.outline_size = 14
	objective_label.modulate = Color(1.0, 0.82, 0.3)
	objective_label.render_priority = 10
	objective_marker.add_child(objective_label)
	objective_marker.visible = false


# ═══════════════════════════════════════════════════════════════════════════
#  COLLISION (flat world: circles + axis-aligned boxes)
# ═══════════════════════════════════════════════════════════════════════════
func _add_circle(x: float, z: float, r: float) -> void:
	circles.append(Vector3(x, z, r))


func _add_rect_world(cx: float, cz: float, sx: float, sz: float) -> void:
	rects.append(Rect2(cx - sx * 0.5, cz - sz * 0.5, sx, sz))


func _add_rect_local(cx: float, cz: float, sx: float, sz: float) -> void:
	_add_rect_world(HAB_POS.x + cx, HAB_POS.z + cz, sx, sz)


func _dist_to_base(p: Vector3) -> float:
	var cx := clampf(p.x, base_rect.position.x, base_rect.end.x)
	var cz := clampf(p.z, base_rect.position.y, base_rect.end.y)
	return Vector2(p.x - cx, p.z - cz).length()


func _clear_of_structures(pos: Vector3, margin: float) -> bool:
	if _dist_to_base(pos) < margin:
		return false
	if Vector2(pos.x - PAD_POS.x, pos.z - PAD_POS.z).length() < 9.0 + margin:
		return false
	if Vector2(pos.x - ROVER_START.x, pos.z - ROVER_START.z).length() < 4.0 + margin:
		return false
	for o in circles:
		if Vector2(pos.x - o.x, pos.z - o.y).length() < o.z + margin:
			return false
	return true


func _resolve_obstacles(p: Vector3, extra: float) -> Vector3:
	for pass_i in 2:
		for o in circles:
			var d := Vector2(p.x - o.x, p.z - o.y)
			var min_d := o.z + extra
			var dist := d.length()
			if dist < min_d:
				var dir := Vector2(0.0, 1.0) if dist < 0.001 else d / dist
				p.x = o.x + dir.x * min_d
				p.z = o.y + dir.y * min_d
		for rc in rects:
			var cx := clampf(p.x, rc.position.x, rc.end.x)
			var cz := clampf(p.z, rc.position.y, rc.end.y)
			var dx := p.x - cx
			var dz := p.z - cz
			var d2 := dx * dx + dz * dz
			if d2 > extra * extra:
				continue
			if d2 > 0.000001:
				var dd := sqrt(d2)
				p.x = cx + dx / dd * extra
				p.z = cz + dz / dd * extra
			else:
				var l := p.x - rc.position.x
				var r := rc.end.x - p.x
				var t := p.z - rc.position.y
				var b := rc.end.y - p.z
				var m := minf(minf(l, r), minf(t, b))
				if m == l:
					p.x = rc.position.x - extra
				elif m == r:
					p.x = rc.end.x + extra
				elif m == t:
					p.z = rc.position.y - extra
				else:
					p.z = rc.end.y + extra
	return p


func _clamp_world(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > WORLD_LIMIT:
		flat = flat.normalized() * WORLD_LIMIT
		p.x = flat.x
		p.z = flat.y
	return p


# ═══════════════════════════════════════════════════════════════════════════
#  INTERACTABLES, DEPOSITS, DROPS, GEMS
# ═══════════════════════════════════════════════════════════════════════════
func _add_interact(act: String, pos: Vector3, label: String, r := 2.2, extra := {}) -> Dictionary:
	var d := {"act": act, "pos": pos, "label": label, "r": r, "hold": false, "cd": 0.0}
	d.merge(extra, true)
	interactables.append(d)
	return d


func _remove_interact(it: Dictionary) -> void:
	for i in interactables.size():
		if is_same(interactables[i], it):
			interactables.remove_at(i)
			break
	if is_same(focus, it):
		focus = {}


func _clear_dynamic() -> void:
	var i := interactables.size() - 1
	while i >= 0:
		var it: Dictionary = interactables[i]
		if bool(it.get("dynamic", false)):
			var n: Variant = it.get("node")
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
			interactables.remove_at(i)
		i -= 1
	focus = {}
	for c in collectibles:
		var gn: Node = c["node"]
		if is_instance_valid(gn):
			gn.queue_free()
	collectibles.clear()


func _spawn_deposit(pos: Vector3, kind := "") -> Dictionary:
	if kind == "":
		var r := rng.randf()
		kind = "iron" if r < 0.5 else ("silica" if r < 0.75 else ("ice" if r < 0.93 else "titanium"))
	var info: Dictionary = ITEMS[kind]
	var col: Color = info["col"]
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	surface_root.add_child(root)
	var anim := Node3D.new()
	root.add_child(anim)
	var rock := _mat(Color(0.28, 0.18, 0.14), 0.0, 0.95)
	for i in 3:
		var rm := _add_mesh(anim, _sph(0.7, 8, 5), rock, Vector3(rng.randf_range(-0.5, 0.5), 0.2, rng.randf_range(-0.5, 0.5)))
		rm.scale = Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.5, 0.8), rng.randf_range(0.9, 1.4))
	var cmat := _mat(col, 0.3, 0.25, col, 1.6)
	for i in 5:
		_add_mesh(anim, _cyl(0.0, rng.randf_range(0.12, 0.22), rng.randf_range(0.6, 1.2), 5), cmat,
			Vector3(rng.randf_range(-0.6, 0.6), 0.55, rng.randf_range(-0.6, 0.6)),
			Vector3(rng.randf_range(-25, 25), rng.randf_range(0, 360), rng.randf_range(-25, 25)))
	if q_tier == "HIGH":
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 0.8
		l.omni_range = 4.0
		l.position = Vector3(0, 1.0, 0)
		root.add_child(l)
	return _add_interact("deposit", root.position, "Mine " + str(info["name"]), 2.8,
		{"hold": true, "kind": kind, "hp": 3, "node": root, "anim": anim, "dynamic": true})


func _deposit_count() -> int:
	var n := 0
	for it in interactables:
		if str(it["act"]) == "deposit":
			n += 1
	return n


func _random_open_pos(rmin: float, rmax: float, margin: float, r: RandomNumberGenerator) -> Vector3:
	for attempt in 60:
		var ang := r.randf() * TAU
		var rad := r.randf_range(rmin, rmax)
		var pos := Vector3(cos(ang) * rad, 0.0, -5.0 + sin(ang) * rad)
		if _clear_of_structures(pos, margin):
			return pos
	return Vector3(40, 0, 40)


func _spawn_initial_deposits() -> void:
	_spawn_deposit(Vector3(-7.0, 0.0, 9.0), "iron")
	var r := RandomNumberGenerator.new()
	r.seed = 777 + expedition
	for i in MAX_DEPOSITS - 6:
		_spawn_deposit(_random_open_pos(18.0, 150.0, 4.0, r))


func _spawn_gems() -> void:
	for c in collectibles:
		var gn: Node = c["node"]
		if is_instance_valid(gn):
			gn.queue_free()
	collectibles.clear()
	var r := RandomNumberGenerator.new()
	r.seed = 20261115 + expedition * 131
	var gem_mat := _mat(Color(0.3, 1.0, 0.5), 0.2, 0.1, Color(0.2, 1.0, 0.45), 3.0)
	var beam_mat := _additive(Color(0.3, 1.0, 0.5, 0.28))
	for i in gem_target + 2:
		var pos := _random_open_pos(25.0, 120.0 + 10.0 * float(expedition), 5.0, r)
		var root := Node3D.new()
		root.position = pos
		surface_root.add_child(root)
		var anim := Node3D.new()
		anim.position.y = 1.1
		root.add_child(anim)
		_add_mesh(anim, _sph(0.32, 6, 4), gem_mat).scale = Vector3(0.8, 1.3, 0.8)
		_add_mesh(root, _cyl(0.05, 0.05, 16.0, 8), beam_mat, Vector3(0, 8.0, 0))
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.3, 1.0, 0.5)
		gl.light_energy = 1.4
		gl.omni_range = 6.0
		gl.position = Vector3(0, 1.0, 0)
		root.add_child(gl)
		collectibles.append({"node": root, "anim": anim, "phase": r.randf() * TAU})


func _spawn_crate(pos: Vector3, rarity: int, falling: bool, fixed := {}, label := "") -> Dictionary:
	var rc: Color = RARITY_COLORS[rarity]
	var root := Node3D.new()
	root.position = Vector3(pos.x, 60.0 if falling else 0.0, pos.z)
	surface_root.add_child(root)
	_add_mesh(root, _box(Vector3(1.2, 0.9, 1.2)), _mat(Color(0.85, 0.85, 0.82), 0.3, 0.5), Vector3(0, 0.45, 0))
	_add_mesh(root, _box(Vector3(1.24, 0.14, 1.24)), _mat(rc, 0.2, 0.4, rc, 2.0), Vector3(0, 0.55, 0))
	for sx in [-0.55, 0.55]:
		var sxf: float = sx
		_add_mesh(root, _box(Vector3(0.1, 0.92, 1.22)), hm_trim, Vector3(sxf, 0.45, 0))
	_add_mesh(root, _cyl(0.06, 0.06, 18.0, 8), _additive(Color(rc.r, rc.g, rc.b, 0.3)), Vector3(0, 9.0, 0))
	var chute_node: Node3D = null
	if falling:
		chute_node = Node3D.new()
		chute_node.position = Vector3(0, 4.5, 0)
		root.add_child(chute_node)
		var cm := _mat(rc.lerp(Color.WHITE, 0.3), 0.0, 0.7)
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_add_mesh(chute_node, _sph(2.2, 16, 6, true), cm)
		for i in 4:
			var a := TAU * float(i) / 4.0
			_line_mesh(chute_node, Vector3(cos(a) * 2.1, 0, sin(a) * 2.1), Vector3(0, -3.6, 0), 0.025, hm_hull)
	var l := OmniLight3D.new()
	l.light_color = rc
	l.light_energy = 1.5
	l.omni_range = 7.0
	l.position = Vector3(0, 1.2, 0)
	root.add_child(l)
	var lbl := label if label != "" else "Open %s supply drop" % RARITY_NAMES[rarity]
	return _add_interact("crate", Vector3(pos.x, 0, pos.z), lbl, 2.4,
		{"node": root, "rarity": rarity, "falling": falling, "chute": chute_node, "fixed": fixed, "dynamic": true})


func _roll_rarity() -> int:
	var bonus := 0.01 * float(mini(streak, 10))
	var r := rng.randf()
	if r < 0.03 + bonus * 0.5:
		return 3
	if r < 0.15 + bonus:
		return 2
	if r < 0.45 + bonus:
		return 1
	return 0


func _loot_for(rar: int) -> Dictionary:
	match rar:
		0:
			return {"ration": 2, "iron": 2}
		1:
			return {"power_cell": 1, "silica": 3, "greens": 2}
		2:
			return {"titanium": 2, "energy_bar": 3, "xp": 150}
	return {"titanium": 3, "power_cell": 2, "ice": 4, "xp": 400}


# ═══════════════════════════════════════════════════════════════════════════
#  INVENTORY & CRAFTING
# ═══════════════════════════════════════════════════════════════════════════
func _inv_count(id: String) -> int:
	return int(inventory.get(id, 0))


func _inv_add(id: String, n: int) -> bool:
	if not inventory.has(id) and inventory.size() >= INV_SLOTS:
		_toast("Inventory full! Use or craft items to free a slot.", 3.0, Color(1, 0.5, 0.4))
		return false
	inventory[id] = mini(_inv_count(id) + n, STACK_MAX)
	return true


func _inv_remove(id: String, n: int) -> bool:
	if _inv_count(id) < n:
		return false
	var left := _inv_count(id) - n
	if left <= 0:
		inventory.erase(id)
	else:
		inventory[id] = left
	return true


func _use_item(id: String) -> void:
	if state != SimState.SURFACE or sleeping or intro_phase != Intro.NONE:
		return
	var info: Dictionary = ITEMS.get(id, {})
	if info.is_empty():
		return
	var cat: String = info["cat"]
	if _inv_count(id) <= 0:
		_toast("No %s in your inventory" % info["name"])
		return
	if cat == "food":
		if food >= 99.0:
			_toast("You're not hungry right now")
			return
		_inv_remove(id, 1)
		food = minf(100.0, food + float(info.get("food", 0.0)))
		rest = minf(100.0, rest + float(info.get("rest", 0.0)))
		tut_flags["ate"] = true
		_toast("Ate %s  +%d Food" % [info["name"], int(info.get("food", 0.0))], 2.6, Color(0.6, 1.0, 0.5))
	elif cat == "tool":
		if power >= 99.0:
			_toast("Power is already full")
			return
		_inv_remove(id, 1)
		power = minf(100.0, power + float(info.get("power", 0.0)))
		_toast("Power Cell installed  +35 Power", 2.6, Color(1.0, 0.9, 0.4))
	else:
		_toast("%s — %s" % [info["name"], info["desc"]], 3.5)
		return
	if ui_modal == "inventory":
		_open_modal("inventory", false)


func _eat_best() -> void:
	for id in ["ration", "greens", "energy_bar"]:
		if _inv_count(id) > 0:
			_use_item(id)
			return
	_toast("No food! Try the galley dispenser, the greenhouse or a supply drop.", 3.5, Color(1, 0.6, 0.4))


func _can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if _inv_count(str(k)) < int(cost[k]):
			return false
	return true


func _craft(r: Dictionary) -> void:
	var cost: Dictionary = r["cost"]
	var id: String = r["id"]
	if id == "drill" and drill_level >= 3:
		_toast("Drill already at max level")
		return
	if not _can_afford(cost):
		_toast("Not enough materials")
		return
	for k in cost.keys():
		_inv_remove(str(k), int(cost[k]))
	var out: Dictionary = r["out"]
	for k in out.keys():
		_inv_add(str(k), int(out[k]))
	if id == "drill":
		drill_level += 1
		_toast("DRILL UPGRADED to level %d — faster mining, bonus yields!" % drill_level, 3.5, Color(0.8, 0.6, 1.0))
	else:
		_toast("Crafted %s" % r["name"], 2.6, Color(1.0, 0.8, 0.4))
	total_crafted += 1
	tut_flags["crafted"] = true
	_daily_progress("craft")
	_award_xp(15)
	_check_achievements()
	_open_modal("craft", false)


# ═══════════════════════════════════════════════════════════════════════════
#  PROGRESSION: XP, COMBO, STREAKS, DAILIES, ACHIEVEMENTS, SAVE
# ═══════════════════════════════════════════════════════════════════════════
func _xp_needed(lv: int) -> int:
	return 100 + (lv - 1) * 60


func _award_xp(base: int, combo_action := true) -> void:
	var mult := float(_br()["xp"])
	if combo_action:
		combo = combo + 1 if combo_timer > 0.0 else 1
		combo_timer = COMBO_WINDOW
		mult *= 1.0 + 0.25 * float(mini(combo, 9) - 1)
		if combo >= 9:
			_unlock("combo")
	xp += int(round(float(base) * mult))
	while xp >= _xp_needed(level):
		xp -= _xp_needed(level)
		level += 1
		_on_level_up()


func _on_level_up() -> void:
	var unlocked := PackedStringArray()
	for e in PALETTE + VISORS:
		var ed: Dictionary = e
		if int(ed["lvl"]) == level and int(ed["streak"]) == 0:
			unlocked.append(str(ed["name"]))
	var msg := "★ LEVEL UP — LEVEL %d ★" % level
	if unlocked.size() > 0:
		msg += "   Unlocked: " + ", ".join(unlocked)
	_toast(msg, 4.5, Color(1.0, 0.85, 0.3))
	_flash(Color(1.0, 0.8, 0.3), 0.35)
	shake = maxf(shake, 0.3)
	if state == SimState.SURFACE:
		_inv_add("power_cell", 1)
	_save()


func _unlock(id: String) -> void:
	if id in achievements or not ACHIEVEMENTS.has(id):
		return
	achievements.append(id)
	var a: Array = ACHIEVEMENTS[id]
	_toast("ACHIEVEMENT UNLOCKED — %s" % a[0], 4.0, Color(1.0, 0.75, 0.3))
	_award_xp(75, false)
	_save()


func _check_achievements() -> void:
	if total_mined >= 25:
		_unlock("miner25")
	if total_mined >= 100:
		_unlock("miner100")
	if total_gems >= 10:
		_unlock("gems10")
	if total_drive >= 1000.0:
		_unlock("drive1k")
	if total_harvest >= 10:
		_unlock("harvest10")
	if total_crafted >= 10:
		_unlock("crafter")
	if expeditions_done >= 3:
		_unlock("exped3")


func _check_streak_unlocks() -> void:
	if streak >= 3:
		_unlock("streak3")
	if streak >= 7:
		_unlock("streak7")


func _is_unlocked(e: Dictionary) -> bool:
	return level >= int(e["lvl"]) and best_streak >= int(e["streak"])


func _today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func _compute_streak() -> int:
	if DEMO_STREAK > 0:
		return DEMO_STREAK
	var today := _today()
	if streak_last_day == today:
		streak = maxi(streak, 1)
	elif streak_last_day == today - 1:
		streak += 1
	else:
		streak = 1
	streak_last_day = today
	_save()
	return streak


func _ensure_daily() -> void:
	var today := _today()
	if daily_day == today and daily.size() == 3:
		return
	daily_day = today
	daily = []
	var r := RandomNumberGenerator.new()
	r.seed = today * 7919
	var idx: Array = range(DAILY_POOL.size())
	for i in range(idx.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	for i in 3:
		var def: Dictionary = DAILY_POOL[int(idx[i])]
		var g := maxi(1, int(ceil(float(def["goal"]) * float(_br()["goal_mult"]))))
		daily.append({"type": def["type"], "goal": g, "text": str(def["text"]) % g, "prog": 0.0, "done": false})


func _daily_progress(kind: String, amount := 1.0) -> void:
	for d in daily:
		var dd: Dictionary = d
		if str(dd["type"]) != kind or bool(dd["done"]):
			continue
		dd["prog"] = float(dd["prog"]) + amount
		if float(dd["prog"]) >= float(dd["goal"]):
			dd["done"] = true
			_toast("DAILY MISSION COMPLETE — %s  (+120 XP, +1 Power Cell)" % dd["text"], 4.0, Color(0.5, 1.0, 0.6))
			_award_xp(120, false)
			_inv_add("power_cell", 1)
			_save()


func _give_daily_reward() -> void:
	var today := _today()
	if claimed_day == today:
		return
	claimed_day = today
	var rations := mini(1 + streak / 2, 5)
	_inv_add("ration", rations)
	_inv_add("ice", 2)
	if streak >= 5:
		_inv_add("titanium", 1)
	_award_xp(20 * mini(streak, 10), false)
	_toast("DAILY SUPPLY — Day %d streak: +%d Rations, +2 Ice%s" % [streak, rations, ", +1 Titanium" if streak >= 5 else ""], 5.0, Color(1.0, 0.75, 0.35))
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	var vals := {
		"level": level, "xp": xp, "drill": drill_level, "total_gems": total_gems, "total_mined": total_mined,
		"total_harvest": total_harvest, "total_crafted": total_crafted, "total_drive": total_drive,
		"expeditions": expeditions_done, "streak": streak, "best_streak": best_streak,
		"streak_last_day": streak_last_day, "claimed_day": claimed_day, "achievements": achievements,
		"tutorial_done": tutorial_done, "suit": suit_idx, "visor": visor_idx, "accent": accent_idx,
		"rover": rover_idx, "callsign": callsign, "daily_day": daily_day, "daily": daily, "age": cadet_age,
	}
	for k in vals.keys():
		cfg.set_value("p", str(k), vals[k])
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	level = int(cfg.get_value("p", "level", 1))
	xp = int(cfg.get_value("p", "xp", 0))
	drill_level = int(cfg.get_value("p", "drill", 1))
	total_gems = int(cfg.get_value("p", "total_gems", 0))
	total_mined = int(cfg.get_value("p", "total_mined", 0))
	total_harvest = int(cfg.get_value("p", "total_harvest", 0))
	total_crafted = int(cfg.get_value("p", "total_crafted", 0))
	total_drive = float(cfg.get_value("p", "total_drive", 0.0))
	expeditions_done = int(cfg.get_value("p", "expeditions", 0))
	streak = int(cfg.get_value("p", "streak", 1))
	best_streak = int(cfg.get_value("p", "best_streak", 1))
	streak_last_day = int(cfg.get_value("p", "streak_last_day", 0))
	claimed_day = int(cfg.get_value("p", "claimed_day", 0))
	tutorial_done = bool(cfg.get_value("p", "tutorial_done", false))
	suit_idx = int(cfg.get_value("p", "suit", 0))
	visor_idx = int(cfg.get_value("p", "visor", 0))
	accent_idx = int(cfg.get_value("p", "accent", 1))
	rover_idx = int(cfg.get_value("p", "rover", 1))
	callsign = str(cfg.get_value("p", "callsign", "CADET"))
	daily_day = int(cfg.get_value("p", "daily_day", 0))
	cadet_age = int(cfg.get_value("p", "age", 16))
	var a: Variant = cfg.get_value("p", "achievements", [])
	if a is Array:
		achievements = (a as Array).duplicate()
	var dl: Variant = cfg.get_value("p", "daily", [])
	if dl is Array:
		daily = (dl as Array).duplicate(true)
	play_tutorial = not tutorial_done


# ═══════════════════════════════════════════════════════════════════════════
#  STATE SWITCHING
# ═══════════════════════════════════════════════════════════════════════════
func _enter_state(s: int) -> void:
	state = s
	var in_menu := s == SimState.MENU_ORBIT
	menu_root.visible = in_menu
	surface_root.visible = not in_menu
	menu_layer.visible = in_menu
	hud_layer.visible = not in_menu and intro_phase == Intro.NONE
	intro_layer.visible = not in_menu and intro_phase != Intro.NONE
	if in_menu:
		_close_modal()
		menu_camera.current = true
		_refresh_menu_profile()
		launch_btn.grab_focus()
	else:
		get_viewport().gui_release_focus()
		surface_camera.current = true
	dragging = false


func _transition_to(s: int) -> void:
	if transitioning:
		return
	transitioning = true
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.45)
	await tw.finished
	if s == SimState.SURFACE:
		_reset_mission()
	_enter_state(s)
	var tw2 := create_tween()
	tw2.tween_property(fade_rect, "color:a", 0.0, 0.8)
	await tw2.finished
	transitioning = false


func _on_launch_pressed() -> void:
	_save()
	_transition_to(SimState.SURFACE)


func _return_to_menu() -> void:
	tut_active = false
	tut_panel.visible = false
	intro_phase = Intro.NONE
	_close_modal()
	_save()
	_transition_to(SimState.MENU_ORBIT)


func _reset_mission() -> void:
	bracket = _bracket_for(cadet_age)
	expedition = 1
	difficulty = _difficulty_for()
	ease = 1.0
	exhaust_events = 0
	was_exhausted = false
	power = 100.0
	food = 85.0
	rest = 90.0
	gems = 0
	gem_target = int(_br()["gems"])
	mission_time = 0.0
	mission_complete = false
	hazard = Hazard.NONE
	hazard_timer = 70.0
	sleeping = false
	power_warned = false
	inventory = {"ration": 1}
	combo = 0
	combo_timer = 0.0
	drop_timer = 75.0
	deposit_timer = 25.0
	fact_timer = 35.0
	play_time = 0.0
	break_at = 0.0
	rover_speed = 0.0
	rover_heading = 0.5
	rover.position = ROVER_START
	rover.rotation.y = rover_heading
	driving = false
	inside_base = false
	player_pos = SPAWN_POS
	player_heading = 0.0
	cam_yaw = 0.0
	cam_pitch = 0.38
	cam_dist = 8.0
	cam_eff_dist = 8.0
	cam_target = player_pos
	sleep_overlay.visible = false
	tut_active = false
	tut_panel.visible = false
	_clear_dynamic()
	_spawn_gems()
	_spawn_initial_deposits()
	tut_crate_pos = Vector3(5.0, 0.0, 12.0)
	_spawn_crate(tut_crate_pos, 0, false, {"ration": 2, "iron": 2, "silica": 1, "greens": 1}, "Open welcome supply crate")
	_close_modal()
	_update_hud()
	_start_intro()


func _next_expedition() -> void:
	expedition += 1
	difficulty = _difficulty_for()
	gem_target = mini(gem_target + 1, 14)
	gems = 0
	mission_complete = false
	mission_time = 0.0
	food = minf(100.0, food + 30.0)
	rest = minf(100.0, rest + 30.0)
	power = minf(100.0, power + 30.0)
	_spawn_gems()
	_close_modal()
	_toast("EXPEDITION %d — %d new gems detected. Difficulty ×%.2f" % [expedition, gem_target, difficulty], 5.0, Color(0.5, 1.0, 0.6))


func _mission_complete() -> void:
	mission_complete = true
	expeditions_done += 1
	_award_xp(300, false)
	_inv_add("titanium", 2)
	_check_achievements()
	_save()
	_flash(Color(0.4, 1.0, 0.5), 0.4)
	_toast("★ ALL ISOTOPE GEMS RECOVERED — EXPEDITION COMPLETE ★", 5.0, Color(0.5, 1.0, 0.6))
	get_tree().create_timer(1.6).timeout.connect(func():
		if state == SimState.SURFACE and mission_complete and ui_modal == "":
			_open_modal("summary"))


# ═══════════════════════════════════════════════════════════════════════════
#  CAPSULE INTRO
# ═══════════════════════════════════════════════════════════════════════════
func _start_intro() -> void:
	intro_phase = Intro.ENTRY
	cap_y = CAPSULE_START_Y
	cap_vel = 75.0
	capsule.position = Vector3(PAD_POS.x, cap_y, PAD_POS.z)
	capsule_glow.visible = true
	capsule_trail.emitting = q_particles
	capsule_flame.emitting = false
	capsule_light.visible = false
	hatch_hinge.rotation.y = 0.0
	chute.visible = false
	chute_attached = true
	chute_age = 0.0
	chute.rotation = Vector3.ZERO
	intro_orbit = 0.6
	intro_dist = 26.0
	astro.visible = false
	intro_msg.modulate.a = 0.0
	letter_top.offset_bottom = 90.0
	letter_bot.offset_top = -90.0
	_intro_message("ARES-7  •  ATMOSPHERIC ENTRY")


func _intro_message(t: String) -> void:
	intro_msg.text = t
	intro_msg.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(intro_msg, "modulate:a", 0.0, 1.2).set_delay(1.6)


func _process_intro(delta: float) -> void:
	match intro_phase:
		Intro.ENTRY:
			cap_vel = lerpf(cap_vel, 55.0, delta * 0.5)
			cap_y -= cap_vel * delta
			shake = maxf(shake, 0.15)
			(capsule_glow.material_override as StandardMaterial3D).albedo_color.a = 0.4 + 0.25 * sin(time_accum * 30.0)
			if cap_y <= 150.0:
				intro_phase = Intro.CHUTE
				capsule_glow.visible = false
				capsule_trail.emitting = false
				chute.visible = true
				chute.scale = Vector3(0.1, 0.1, 0.1)
				create_tween().tween_property(chute, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				shake = 0.7
				_intro_message("PARACHUTE DEPLOYED")
		Intro.CHUTE:
			cap_vel = lerpf(cap_vel, 10.0, delta * 1.8)
			cap_y -= cap_vel * delta
			if cap_y <= 24.0:
				intro_phase = Intro.RETRO
				chute_attached = false
				chute_drift = Vector3(rng.randf_range(-4.0, 4.0), 3.0, rng.randf_range(-4.0, 4.0))
				capsule_flame.emitting = true
				capsule_light.visible = true
				_intro_message("RETRO-ROCKETS FIRING")
		Intro.RETRO:
			cap_vel = lerpf(cap_vel, 2.2, delta * 2.2)
			cap_y -= cap_vel * delta
			shake = maxf(shake, 0.25)
			capsule_light.light_energy = 6.0 + rng.randf() * 3.0
			if cap_y <= 0.0:
				cap_y = 0.0
				intro_phase = Intro.LANDED
				intro_timer = 1.6
				capsule_flame.emitting = false
				capsule_light.visible = false
				landing_dust.restart()
				landing_dust.emitting = true
				shake = 1.0
				_intro_message("TOUCHDOWN — WELCOME TO GALE CRATER")
		Intro.LANDED:
			intro_timer -= delta
			if intro_timer <= 0.0:
				create_tween().tween_property(hatch_hinge, "rotation:y", -1.9, 0.9).set_trans(Tween.TRANS_BACK)
				intro_phase = Intro.EGRESS
				intro_timer = 2.4
				player_pos = Vector3(PAD_POS.x, PLAYER_Y, PAD_POS.z - 1.6)
				player_heading = 0.0
				astro.visible = true
		Intro.EGRESS:
			intro_timer -= delta
			is_moving = false
			if intro_timer < 1.6:
				player_pos = player_pos.move_toward(SPAWN_POS, WALK_SPEED * 0.7 * delta)
				is_moving = player_pos.distance_to(SPAWN_POS) > 0.05
				walk_phase += delta * 6.0
			astro.position = player_pos
			_animate_astronaut(delta)
			if intro_timer <= 0.0:
				_finish_intro()
				return
	capsule.position = Vector3(PAD_POS.x, cap_y, PAD_POS.z)
	if chute.visible:
		if chute_attached:
			chute.position = capsule.position + Vector3(0, 14.0, 0)
			chute.rotation.z = sin(time_accum * 1.3) * 0.06
		else:
			chute_age += delta
			chute.position += chute_drift * delta
			chute.rotation.z += delta * 0.3
			if chute_age > 5.0:
				chute.visible = false
	intro_label.text = "ALT %6.1f m    VEL %5.1f m/s    TARGET: GALE OUTPOST PAD" % [cap_y, cap_vel]


func _update_camera_intro(delta: float) -> void:
	intro_orbit += delta * 0.22
	var tgt := capsule.position + Vector3(0, 2.0, 0)
	var want := 13.0
	var pitch := 0.25
	match intro_phase:
		Intro.ENTRY:
			want = 26.0
			pitch = -0.1
		Intro.CHUTE:
			want = 22.0
			pitch = -0.2
		Intro.EGRESS:
			tgt = player_pos + Vector3(0, 1.0, 0)
			want = 9.0
	intro_dist = lerpf(intro_dist, want, clampf(delta * 1.5, 0.0, 1.0))
	var off := Vector3(sin(intro_orbit) * cos(pitch), sin(pitch), cos(intro_orbit) * cos(pitch)) * intro_dist
	var pos := tgt + off
	pos.y = maxf(pos.y, 1.0)
	surface_camera.look_at_from_position(pos, tgt, Vector3.UP)


func _finish_intro() -> void:
	intro_phase = Intro.NONE
	cap_y = 0.0
	capsule.position = PAD_POS
	chute.visible = false
	capsule_glow.visible = false
	capsule_trail.emitting = false
	capsule_flame.emitting = false
	capsule_light.visible = false
	hatch_hinge.rotation.y = -1.9
	astro.visible = true
	player_pos = SPAWN_POS
	cam_target = player_pos
	cam_yaw = 0.0
	var tw := create_tween()
	tw.tween_property(letter_top, "offset_bottom", 0.0, 0.6)
	tw.parallel().tween_property(letter_bot, "offset_top", 0.0, 0.6)
	tw.tween_callback(func(): intro_layer.visible = false)
	hud_layer.visible = true
	_give_daily_reward()
	if play_tutorial:
		_start_tutorial()
	else:
		_toast("Welcome back, %s — find the green beacons ◆" % callsign, 4.0)


func _skip_intro() -> void:
	if intro_phase == Intro.NONE:
		return
	_finish_intro()


# ═══════════════════════════════════════════════════════════════════════════
#  TUTORIAL (branches by age bracket)
# ═══════════════════════════════════════════════════════════════════════════
func _start_tutorial() -> void:
	tut_steps = []
	for s in TUTORIAL:
		var sd: Dictionary = s
		var skip: Array = sd["skip"]
		if not skip.has(bracket):
			tut_steps.append(sd)
	tut_index = 0
	tut_cam_drag = 0.0
	tut_walk = 0.0
	tut_sprint = 0.0
	tut_drive = 0.0
	tut_flags = {}
	tut_active = true
	_refresh_tut_panel()
	_toast("TRAINING STARTED — follow the panel on the left", 3.5, Color(0.6, 0.85, 1.0))


func _tut_check(id: String) -> bool:
	match id:
		"look":
			return tut_cam_drag > 350.0
		"move":
			return tut_walk > 10.0
		"sprint":
			return tut_sprint > 1.5
		"base":
			return inside_base
		"rover":
			return tut_drive > 40.0
		"done":
			return false
	return bool(tut_flags.get(id, false))


func _update_tutorial(delta: float) -> void:
	if not tut_active or tut_index >= tut_steps.size():
		return
	var step: Dictionary = tut_steps[tut_index]
	var id: String = step["id"]
	if id == "done":
		tut_done_timer -= delta
		if tut_done_timer <= 0.0:
			_end_tutorial(true)
		return
	if _tut_check(id):
		tut_index += 1
		_award_xp(20, false)
		_fx_burst(player_pos + Vector3(0, 1.2, 0), Color(0.5, 0.85, 1.0))
		_toast("✓ %s complete  +XP" % step["title"], 2.4, Color(0.6, 0.9, 1.0))
		var nxt: Dictionary = tut_steps[tut_index]
		if str(nxt["id"]) == "done":
			tut_done_timer = 8.0
		_refresh_tut_panel()


func _end_tutorial(completed: bool) -> void:
	tut_active = false
	tut_panel.visible = false
	tutorial_done = true
	play_tutorial = false
	if completed:
		_unlock("tutorial")
		_award_xp(100, false)
	_save()


func _refresh_tut_panel() -> void:
	tut_panel.visible = tut_active
	if not tut_active:
		return
	var step: Dictionary = tut_steps[tut_index]
	var texts: Array = step["t"]
	tut_title.text = "TRAINING  %d / %d   •   %s" % [tut_index + 1, tut_steps.size(), step["title"]]
	tut_text.text = str(texts[bracket])
	tut_prog.max_value = tut_steps.size() - 1
	tut_prog.value = tut_index
	tut_panel.modulate = Color(1.6, 1.6, 1.6)
	create_tween().tween_property(tut_panel, "modulate", Color.WHITE, 0.6)


# ═══════════════════════════════════════════════════════════════════════════
#  SURFACE LOOP
# ═══════════════════════════════════════════════════════════════════════════
func _process_surface(delta: float) -> void:
	_animate_world(delta)
	if intro_phase != Intro.NONE:
		_process_intro(delta)
		if intro_phase != Intro.NONE:
			_update_camera_intro(delta)
		_apply_shake(delta)
		return
	if ui_modal in ["pause", "summary", "break"]:
		_update_camera(delta)
		return
	mission_time += delta
	play_time += delta
	autosave_timer -= delta
	if autosave_timer <= 0.0:
		autosave_timer = 30.0
		_save()
	_update_hazard(delta)
	_process_sleep(delta)
	_handle_movement(delta)
	inside_base = not driving and base_rect.has_point(Vector2(player_pos.x, player_pos.z))
	roof_root.visible = not inside_base
	_update_survival(delta)
	_update_collectibles(delta)
	_update_interactables(delta)
	_update_focus()
	_process_mining(delta)
	_update_spawners(delta)
	_update_combo(delta)
	_update_tutorial(delta)
	_update_objective()
	_update_facts(delta)
	_check_break()
	_update_camera(delta)
	_apply_shake(delta)
	_update_environment(delta)
	_animate_astronaut(delta)
	if not player_pos.is_finite():
		player_pos = SPAWN_POS
	player_pos.y = PLAYER_Y
	rover.position.y = PLAYER_Y
	astro.position = player_pos
	hud_timer -= delta
	if hud_timer <= 0.0:
		hud_timer = 0.08
		_update_hud()


func _animate_world(delta: float) -> void:
	holo_globe.rotate_y(delta * 0.5)
	hab_beacon_mat.emission_energy_multiplier = 4.0 if fmod(time_accum, 1.2) < 0.6 else 0.5
	pad_light_mat.emission_energy_multiplier = 1.0 + 3.0 * (0.5 + 0.5 * sin(time_accum * 4.0))
	for f in o2_fans:
		f.rotate_y(delta * 6.0)
	drone.position.y = 2.0 + sin(time_accum * 2.0) * 0.15
	drone.rotation.y += delta * 0.4


func _handle_movement(delta: float) -> void:
	is_moving = false
	var ix := 0.0
	var iz := 0.0
	if not sleeping and ui_modal == "":
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			iz -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			iz += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			ix -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			ix += 1.0
	var vitals := 1.0
	if food <= 0.0 or rest <= 0.0:
		vitals = 0.75 if bracket == 0 else 0.5
	if driving:
		_drive_rover(delta, -iz, -ix, vitals)
		return
	rover_speed = move_toward(rover_speed, 0.0, 12.0 * delta)
	var input := Vector3(ix, 0.0, iz)
	sprinting = false
	if input.length() > 0.01:
		input = input.normalized()
		var dir := Basis(Vector3.UP, cam_yaw) * input
		sprinting = Input.is_physical_key_pressed(KEY_SHIFT)
		var spd := (SPRINT_SPEED if sprinting else WALK_SPEED) * vitals
		if power <= 0.0:
			spd *= 0.6
		var before := player_pos
		player_pos += dir * spd * delta
		player_heading = lerp_angle(player_heading, atan2(-dir.x, -dir.z), clampf(delta * 12.0, 0.0, 1.0))
		walk_phase += delta * spd * 1.7
		is_moving = true
		player_pos = _resolve_obstacles(player_pos, 0.6)
		player_pos = _clamp_world(player_pos)
		tut_walk += Vector2(player_pos.x - before.x, player_pos.z - before.z).length()
		if sprinting:
			tut_sprint += delta
	player_pos.y = PLAYER_Y


func _drive_rover(delta: float, throttle: float, steer: float, vitals: float) -> void:
	var max_v := ROVER_MAX_SPEED * (0.8 if hazard == Hazard.DUST_STORM else 1.0) * (0.7 if vitals < 1.0 else 1.0)
	var target := throttle * (max_v if throttle > 0.0 else max_v * 0.5)
	if power <= 0.0:
		target = 0.0
		if not power_warned:
			power_warned = true
			_toast("Rover power depleted — use a Power Cell (Q) or recharge at base", 4.0, Color(1, 0.5, 0.4))
	var rate := ROVER_ACCEL if absf(target) > 0.01 else 7.0
	rover_speed = move_toward(rover_speed, target, rate * delta)
	var steer_scale := lerpf(0.5, 1.0, clampf(absf(rover_speed) / 8.0, 0.0, 1.0))
	var dir_sign := 1.0 if rover_speed >= -0.5 else -1.0
	rover_heading += steer * ROVER_TURN * steer_scale * dir_sign * delta
	var fwd := Vector3(-sin(rover_heading), 0.0, -cos(rover_heading))
	var before := rover.position
	var np := rover.position + fwd * rover_speed * delta
	np = _resolve_obstacles(np, 2.0)
	np = _clamp_world(np)
	np.y = PLAYER_Y
	var moved := before.distance_to(np)
	if moved < absf(rover_speed) * delta * 0.5 - 0.0001:
		rover_speed *= 0.6
	rover.position = np
	rover.rotation.y = rover_heading
	for w in rover_wheels:
		w.rotation.x = wrapf(w.rotation.x - rover_speed * delta / 0.5, -PI, PI)
	total_drive += moved
	tut_drive += moved
	if moved > 0.0:
		_daily_progress("drive", moved)
	player_pos = rover.position
	is_moving = absf(rover_speed) > 0.5
	if not dragging and absf(rover_speed) > 1.0:
		cam_yaw = lerp_angle(cam_yaw, rover_heading, clampf(delta * 0.9, 0.0, 1.0))


func _animate_astronaut(delta: float) -> void:
	astro.visible = not driving
	astro_model.rotation.y = player_heading
	var swing := sin(walk_phase) * 0.7 if is_moving else 0.0
	var k := clampf(delta * 12.0, 0.0, 1.0)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, swing, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -swing, k)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -swing, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, swing, k)
	astro_model.position.y = absf(sin(walk_phase)) * 0.05 if is_moving else 0.0
	helmet_light.visible = hazard == Hazard.DUST_STORM and not inside_base
	step_dust.emitting = q_particles and is_moving and not driving and not inside_base
	rover_dust.emitting = q_particles and driving and absf(rover_speed) > 3.0


func _update_camera(delta: float) -> void:
	var tgt := rover.position if driving else player_pos
	cam_target = cam_target.lerp(tgt, 1.0 - exp(-9.0 * delta))
	var dist := cam_dist
	var pitch := cam_pitch
	if inside_base:
		dist = minf(dist, 9.5)
		pitch = maxf(pitch, 0.85)
	var k := 1.0 - exp(-6.0 * delta)
	cam_eff_dist = lerpf(cam_eff_dist, dist, k)
	cam_eff_pitch = lerpf(cam_eff_pitch, pitch, k)
	var offset := Vector3(sin(cam_yaw) * cos(cam_eff_pitch), sin(cam_eff_pitch), cos(cam_yaw) * cos(cam_eff_pitch)) * cam_eff_dist
	var pos := cam_target + offset
	pos.y = maxf(pos.y, 0.7)
	surface_camera.look_at_from_position(pos, cam_target + Vector3(0, 1.0, 0), Vector3.UP)


func _apply_shake(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 1.6)
	var s := shake * shake * 0.35
	surface_camera.h_offset = rng.randf_range(-s, s)
	surface_camera.v_offset = rng.randf_range(-s, s)


func _update_survival(delta: float) -> void:
	var near := inside_base or _dist_to_base(player_pos) <= 3.0
	var d := difficulty * ease
	if not sleeping:
		var act := 1.0
		if is_moving:
			act = 1.4 if sprinting else 1.2
		food = maxf(0.0, food - FOOD_DRAIN * d * act * delta)
		rest = maxf(0.0, rest - REST_DRAIN * d * act * delta)
	var drain := POWER_DRAIN * d
	if driving:
		drain += ROVER_POWER * d * absf(rover_speed) / ROVER_MAX_SPEED
	var gain := 0.3 * (0.4 if hazard == Hazard.DUST_STORM else 1.0)
	if near:
		gain += 6.0
	power = clampf(power + (gain - drain) * delta, 0.0, 100.0)
	if power > 5.0:
		power_warned = false
	if hazard == Hazard.SOLAR_FLARE and not near and not sleeping:
		rest = maxf(0.0, rest - 2.0 * d * delta)
	# adaptive difficulty: help players who keep running dry
	var exhausted := food <= 0.0 or rest <= 0.0
	if exhausted and not was_exhausted:
		exhaust_events += 1
		if bracket <= 1 or exhaust_events >= 3:
			ease = maxf(0.6, ease - 0.1)
			_toast("Mission Control: suit systems tuned to drain %d%% slower. Eat (E) and rest in a bunk!" % int((1.0 - ease) * 100.0), 5.0, Color(0.6, 0.85, 1.0))
		else:
			_toast("EXHAUSTED — speed halved. Eat (E) and sleep in a bunk!", 4.0, Color(1, 0.5, 0.4))
	was_exhausted = exhausted


func _update_hazard(delta: float) -> void:
	hazard_timer -= delta
	if hazard_timer > 0.0:
		return
	var hm := float(_br()["hazard"])
	if hazard == Hazard.NONE:
		var flare_ok := bool(_br()["flare"])
		hazard = Hazard.SOLAR_FLARE if flare_ok and rng.randf() < 0.4 else Hazard.DUST_STORM
		hazard_timer = rng.randf_range(20.0, 32.0)
		if hazard == Hazard.DUST_STORM:
			_toast("▲ DUST STORM incoming — solar output reduced", 4.0, Color(1.0, 0.65, 0.25))
		else:
			_toast("▲ SOLAR FLARE — get inside the base!", 4.0, Color(1.0, 0.35, 0.25))
			_flash(Color(1.0, 0.6, 0.3), 0.25)
	else:
		hazard = Hazard.NONE
		hazard_timer = rng.randf_range(45.0, 80.0) / (difficulty * hm)
		_toast("Skies clear", 3.0)


func _update_environment(delta: float) -> void:
	var storm := hazard == Hazard.DUST_STORM
	var flare := hazard == Hazard.SOLAR_FLARE
	var k := clampf(delta * 0.9, 0.0, 1.0)
	surface_env.fog_density = lerpf(surface_env.fog_density, FOG_STORM if storm else FOG_BASE, k)
	surface_env.fog_light_color = surface_env.fog_light_color.lerp(COL_FOG_STORM if storm else COL_FOG_CLEAR, k)
	surface_sun.light_energy = lerpf(surface_sun.light_energy, 0.55 if storm else (1.9 if flare else 1.25), k)
	surface_sun.light_color = surface_sun.light_color.lerp(Color(1.0, 0.62, 0.42) if flare else Color(1.0, 0.88, 0.75), k)
	surface_env.ambient_light_energy = lerpf(surface_env.ambient_light_energy, 0.5 if storm else 0.75, k)
	if q_volumetric:
		surface_env.volumetric_fog_density = lerpf(surface_env.volumetric_fog_density, 0.03 if storm else 0.005, k)
	dust_particles.emitting = storm and q_particles


func _update_collectibles(delta: float) -> void:
	var reach := 3.4 if driving else 2.4
	var i := collectibles.size() - 1
	while i >= 0:
		var c: Dictionary = collectibles[i]
		var node: Node3D = c["node"]
		var anim: Node3D = c["anim"]
		var phase: float = c["phase"]
		anim.rotation.y += delta * 1.6
		anim.position.y = 1.1 + sin(time_accum * 2.0 + phase) * 0.18
		var d := Vector2(player_pos.x - node.position.x, player_pos.z - node.position.z).length()
		if d < reach and not mission_complete:
			gems += 1
			total_gems += 1
			_inv_add("gem", 1)
			power = minf(100.0, power + 12.0)
			tut_flags["gem"] = true
			_daily_progress("gems")
			_award_xp(50)
			_fx_burst(node.position + Vector3(0, 1, 0), Color(0.3, 1.0, 0.5))
			_toast("◆ Isotope Gem recovered  (%d / %d)  +12%% power" % [gems, gem_target], 2.8, Color(0.4, 1.0, 0.6))
			node.queue_free()
			collectibles.remove_at(i)
			_check_achievements()
			if gems >= gem_target:
				_mission_complete()
		i -= 1


func _update_interactables(delta: float) -> void:
	for it in interactables:
		var act: String = it["act"]
		if act == "plant":
			var g := minf(1.0, float(it["grow"]) + delta / 55.0)
			it["grow"] = g
			var pn: Node3D = it["plant_node"]
			var s := 0.25 + 0.75 * g
			pn.scale = Vector3(s, s, s)
			it["label"] = "Harvest Fresh Greens" if g >= 1.0 else "Growing…  %d%%" % int(g * 100.0)
		elif act == "crate" and bool(it["falling"]):
			var node: Node3D = it["node"]
			node.position.y = maxf(0.0, node.position.y - 7.0 * delta)
			node.rotation.y += delta * 0.5
			if node.position.y <= 0.0:
				it["falling"] = false
				var ch: Variant = it["chute"]
				if ch is Node3D:
					(ch as Node3D).visible = false
				_fx_burst(node.position + Vector3(0, 0.3, 0), Color(0.85, 0.6, 0.4))


func _update_focus() -> void:
	var best: Dictionary = {}
	var best_d := 1e9
	if not driving and not sleeping:
		for it in interactables:
			if bool(it.get("falling", false)):
				continue
			var ip: Vector3 = it["pos"]
			var d := Vector2(player_pos.x - ip.x, player_pos.z - ip.z).length()
			if d < float(it["r"]) and d < best_d:
				best_d = d
				best = it
		var rd := Vector2(player_pos.x - rover.position.x, player_pos.z - rover.position.z).length()
		if rd < 4.5 and rd < best_d:
			best = {"act": "rover", "label": "Board ARES rover", "hold": false}
	focus = best


func _process_mining(delta: float) -> void:
	var holding := Input.is_physical_key_pressed(KEY_F) and ui_modal == "" and not sleeping
	if not focus.is_empty() and bool(focus.get("hold", false)) and holding:
		if not is_same(focus, mine_target):
			mine_target = focus
			mine_progress = 0.0
		mine_progress += delta * (0.75 + 0.35 * float(drill_level)) * (1.0 if power > 0.0 else 0.5)
		var anim: Node3D = focus["anim"]
		anim.position = Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.04, 0.04))
		if rng.randf() < 0.15:
			_fx_burst(Vector3(anim.global_position.x, 0.8, anim.global_position.z), ITEMS[str(focus["kind"])]["col"])
		if mine_progress >= 1.0:
			mine_progress = 0.0
			_mine_yield(focus)
	else:
		mine_progress = maxf(0.0, mine_progress - delta * 2.0)


func _mine_yield(it: Dictionary) -> void:
	var kind: String = it["kind"]
	var n := 1 + (1 if rng.randf() < 0.25 * float(drill_level) else 0)
	if not _inv_add(kind, n):
		return
	var nm: String = ITEMS[kind]["name"]
	_toast("+%d %s%s" % [n, nm, "  (bonus!)" if n > 1 else ""], 2.0, ITEMS[kind]["col"])
	it["hp"] = int(it["hp"]) - 1
	total_mined += 1
	tut_flags["mine"] = true
	_daily_progress("mine")
	_award_xp(10 if kind != "titanium" else 30)
	shake = maxf(shake, 0.2)
	_check_achievements()
	var node: Node3D = it["node"]
	_fx_burst(node.position + Vector3(0, 0.8, 0), ITEMS[kind]["col"])
	if int(it["hp"]) <= 0:
		node.queue_free()
		_remove_interact(it)
		mine_target = {}
	else:
		var s := 0.55 + 0.15 * float(it["hp"])
		node.scale = Vector3(s, s, s)


func _update_spawners(delta: float) -> void:
	deposit_timer -= delta
	if deposit_timer <= 0.0:
		deposit_timer = 25.0
		if _deposit_count() < MAX_DEPOSITS:
			_spawn_deposit(_random_open_pos(30.0, 150.0, 4.0, rng))
	drop_timer -= delta
	if drop_timer <= 0.0:
		drop_timer = rng.randf_range(80.0, 140.0) / maxf(0.7, float(_br()["hazard"]) * 0.5 + 0.5)
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(25.0, 60.0)
		var pos := Vector3(player_pos.x + cos(ang) * dist, 0.0, player_pos.z + sin(ang) * dist)
		if _clear_of_structures(pos, 3.0):
			var rar := _roll_rarity()
			_spawn_crate(_clamp_world(pos), rar, true)
			_toast("SUPPLY DROP incoming — %s! Check your radar." % RARITY_NAMES[rar], 4.0, RARITY_COLORS[rar])


func _update_combo(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			if combo >= 3:
				_toast("Combo ended at ×%.2f" % (1.0 + 0.25 * float(mini(combo, 9) - 1)), 2.0)
			combo = 0


func _nearest_gem() -> Variant:
	var best: Variant = null
	var bd := 1e9
	for c in collectibles:
		var n: Node3D = c["node"]
		var d := n.position.distance_to(player_pos)
		if d < bd:
			bd = d
			best = n.position
	return best


func _update_objective() -> void:
	has_objective = false
	var target: Variant = null
	if tut_active and tut_index < tut_steps.size():
		var id: String = tut_steps[tut_index]["id"]
		match id:
			"crate":
				if not tut_flags.get("crate", false):
					target = tut_crate_pos
			"mine":
				var bd := 1e9
				for it in interactables:
					if str(it["act"]) == "deposit":
						var ip: Vector3 = it["pos"]
						var d := ip.distance_to(player_pos)
						if d < bd:
							bd = d
							target = ip
			"base":
				target = _w(0.0, 11.0)
			"craft":
				target = _w(17.0, -20.0)
			"locker":
				target = _w(-23.3, -3.7)
			"sleep":
				target = _w(-16.1, 4.5)
			"rover":
				target = rover.position
			"gem":
				target = _nearest_gem()
	elif bool(_br()["hints"]) and not mission_complete:
		target = _w(0.0, 11.0) if power < 20.0 and not inside_base else _nearest_gem()
	if target is Vector3:
		has_objective = true
		objective_pos = target
	objective_marker.visible = has_objective
	if has_objective:
		objective_marker.position = objective_pos + Vector3(0, 3.6 + sin(time_accum * 3.0) * 0.3, 0)
		objective_label.text = "▼\n%d m" % int(Vector2(objective_pos.x - player_pos.x, objective_pos.z - player_pos.z).length())


func _update_facts(delta: float) -> void:
	if fact_time > 0.0:
		fact_time -= delta
		fact_panel.modulate.a = clampf(fact_time / 0.6, 0.0, 1.0)
		if fact_time <= 0.0:
			fact_panel.visible = false
	fact_timer -= delta
	if fact_timer <= 0.0:
		fact_timer = rng.randf_range(80.0, 120.0)
		var f: Array = FACTS[fact_index % FACTS.size()]
		fact_index += 1
		fact_label.text = "DID YOU KNOW?\n" + str(f[0] if bracket <= 1 else f[1])
		fact_panel.visible = true
		fact_panel.modulate.a = 1.0
		fact_time = 10.0


func _check_break() -> void:
	var mins := int(_br()["break_min"])
	if mins <= 0 or ui_modal != "":
		return
	if play_time - break_at >= float(mins) * 60.0:
		break_at = play_time
		_open_modal("break")


# ═══════════════════════════════════════════════════════════════════════════
#  ACTIONS
# ═══════════════════════════════════════════════════════════════════════════
func _on_interact_pressed() -> void:
	if sleeping:
		return
	if driving:
		_toggle_rover()
		return
	if focus.is_empty():
		_toast("Nothing to interact with here")
		return
	var act: String = focus["act"]
	if act == "rover":
		_toggle_rover()
	elif not bool(focus.get("hold", false)):
		_do_interact(focus)


func _do_interact(it: Dictionary) -> void:
	var act: String = it["act"]
	var cd_until := float(it.get("cd", 0.0))
	if cd_until > time_accum:
		_toast("Recharging — ready in %ds" % ceili(cd_until - time_accum))
		return
	match act:
		"bunk":
			_start_sleep()
		"locker":
			tut_flags["locker"] = true
			_open_modal("custom")
		"fabricator", "drill_rack":
			_open_modal("craft")
		"terminal":
			_open_modal("terminal")
		"dispenser":
			if _inv_add("ration", 1):
				it["cd"] = time_accum + 45.0
				_toast("Dispenser: +1 Ration Pack", 2.4, Color(0.6, 1.0, 0.5))
				_award_xp(4)
		"fridge":
			var got := "greens" if rng.randf() < 0.6 else "energy_bar"
			if _inv_add(got, 1):
				it["cd"] = time_accum + 90.0
				_toast("Fridge: +1 %s" % ITEMS[got]["name"], 2.4, Color(0.6, 1.0, 0.5))
		"coffee":
			rest = minf(100.0, rest + 12.0)
			it["cd"] = time_accum + 40.0
			_toast("Hot coffee  +12 Rest", 2.4, Color(0.6, 0.8, 1.0))
		"plant":
			if float(it["grow"]) < 1.0:
				_toast("Still growing (%d%%)" % int(float(it["grow"]) * 100.0))
				return
			var n := 1 + (1 if rng.randf() < 0.4 else 0)
			if _inv_add("greens", n):
				it["grow"] = 0.0
				total_harvest += 1
				_daily_progress("harvest")
				_award_xp(8)
				_fx_burst(Vector3(player_pos.x, 1.0, player_pos.z), Color(0.4, 1.0, 0.4))
				_toast("Harvested +%d Fresh Greens" % n, 2.4, Color(0.5, 1.0, 0.5))
				_check_achievements()
		"crate":
			_open_crate(it)


func _open_crate(it: Dictionary) -> void:
	if bool(it["falling"]):
		_toast("Wait for it to land!")
		return
	var rar := int(it["rarity"])
	var loot: Dictionary = it["fixed"]
	var is_welcome := not loot.is_empty()
	if loot.is_empty():
		loot = _loot_for(rar)
	var parts := PackedStringArray()
	for k in loot.keys():
		var id: String = k
		var n := int(loot[k])
		if id == "xp":
			_award_xp(n, false)
			parts.append("+%d XP" % n)
		elif _inv_add(id, n):
			parts.append("+%d %s" % [n, ITEMS[id]["name"]])
	var node: Node3D = it["node"]
	_fx_burst(node.position + Vector3(0, 1, 0), RARITY_COLORS[rar])
	_toast("%s CRATE:  %s" % [RARITY_NAMES[rar].to_upper(), ", ".join(parts)], 4.0, RARITY_COLORS[rar])
	_award_xp(30 * (rar + 1))
	if rar >= 2:
		_flash(RARITY_COLORS[rar], 0.3)
		shake = maxf(shake, 0.4)
	if rar == 3:
		_unlock("legendary")
	if is_welcome:
		tut_flags["crate"] = true
	else:
		_daily_progress("drops")
	node.queue_free()
	_remove_interact(it)


func _start_sleep() -> void:
	if sleeping or driving:
		return
	sleeping = true
	sleep_timer = SLEEP_TIME
	sleep_rest_from = rest
	rover_speed = 0.0
	sleep_label.text = ["Sweet dreams, Space Explorer…", "Resting in crew quarters…", "Sleep cycle in progress…", "Rest cycle: restoring crew performance…"][bracket]


func _process_sleep(delta: float) -> void:
	if not sleeping:
		sleep_overlay.visible = false
		return
	sleep_timer -= delta
	var p := clampf(1.0 - sleep_timer / SLEEP_TIME, 0.0, 1.0)
	rest = lerpf(sleep_rest_from, 100.0, p)
	food = maxf(0.0, food - (8.0 / SLEEP_TIME) * delta)
	sleep_overlay.visible = true
	sleep_overlay.color.a = sin(PI * p) * 0.92
	sleep_label.modulate.a = sin(PI * p)
	if sleep_timer <= 0.0:
		sleeping = false
		rest = 100.0
		sleep_overlay.visible = false
		tut_flags["sleep"] = true
		_toast("Fully rested — Rest 100%", 2.6, Color(0.6, 0.8, 1.0))


func _toggle_rover() -> void:
	if state != SimState.SURFACE or sleeping or ui_modal != "":
		return
	if driving:
		driving = false
		rover_speed = 0.0
		var side := Basis(Vector3.UP, rover_heading) * Vector3.RIGHT
		player_pos = _clamp_world(_resolve_obstacles(rover.position + side * 3.2, 0.6))
		player_pos.y = PLAYER_Y
		cam_yaw = player_heading
		_toast("Exited rover")
	else:
		var d := Vector2(player_pos.x - rover.position.x, player_pos.z - rover.position.z).length()
		if d <= 7.0:
			driving = true
			rover_speed = 0.0
			cam_yaw = rover_heading
			_toast("Rover engaged — WASD to drive, R to exit")
		else:
			_toast("Rover is %d m away — walk closer, then press R" % int(d))


func _on_reset_spawn() -> void:
	if state != SimState.SURFACE:
		return
	driving = false
	rover_speed = 0.0
	sleeping = false
	sleep_overlay.visible = false
	player_pos = SPAWN_POS
	player_heading = 0.0
	cam_yaw = 0.0
	cam_target = player_pos
	_toast("Returned to landing pad")


# ═══════════════════════════════════════════════════════════════════════════
#  FX / FEEDBACK / COSMETICS
# ═══════════════════════════════════════════════════════════════════════════
func _fx_burst(pos: Vector3, col: Color) -> void:
	if not q_particles:
		return
	burst_fx.global_position = pos
	burst_fx.color = col
	burst_fx.restart()
	burst_fx.emitting = true


func _flash(col: Color, strength: float) -> void:
	if flash_rect == null:
		return
	flash_rect.color = Color(col.r, col.g, col.b, strength)
	create_tween().tween_property(flash_rect, "color:a", 0.0, 0.6)


func _toast(msg: String, dur := 2.6, col := Color(1, 0.95, 0.85)) -> void:
	if toast_label == null:
		return
	toast_label.text = msg
	toast_label.add_theme_color_override("font_color", col)
	toast_time = dur
	toast_label.modulate.a = 1.0
	toast_label.visible = true
	toast_label.scale = Vector2(1.08, 1.08)
	create_tween().tween_property(toast_label, "scale", Vector2.ONE, 0.25)


func _update_toast(delta: float) -> void:
	if toast_time > 0.0:
		toast_time -= delta
		toast_label.modulate.a = clampf(toast_time / 0.6, 0.0, 1.0)
		if toast_time <= 0.0:
			toast_label.visible = false


func _apply_customization() -> void:
	suit_idx = clampi(suit_idx, 0, PALETTE.size() - 1)
	accent_idx = clampi(accent_idx, 0, PALETTE.size() - 1)
	rover_idx = clampi(rover_idx, 0, PALETTE.size() - 1)
	visor_idx = clampi(visor_idx, 0, VISORS.size() - 1)
	var sc: Color = PALETTE[suit_idx]["col"]
	var vc: Color = VISORS[visor_idx]["col"]
	var ac: Color = PALETTE[accent_idx]["col"]
	var rc: Color = PALETTE[rover_idx]["col"]
	suit_mat.albedo_color = sc
	visor_mat.albedo_color = vc
	visor_mat.emission = vc * 0.6
	accent_mat.albedo_color = ac
	accent_mat.emission = ac
	rover_paint_mat.albedo_color = rc
	callsign_label.text = callsign


func _set_cosmetic(cat: String, i: int) -> void:
	match cat:
		"suit":
			suit_idx = i
		"visor":
			visor_idx = i
		"accent":
			accent_idx = i
		"rover":
			rover_idx = i
	_apply_customization()
	_save()
	_open_modal("custom", false)


# ═══════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ═══════════════════════════════════════════════════════════════════════════
func _style(bg: Color, border := Color(0, 0, 0, 0), radius := 12, bw := 0, margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.set_border_width_all(bw)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


func _panel_style() -> StyleBoxFlat:
	return _style(Color(0.05, 0.02, 0.03, 0.8), Color(0.95, 0.4, 0.2, 0.8), 14, 2, 12)


func _lbl(text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _outlined(l: Label, w := 6) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", w)
	return l


func _style_button(b: Button, base: Color, size := 16) -> void:
	b.add_theme_font_size_override("font_size", size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	b.add_theme_stylebox_override("normal", _style(base, base.lightened(0.3), 10, 2, 8))
	b.add_theme_stylebox_override("hover", _style(base.lightened(0.15), Color.WHITE, 10, 2, 8))
	b.add_theme_stylebox_override("pressed", _style(base.darkened(0.2), Color.WHITE, 10, 2, 8))
	b.add_theme_stylebox_override("disabled", _style(base.darkened(0.55), Color(1, 1, 1, 0.1), 10, 1, 8))
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.9), 10, 2, 8))


func _button(text: String, col: Color, cb: Callable, size := 15, min_size := Vector2(0, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	_style_button(b, col, size)
	b.pressed.connect(cb)
	return b


func _bar(color: Color, h := 20) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(120, h)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_font_size_override("font_size", 12)
	bar.add_theme_stylebox_override("fill", _style(color, Color(0, 0, 0, 0), 6, 0, 0))
	bar.add_theme_stylebox_override("background", _style(Color(0.12, 0.08, 0.08, 0.9), Color(1, 1, 1, 0.15), 6, 1, 0))
	return bar


func _bar_row(parent: Control, text: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _lbl(text, 15, Color(0.92, 0.86, 0.82))
	l.custom_minimum_size = Vector2(60, 0)
	row.add_child(l)
	var bar := _bar(color)
	row.add_child(bar)
	parent.add_child(row)
	return bar


func _wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l


# ═══════════════════════════════════════════════════════════════════════════
#  MENU UI
# ═══════════════════════════════════════════════════════════════════════════
func _build_menu_ui() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	add_child(menu_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(root)

	menu_panel = PanelContainer.new()
	menu_panel.anchor_bottom = 1.0
	menu_panel.offset_left = 36.0
	menu_panel.offset_right = 500.0
	menu_panel.offset_top = 24.0
	menu_panel.offset_bottom = -24.0
	menu_panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.02, 0.03, 0.86), Color(0.95, 0.4, 0.2, 0.85), 18, 2, 20))
	menu_panel.modulate.a = 0.0
	root.add_child(menu_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 9)
	scroll.add_child(vb)

	vb.add_child(_lbl("ARES PROGRAM  •  GALE CRATER EXPEDITION", 13, Color(0.98, 0.55, 0.3)))
	var title := _lbl("MARS SIMULATOR", 40)
	title.add_theme_color_override("font_outline_color", Color(0.9, 0.25, 0.1))
	title.add_theme_constant_override("outline_size", 3)
	vb.add_child(title)
	vb.add_child(_lbl("MASTER EDITION II", 18, Color(0.98, 0.55, 0.3)))
	vb.add_child(HSeparator.new())

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _style(Color(0.95, 0.5, 0.1, 0.22), Color(1.0, 0.65, 0.2), 20, 2, 8))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	streak_badge = _lbl("", 16, Color(1.0, 0.82, 0.45))
	badge.add_child(streak_badge)
	vb.add_child(badge)
	profile_label = _wrap(_lbl("", 13, Color(0.85, 0.8, 0.78)), 400)
	vb.add_child(profile_label)

	vb.add_child(_lbl("MISSION BRIEFING", 14, Color(0.98, 0.55, 0.3)))
	vb.add_child(_wrap(_lbl(
		"• Drop from orbit in the ARES-7 capsule and land beside Base Alpha.\n" +
		"• Mine glowing deposits, open supply drops, grow food and craft gear.\n" +
		"• Recover every Isotope Gem (green beams) to finish each expedition.\n" +
		"• Keep Power, Food and Rest up — shelter inside during flares.", 14, Color(0.92, 0.88, 0.85)), 400))

	age_label = _lbl("", 18)
	vb.add_child(age_label)
	age_slider = HSlider.new()
	age_slider.min_value = 8
	age_slider.max_value = 60
	age_slider.step = 1
	age_slider.custom_minimum_size = Vector2(0, 28)
	age_slider.value_changed.connect(_on_age_changed)
	vb.add_child(age_slider)
	diff_label = _wrap(_lbl("", 14, Color(1.0, 0.75, 0.5)), 400)
	vb.add_child(diff_label)
	branch_label = _wrap(_lbl("", 13, Color(0.8, 0.75, 0.72)), 400)
	vb.add_child(branch_label)

	tut_check = CheckBox.new()
	tut_check.text = "Play the training tutorial"
	tut_check.button_pressed = play_tutorial
	tut_check.add_theme_font_size_override("font_size", 15)
	tut_check.toggled.connect(func(on: bool): play_tutorial = on)
	vb.add_child(tut_check)

	launch_btn = Button.new()
	launch_btn.text = "▲  Launch Mission to Gale Crater"
	launch_btn.custom_minimum_size = Vector2(0, 60)
	_style_button(launch_btn, Color(0.82, 0.22, 0.10), 22)
	launch_btn.pressed.connect(_on_launch_pressed)
	vb.add_child(launch_btn)
	vb.add_child(_lbl("Rendering profile: %s  •  %s  •  %d threads" % [q_tier, q_os, q_cores], 12, Color(0.65, 0.6, 0.58)))

	var ev := _outlined(_lbl(EVENT_TEXT, 16, Color(1.0, 0.8, 0.6)))
	ev.anchor_left = 1.0
	ev.anchor_right = 1.0
	ev.offset_left = -560.0
	ev.offset_right = -32.0
	ev.offset_top = 26.0
	ev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ev)
	var hint := _outlined(_lbl("Drag to rotate Mars   •   Scroll to zoom", 14, Color(0.85, 0.8, 0.78)))
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -44.0
	hint.offset_bottom = -12.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	pin_label = _outlined(_lbl("◉ GALE CRATER\n5.4°S · 137.8°E", 15, Color(1.0, 0.45, 0.35)))
	pin_label.visible = false
	root.add_child(pin_label)


func _on_age_changed(v: float) -> void:
	cadet_age = int(v)
	bracket = _bracket_for(cadet_age)
	expedition = 1
	difficulty = _difficulty_for()
	var b := _br()
	age_label.text = "Cadet Age:  %d%s" % [cadet_age, "+" if cadet_age >= 60 else ""]
	diff_label.text = "Path: %s  •  drain ×%.2f  •  %d gems  •  hazards ×%.2f" % [b["name"], difficulty, int(b["gems"]), float(b["hazard"])]
	branch_label.text = str(b["desc"])
	_ensure_daily()


func _refresh_menu_profile() -> void:
	streak_badge.text = "★  %d-DAY STREAK   (best %d)" % [streak, best_streak]
	var reward := "Today's supply bonus ready on landing!" if claimed_day != _today() else "Today's supply bonus claimed — come back tomorrow."
	profile_label.text = "Level %d  •  %d XP to next  •  %d gems lifetime  •  %d expeditions  •  %d/%d achievements\n%s" % [
		level, _xp_needed(level) - xp, total_gems, expeditions_done, achievements.size(), ACHIEVEMENTS.size(), reward]
	tut_check.button_pressed = play_tutorial


# ═══════════════════════════════════════════════════════════════════════════
#  HUD
# ═══════════════════════════════════════════════════════════════════════════
func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)

	var vignette := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.05), Color(0.08, 0.02, 0.0, 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	vignette.texture = gt
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(vignette)

	# left column: telemetry + training
	var left := VBoxContainer.new()
	left.position = Vector2(16, 16)
	left.custom_minimum_size = Vector2(320, 0)
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(left)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	left.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(_lbl("ARES TELEMETRY", 17, Color(1.0, 0.6, 0.35)))
	cadet_label = _lbl("", 12, Color(0.75, 0.7, 0.68))
	vb.add_child(cadet_label)
	power_bar = _bar_row(vb, "Power", Color(1.0, 0.78, 0.2))
	food_bar = _bar_row(vb, "Food", Color(0.45, 0.85, 0.35))
	rest_bar = _bar_row(vb, "Rest", Color(0.4, 0.65, 1.0))
	hazard_label = _lbl("", 14)
	vb.add_child(hazard_label)
	mode_label = _lbl("", 13, Color(0.92, 0.88, 0.85))
	vb.add_child(mode_label)
	room_label = _lbl("", 13, Color(0.6, 0.85, 1.0))
	vb.add_child(room_label)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	vb.add_child(grid)
	grid.add_child(_button("Bag", Color(0.45, 0.3, 0.15), func(): if ui_modal == "": _open_modal("inventory"), 13, Vector2(68, 32)))
	grid.add_child(_button("Eat", Color(0.25, 0.5, 0.2), _eat_best, 13, Vector2(68, 32)))
	grid.add_child(_button("Rover", Color(0.7, 0.35, 0.1), _toggle_rover, 13, Vector2(68, 32)))
	grid.add_child(_button("Pad", Color(0.4, 0.2, 0.35), _on_reset_spawn, 13, Vector2(68, 32)))

	tut_panel = PanelContainer.new()
	tut_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.06, 0.12, 0.85), Color(0.4, 0.75, 1.0, 0.9), 14, 2, 12))
	tut_panel.visible = false
	left.add_child(tut_panel)
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 6)
	tut_panel.add_child(tvb)
	tut_title = _lbl("", 14, Color(0.6, 0.85, 1.0))
	tvb.add_child(tut_title)
	tut_text = _wrap(_lbl("", 16), 296)
	tvb.add_child(tut_text)
	tut_prog = _bar(Color(0.4, 0.75, 1.0), 8)
	tut_prog.show_percentage = false
	tvb.add_child(tut_prog)
	tvb.add_child(_lbl("Backspace — skip training", 11, Color(0.6, 0.65, 0.7)))

	# top centre: level / xp / streak / combo
	var top := PanelContainer.new()
	_anchor(top, 0.5, 0.0, 0.5, 0.0, -200.0, 12.0, 200.0, 12.0)
	top.add_theme_stylebox_override("panel", _panel_style())
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	top.add_child(tv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	level_label = _lbl("LV 1", 22, Color(1.0, 0.82, 0.3))
	row.add_child(level_label)
	rank_label = _lbl("", 13, Color(0.9, 0.85, 0.8))
	rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_label)
	streak_label = _lbl("", 14, Color(1.0, 0.65, 0.25))
	streak_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(streak_label)
	tv.add_child(row)
	xp_bar = _bar(Color(1.0, 0.78, 0.25), 12)
	xp_bar.show_percentage = false
	tv.add_child(xp_bar)
	xp_text = _lbl("", 11, Color(0.85, 0.8, 0.75))
	xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(xp_text)
	combo_label = _outlined(_lbl("", 20, Color(1.0, 0.45, 0.85)))
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.visible = false
	tv.add_child(combo_label)

	# top right: radar, clock, daily missions
	radar = RadarView.new()
	radar.game = self
	_anchor(radar, 1.0, 0.0, 1.0, 0.0, -200.0, 16.0, -16.0, 200.0)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(radar)
	mission_label = _outlined(_lbl("", 15, Color(1.0, 0.85, 0.65)))
	_anchor(mission_label, 1.0, 0.0, 1.0, 0.0, -460.0, 206.0, -16.0, 230.0)
	mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_root.add_child(mission_label)
	var dp := PanelContainer.new()
	_anchor(dp, 1.0, 0.0, 1.0, 0.0, -300.0, 236.0, -16.0, 236.0)
	dp.add_theme_stylebox_override("panel", _style(Color(0.05, 0.02, 0.03, 0.7), Color(0.5, 1.0, 0.6, 0.6), 12, 1, 10))
	dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(dp)
	daily_label = _wrap(_lbl("", 13, Color(0.85, 1.0, 0.85)), 260)
	dp.add_child(daily_label)

	toast_label = _outlined(_lbl("", 20), 8)
	_anchor(toast_label, 0.5, 0.0, 0.5, 0.0, -420.0, 128.0, 420.0, 160.0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.pivot_offset = Vector2(420, 16)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.visible = false
	hud_root.add_child(toast_label)

	# bottom: prompt + hotbar + help
	prompt_panel = PanelContainer.new()
	_anchor(prompt_panel, 0.5, 1.0, 0.5, 1.0, -230.0, -176.0, 230.0, -124.0)
	prompt_panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.02, 0.03, 0.85), Color(1.0, 0.82, 0.3, 0.9), 12, 2, 10))
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.visible = false
	hud_root.add_child(prompt_panel)
	var pvb := VBoxContainer.new()
	prompt_panel.add_child(pvb)
	prompt_label = _lbl("", 18, Color(1.0, 0.9, 0.6))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvb.add_child(prompt_label)
	mine_bar = _bar(Color(1.0, 0.6, 0.2), 10)
	mine_bar.max_value = 1.0
	mine_bar.show_percentage = false
	pvb.add_child(mine_bar)

	var hot := HBoxContainer.new()
	_anchor(hot, 0.5, 1.0, 0.5, 1.0, -330.0, -112.0, 330.0, -62.0)
	hot.alignment = BoxContainer.ALIGNMENT_CENTER
	hot.add_theme_constant_override("separation", 10)
	hot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hot)
	hot_food = _hot_slot(hot, Color(0.45, 0.85, 0.35))
	hot_cell = _hot_slot(hot, Color(1.0, 0.85, 0.25))
	hot_inv = _hot_slot(hot, Color(0.85, 0.65, 0.45))

	var help := _outlined(_lbl("WASD move  •  Shift sprint  •  F interact / hold to mine  •  I bag  •  E eat  •  Q cell  •  R rover  •  H pad  •  Esc pause", 12, Color(0.9, 0.85, 0.8)))
	_anchor(help, 0.0, 1.0, 1.0, 1.0, 0.0, -30.0, 0.0, -8.0)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(help)

	fact_panel = PanelContainer.new()
	_anchor(fact_panel, 0.0, 1.0, 0.0, 1.0, 16.0, -230.0, 376.0, -150.0)
	fact_panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.03, 0.12, 0.85), Color(0.8, 0.5, 1.0, 0.8), 12, 2, 10))
	fact_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fact_panel.visible = false
	hud_root.add_child(fact_panel)
	fact_label = _wrap(_lbl("", 14, Color(0.95, 0.9, 1.0)), 340)
	fact_panel.add_child(fact_label)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(0, 0, 0, 0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(flash_rect)

	sleep_overlay = ColorRect.new()
	sleep_overlay.color = Color(0, 0, 0, 0)
	sleep_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sleep_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sleep_overlay.visible = false
	hud_root.add_child(sleep_overlay)
	sleep_label = _lbl("", 30, Color(0.85, 0.9, 1.0))
	sleep_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleep_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sleep_overlay.add_child(sleep_label)


func _hot_slot(parent: Control, col: Color) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.05, 0.02, 0.03, 0.8), col, 10, 2, 8))
	p.custom_minimum_size = Vector2(190, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := _lbl("", 14, col.lightened(0.3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return l


func _build_intro_overlay() -> void:
	intro_layer = CanvasLayer.new()
	intro_layer.layer = 6
	add_child(intro_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_layer.add_child(root)
	letter_top = ColorRect.new()
	letter_top.color = Color.BLACK
	_anchor(letter_top, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 90.0)
	root.add_child(letter_top)
	letter_bot = ColorRect.new()
	letter_bot.color = Color.BLACK
	_anchor(letter_bot, 0.0, 1.0, 1.0, 1.0, 0.0, -90.0, 0.0, 0.0)
	root.add_child(letter_bot)
	var t := _lbl("ARES-7   •   ENTRY, DESCENT & LANDING   •   GALE CRATER", 18, Color(1.0, 0.6, 0.35))
	_anchor(t, 0.0, 0.0, 1.0, 0.0, 0.0, 32.0, 0.0, 60.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(t)
	intro_label = _lbl("", 15, Color(0.85, 0.95, 1.0))
	_anchor(intro_label, 0.0, 1.0, 1.0, 1.0, 40.0, -60.0, -40.0, -30.0)
	root.add_child(intro_label)
	var skip := _lbl("SPACE — skip", 14, Color(0.8, 0.75, 0.7))
	_anchor(skip, 0.0, 1.0, 1.0, 1.0, 40.0, -60.0, -40.0, -30.0)
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(skip)
	intro_msg = _outlined(_lbl("", 34, Color(1.0, 0.85, 0.6)), 10)
	_anchor(intro_msg, 0.0, 0.5, 1.0, 0.5, 0.0, 120.0, 0.0, 170.0)
	intro_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(intro_msg)
	intro_layer.visible = false


func _build_fade_layer() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 50
	add_child(fade_layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)


func _update_hud() -> void:
	power_bar.value = power
	food_bar.value = food
	rest_bar.value = rest
	var pulse := Color(1.0, 0.45 + 0.2 * sin(time_accum * 8.0), 0.45)
	power_bar.modulate = pulse if power < 25.0 else Color.WHITE
	food_bar.modulate = pulse if food < 25.0 else Color.WHITE
	rest_bar.modulate = pulse if rest < 25.0 else Color.WHITE
	cadet_label.text = "%s  •  %s  •  age %d  •  ×%.2f" % [callsign, _br()["name"], cadet_age, difficulty * ease]
	match hazard:
		Hazard.NONE:
			hazard_label.text = "● CLEAR SKIES"
			hazard_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		Hazard.DUST_STORM:
			hazard_label.text = "▲ DUST STORM  (%ds)" % int(hazard_timer)
			hazard_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
		Hazard.SOLAR_FLARE:
			hazard_label.text = "▲ SOLAR FLARE — GET INSIDE!  (%ds)" % int(hazard_timer)
			hazard_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	if driving:
		mode_label.text = "MODE: ROVER  •  %.1f m/s" % absf(rover_speed)
	elif food <= 0.0 or rest <= 0.0:
		mode_label.text = "MODE: ON FOOT  •  EXHAUSTED"
	else:
		mode_label.text = "MODE: ON FOOT  •  drill Lv %d" % drill_level
	var room := ""
	for r in rooms:
		var rr: Rect2 = r["rect"]
		if rr.has_point(Vector2(player_pos.x, player_pos.z)):
			room = r["name"]
	if room != "":
		room_label.text = "LOCATION: %s  (shelter • recharging)" % room
	else:
		var to_base := Vector2(HAB_POS.x - player_pos.x, HAB_POS.z + 9.0 - player_pos.z)
		var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
		var fwd := Vector2(-sin(cam_yaw), -cos(cam_yaw))
		var ang := atan2(to_base.dot(right), to_base.dot(fwd))
		var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
		room_label.text = "OUTSIDE  •  BASE %s %d m" % [arrows[wrapi(int(roundf(ang / (PI / 4.0))), 0, 8)], int(_dist_to_base(player_pos))]
	level_label.text = "LV %d" % level
	rank_label.text = str(_br()["name"]).to_upper()
	streak_label.text = "★ %d-DAY" % streak
	xp_bar.max_value = _xp_needed(level)
	xp_bar.value = xp
	xp_text.text = "%d / %d XP" % [xp, _xp_needed(level)]
	combo_label.visible = combo > 1
	if combo > 1:
		combo_label.text = "COMBO ×%.2f   (%ds)" % [1.0 + 0.25 * float(mini(combo, 9) - 1), ceili(combo_timer)]
	var m := floori(mission_time / 60.0)
	var s := int(mission_time) % 60
	mission_label.text = "MET %02d:%02d  •  EXPEDITION %d  •  GEMS %d/%d%s" % [m, s, expedition, gems, gem_target, "  ★" if mission_complete else ""]
	var lines := PackedStringArray(["DAILY MISSIONS"])
	for d in daily:
		var dd: Dictionary = d
		lines.append("%s %s  (%d/%d)" % ["✓" if bool(dd["done"]) else "·", dd["text"], mini(int(dd["prog"]), int(dd["goal"])), int(dd["goal"])])
	daily_label.text = "\n".join(lines)
	var food_n := _inv_count("ration") + _inv_count("greens") + _inv_count("energy_bar")
	hot_food.text = "[E]  Food  ×%d" % food_n
	hot_cell.text = "[Q]  Power Cell  ×%d" % _inv_count("power_cell")
	hot_inv.text = "[I]  Bag  %d / %d" % [inventory.size(), INV_SLOTS]
	var show_prompt := ui_modal == "" and not sleeping and (driving or not focus.is_empty())
	prompt_panel.visible = show_prompt
	if show_prompt:
		var is_hold := not driving and bool(focus.get("hold", false))
		mine_bar.visible = is_hold
		mine_bar.value = mine_progress
		if driving:
			prompt_label.text = "[R]  Exit rover"
		elif str(focus["act"]) == "rover":
			prompt_label.text = "[R / F]  Board ARES rover"
		elif is_hold:
			prompt_label.text = "[Hold F]  %s   (%d left)" % [focus["label"], int(focus["hp"])]
		else:
			var cd := float(focus.get("cd", 0.0)) - time_accum
			prompt_label.text = "[F]  %s%s" % [focus["label"], "   (ready in %ds)" % ceili(cd) if cd > 0.0 else ""]
	radar.queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════
#  MODAL WINDOWS (inventory, crafting, customisation, terminal, pause …)
# ═══════════════════════════════════════════════════════════════════════════
func _build_modal() -> void:
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 20
	add_child(modal_layer)
	modal_dim = ColorRect.new()
	modal_dim.color = Color(0, 0, 0, 0.55)
	modal_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_dim.visible = false
	modal_layer.add_child(modal_dim)
	modal_panel = PanelContainer.new()
	_anchor(modal_panel, 0.5, 0.5, 0.5, 0.5, -340.0, -260.0, 340.0, 260.0)
	modal_panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.03, 0.04, 0.96), Color(0.95, 0.45, 0.2, 0.95), 18, 2, 18))
	modal_dim.add_child(modal_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	modal_panel.add_child(vb)
	var head := HBoxContainer.new()
	modal_title = _lbl("", 22, Color(1.0, 0.65, 0.35))
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(modal_title)
	modal_close = _button("✕  Close (Esc)", Color(0.35, 0.2, 0.2), _close_modal, 14, Vector2(130, 34))
	head.add_child(modal_close)
	vb.add_child(head)
	vb.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation", 10)
	scroll.add_child(modal_body)


func _open_modal(kind: String, animate := true) -> void:
	if state != SimState.SURFACE:
		return
	ui_modal = kind
	modal_dim.visible = true
	for ch in modal_body.get_children():
		ch.queue_free()
	modal_close.visible = kind != "summary"
	match kind:
		"inventory":
			modal_title.text = "INVENTORY"
			tut_flags["inventory"] = true
			_fill_inventory()
		"craft":
			modal_title.text = "FABRICATOR"
			_fill_craft()
		"custom":
			modal_title.text = "LOCKER — CUSTOMISE"
			_fill_custom()
		"terminal":
			modal_title.text = "MISSION CONTROL"
			_fill_terminal()
		"pause":
			modal_title.text = "PAUSED"
			_fill_pause()
		"summary":
			modal_title.text = "EXPEDITION %d COMPLETE" % expedition
			_fill_summary()
		"break":
			modal_title.text = "TIME FOR A BREAK?"
			_fill_break()
	if animate:
		modal_panel.modulate.a = 0.0
		create_tween().tween_property(modal_panel, "modulate:a", 1.0, 0.15)


func _close_modal() -> void:
	if ui_modal == "custom":
		_save()
	ui_modal = ""
	if modal_dim != null:
		modal_dim.visible = false


func _fill_inventory() -> void:
	modal_body.add_child(_lbl("Slots %d / %d  •  click an item to use it  •  hover for details" % [inventory.size(), INV_SLOTS], 14, Color(0.85, 0.8, 0.78)))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	modal_body.add_child(grid)
	var order := {"food": 0, "tool": 1, "material": 2}
	var ids: Array = inventory.keys()
	ids.sort_custom(func(a, b): return int(order[ITEMS[a]["cat"]]) < int(order[ITEMS[b]["cat"]]))
	for id in ids:
		var info: Dictionary = ITEMS[id]
		var col: Color = info["col"]
		var item_id: String = id
		var b := _button("%s\n×%d" % [info["name"], _inv_count(item_id)], col.darkened(0.55), func(): _use_item(item_id), 13, Vector2(118, 72))
		b.tooltip_text = "%s  [%s]" % [info["desc"], info["cat"]]
		grid.add_child(b)
	for i in INV_SLOTS - ids.size():
		var e := Panel.new()
		e.custom_minimum_size = Vector2(118, 72)
		e.add_theme_stylebox_override("panel", _style(Color(0.1, 0.07, 0.07, 0.8), Color(1, 1, 1, 0.08), 10, 1, 0))
		grid.add_child(e)
	modal_body.add_child(_wrap(_lbl("Food restores Food/Rest • Power Cells restore Power (Q) • Materials are crafted at the Workshop Fabricator • Gems count toward your expedition.", 12, Color(0.7, 0.66, 0.64)), 620))


func _fill_craft() -> void:
	modal_body.add_child(_lbl("Drill level %d / 3  •  mining speed ×%.2f" % [drill_level, 0.75 + 0.35 * float(drill_level)], 15, Color(0.8, 0.65, 1.0)))
	for r in RECIPES:
		var rd: Dictionary = r
		var cost: Dictionary = rd["cost"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nm := _lbl(str(rd["name"]), 17)
		nm.custom_minimum_size = Vector2(170, 0)
		row.add_child(nm)
		var parts := PackedStringArray()
		for k in cost.keys():
			parts.append("%s %d/%d" % [ITEMS[k]["name"], _inv_count(str(k)), int(cost[k])])
		var cl := _lbl(", ".join(parts), 13, Color(0.6, 1.0, 0.6) if _can_afford(cost) else Color(1.0, 0.6, 0.5))
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(cl)
		var b := _button("Craft", Color(0.8, 0.45, 0.12), func(): _craft(rd), 15, Vector2(90, 38))
		b.disabled = not _can_afford(cost) or (str(rd["id"]) == "drill" and drill_level >= 3)
		row.add_child(b)
		modal_body.add_child(row)


func _fill_custom() -> void:
	var row := HBoxContainer.new()
	row.add_child(_lbl("Callsign:", 16))
	var le := LineEdit.new()
	le.text = callsign
	le.max_length = 12
	le.custom_minimum_size = Vector2(220, 34)
	le.text_changed.connect(func(t: String):
		callsign = t.strip_edges().to_upper() if t.strip_edges() != "" else "CADET"
		callsign_label.text = callsign)
	row.add_child(le)
	modal_body.add_child(row)
	_swatch_row("SUIT", PALETTE, "suit", suit_idx)
	_swatch_row("VISOR", VISORS, "visor", visor_idx)
	_swatch_row("ACCENTS", PALETTE, "accent", accent_idx)
	_swatch_row("ROVER PAINT", PALETTE, "rover", rover_idx)
	modal_body.add_child(_lbl("Level up and keep your daily streak to unlock more colours.", 12, Color(0.7, 0.66, 0.64)))


func _swatch_row(title: String, list: Array, cat: String, cur: int) -> void:
	modal_body.add_child(_lbl(title, 15, Color(1.0, 0.65, 0.35)))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	modal_body.add_child(flow)
	for i in list.size():
		var e: Dictionary = list[i]
		var ok := _is_unlocked(e)
		var col: Color = e["col"]
		var txt: String = e["name"] if ok else ("Lv %d" % int(e["lvl"]) if int(e["streak"]) == 0 else "%d-day streak" % int(e["streak"]))
		var b := _button(txt, col.darkened(0.25 if ok else 0.7), func(): _set_cosmetic(cat, i), 12, Vector2(100, 40))
		b.add_theme_color_override("font_outline_color", Color.BLACK)
		b.add_theme_constant_override("outline_size", 4)
		if i == cur:
			b.add_theme_stylebox_override("normal", _style(col.darkened(0.25), Color.WHITE, 10, 3, 8))
		b.disabled = not ok
		flow.add_child(b)


func _fill_terminal() -> void:
	modal_body.add_child(_wrap(_lbl("Commander %s  •  Level %d (%d / %d XP)  •  %d-day streak (best %d)\nGems %d  •  Mined %d  •  Harvested %d  •  Crafted %d  •  Driven %.1f km  •  Expeditions %d" % [
		callsign, level, xp, _xp_needed(level), streak, best_streak, total_gems, total_mined, total_harvest, total_crafted, total_drive / 1000.0, expeditions_done], 14), 620))
	modal_body.add_child(_lbl("DAILY MISSIONS  (reset at midnight UTC)", 16, Color(0.5, 1.0, 0.6)))
	for d in daily:
		var dd: Dictionary = d
		var row := HBoxContainer.new()
		var l := _lbl(("✓ " if bool(dd["done"]) else "· ") + str(dd["text"]), 14)
		l.custom_minimum_size = Vector2(300, 0)
		row.add_child(l)
		var pb := _bar(Color(0.5, 1.0, 0.6), 14)
		pb.max_value = float(dd["goal"])
		pb.value = minf(float(dd["prog"]), float(dd["goal"]))
		pb.show_percentage = false
		row.add_child(pb)
		modal_body.add_child(row)
	modal_body.add_child(_lbl("ACHIEVEMENTS  %d / %d" % [achievements.size(), ACHIEVEMENTS.size()], 16, Color(1.0, 0.75, 0.3)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	modal_body.add_child(grid)
	for k in ACHIEVEMENTS.keys():
		var a: Array = ACHIEVEMENTS[k]
		var got: bool = k in achievements
		grid.add_child(_lbl(("★ " if got else "☆ ") + "%s — %s" % [a[0], a[1]], 13, Color(1.0, 0.85, 0.4) if got else Color(0.55, 0.5, 0.5)))


func _fill_pause() -> void:
	modal_body.add_child(_button("▶  Resume", Color(0.25, 0.5, 0.2), _close_modal, 18, Vector2(0, 48)))
	modal_body.add_child(_button("Mission Control (stats, dailies, achievements)", Color(0.2, 0.35, 0.6), func(): _open_modal("terminal"), 16, Vector2(0, 44)))
	modal_body.add_child(_button("Replay training tutorial", Color(0.25, 0.45, 0.6), func():
		_close_modal()
		_start_tutorial(), 16, Vector2(0, 44)))
	modal_body.add_child(_button("Return to orbit (main menu)", Color(0.6, 0.2, 0.15), _return_to_menu, 16, Vector2(0, 44)))
	modal_body.add_child(_wrap(_lbl("Progress, streak and cosmetics are saved automatically.", 12, Color(0.7, 0.66, 0.64)), 600))


func _fill_summary() -> void:
	var m := floori(mission_time / 60.0)
	var s := int(mission_time) % 60
	modal_body.add_child(_wrap(_lbl("All %d Isotope Gems recovered in %02d:%02d.\n\nRewards: +300 XP, +2 Titanium\nLevel %d  •  %d-day streak  •  %d expeditions completed" % [gem_target, m, s, level, streak, expeditions_done], 17), 600))
	modal_body.add_child(_button("▲  Start Expedition %d  (more gems, tougher conditions)" % (expedition + 1), Color(0.25, 0.55, 0.25), _next_expedition, 17, Vector2(0, 52)))
	modal_body.add_child(_button("Keep exploring this area", Color(0.3, 0.3, 0.45), _close_modal, 15, Vector2(0, 42)))
	modal_body.add_child(_button("Return to orbit", Color(0.6, 0.2, 0.15), _return_to_menu, 15, Vector2(0, 42)))


func _fill_break() -> void:
	var mins := int(_br()["break_min"])
	var msgs := [
		"You've been exploring for %d minutes, Space Explorer! Great time to stretch, drink some water and rest your eyes." % mins,
		"%d minutes on Mars! Astronauts take breaks too — stretch, grab some water, look at something far away." % mins,
		"%d-minute check-in: a short break helps you stay sharp. Your streak and progress are saved." % mins,
		"Session check-in.",
	]
	modal_body.add_child(_wrap(_lbl(str(msgs[bracket]), 17), 600))
	modal_body.add_child(_button("Continue mission", Color(0.25, 0.5, 0.2), _close_modal, 17, Vector2(0, 48)))
	modal_body.add_child(_button("Save & return to orbit", Color(0.4, 0.3, 0.2), _return_to_menu, 15, Vector2(0, 42)))


# ═══════════════════════════════════════════════════════════════════════════
#  RADAR (inner class)
# ═══════════════════════════════════════════════════════════════════════════
class RadarView extends Control:
	var game
	const RANGE := 90.0

	func _map(rel: Vector2, right: Vector2, fwd: Vector2, c: Vector2, k: float, clamp_r := -1.0) -> Vector2:
		var v := Vector2(rel.dot(right), -rel.dot(fwd)) * k
		if clamp_r > 0.0 and v.length() > clamp_r:
			v = v.normalized() * clamp_r
		return c + v

	func _kind_col(kind: String) -> Color:
		match kind:
			"iron":
				return Color(1.0, 0.45, 0.25)
			"silica":
				return Color(0.95, 0.9, 1.0)
			"ice":
				return Color(0.5, 0.85, 1.0)
		return Color(0.75, 0.55, 1.0)

	func _draw() -> void:
		if game == null:
			return
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.5 - 3.0
		var edge := rad - 5.0
		draw_circle(c, rad + 3.0, Color(0.95, 0.45, 0.2, 0.9))
		draw_circle(c, rad, Color(0.06, 0.03, 0.03, 0.88))
		draw_arc(c, rad * 0.5, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.0)
		draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), Color(1, 1, 1, 0.07), 1.0)
		draw_line(c - Vector2(0, rad), c + Vector2(0, rad), Color(1, 1, 1, 0.07), 1.0)
		var pp: Vector3 = game.player_pos
		var yaw: float = game.cam_yaw
		var right := Vector2(cos(yaw), -sin(yaw))
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var k := rad / RANGE
		var br: Rect2 = game.base_rect
		var pts := PackedVector2Array()
		for corner in [br.position, Vector2(br.end.x, br.position.y), br.end, Vector2(br.position.x, br.end.y)]:
			var cv: Vector2 = corner
			pts.append(_map(Vector2(cv.x - pp.x, cv.y - pp.z), right, fwd, c, k, edge))
		draw_colored_polygon(pts, Color(0.3, 0.7, 1.0, 0.3))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.4, 0.8, 1.0, 0.9), 1.5)
		draw_circle(_map(Vector2(0.0 - pp.x, 14.0 - pp.z), right, fwd, c, k, edge), 3.0, Color(1.0, 0.6, 0.3))
		for it in game.interactables:
			var act: String = it["act"]
			var ip: Vector3 = it["pos"]
			var rel := Vector2(ip.x - pp.x, ip.z - pp.z)
			if act == "deposit" and rel.length() < RANGE:
				draw_circle(_map(rel, right, fwd, c, k), 2.5, _kind_col(str(it["kind"])))
			elif act == "crate":
				var sp := _map(rel, right, fwd, c, k, edge)
				draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.8, 0.2))
		for g in game.collectibles:
			var gn: Node3D = g["node"]
			var sp := _map(Vector2(gn.position.x - pp.x, gn.position.z - pp.z), right, fwd, c, k, edge)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -5), sp + Vector2(4, 0), sp + Vector2(0, 5), sp + Vector2(-4, 0)]), Color(0.3, 1.0, 0.5))
		if not game.driving:
			var rp: Vector3 = game.rover.position
			var rs := _map(Vector2(rp.x - pp.x, rp.z - pp.z), right, fwd, c, k, edge)
			draw_rect(Rect2(rs - Vector2(3, 4), Vector2(6, 8)), Color(1.0, 0.5, 0.15))
		if game.has_objective:
			var op: Vector3 = game.objective_pos
			var os := _map(Vector2(op.x - pp.x, op.z - pp.z), right, fwd, c, k, edge)
			var t: float = game.time_accum
			draw_arc(os, 5.0 + 3.0 * fmod(t * 1.5, 1.0), 0.0, TAU, 20, Color(1.0, 0.82, 0.3, 1.0 - fmod(t * 1.5, 1.0)), 2.0)
		var h: float = game.rover_heading if game.driving else game.player_heading
		var fdir := Vector2(-sin(h), -cos(h))
		var sd := Vector2(fdir.dot(right), -fdir.dot(fwd)).normalized()
		var perp := Vector2(-sd.y, sd.x)
		draw_colored_polygon(PackedVector2Array([c + sd * 8.0, c - sd * 5.0 + perp * 5.0, c - sd * 5.0 - perp * 5.0]), Color.WHITE)
		var npos := _map(Vector2(0, -1), right, fwd, Vector2.ZERO, 1.0).normalized() * (rad - 10.0) + c
		draw_string(ThemeDB.fallback_font, npos + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.6, 0.35))
