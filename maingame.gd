## =====================================================================
##  MARS SIMULATOR — single-file Godot 4 (4.3+) version
## =====================================================================
##  How to run:
##   1. Create a new Godot 4 project.
##   2. Make a new scene whose root is a plain "Node", attach this script,
##      save the scene and set it as the main scene (Project > Project Settings
##      > Application > Run > Main Scene).
##   3. Press F5.
##  Everything (planet, base, astronaut, rover, menus) is generated in code.
##  Progress is saved to user://mars_save.json.
##
##  Controls: WASD/arrows move · Space jump · Shift sprint · E interact ·
##  M Mission Control · drag to look · wheel/pinch to zoom.
##  On touch screens an on-screen joystick and buttons appear.
## =====================================================================
extends Node

# ---------------------------------------------------------------- main
const SAVE_PATH := "user://mars_save.json"

var save := {}
var mode := "orbit"
var orbit
var base
var ui

func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(640, 640)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	_setup_input()
	_load_game()
	ui = UI.new()
	ui.main = self
	add_child(ui)
	orbit = OrbitWorld.new()
	orbit.main = self
	add_child(orbit)
	base = BaseWorld.new()
	base.main = self
	add_child(base)
	ui.minimap.base = base
	if save["daily"] == null or int(save["daily"]["sol"]) != int(save["sol"]):
		save["daily"] = base.new_daily(int(save["sol"]))
	persist()
	set_mode("orbit")
	ui.update_hud()

func _setup_input() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "interact": [KEY_E], "sprint": [KEY_SHIFT], "missions": [KEY_M]}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)

func _load_game() -> void:
	save = {"wallet": 0, "completed": [], "assembled": [], "active": null, "decisions": {}, "sol": 1, "daily": null, "seed": 1, "suited": false,
		"cfg": {"name": "", "gender": "female", "helmet": "classic", "suit": 0, "skin": 1}}
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			for k in data:
				save[k] = data[k]
	# JSON turns ints into floats: tidy the fields we compare as ints
	save["wallet"] = int(save["wallet"])
	save["sol"] = int(save["sol"])
	save["seed"] = int(save["seed"])
	save["cfg"]["suit"] = int(save["cfg"].get("suit", 0))
	save["cfg"]["skin"] = int(save["cfg"].get("skin", 1))
	if save["active"] != null:
		var done: Array = []
		for v in save["active"]["done"]:
			done.append(int(v))
		save["active"]["done"] = done
		save["active"]["step"] = int(save["active"]["step"])
	if save["daily"] != null:
		var gh: Array = []
		for v in save["daily"]["gh"]:
			gh.append(int(v))
		save["daily"]["gh"] = gh
		save["daily"]["meals"] = int(save["daily"]["meals"])

func persist() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))

func add_gems(n: int) -> void:
	save["wallet"] = max(0, int(save["wallet"]) + n)
	if n > 0 and save["daily"] != null:
		save["daily"]["earned"] = int(save["daily"]["earned"]) + n
	persist()
	ui.update_hud()

func toast(msg: String) -> void:
	ui.toast(msg)

func fade(cb: Callable) -> void:
	ui.fade(cb)

func set_mode(m: String) -> void:
	mode = m
	orbit.activate(m == "orbit")
	base.activate(m != "orbit")
	base.customizing = m == "customize"
	if m == "customize":
		var portrait: bool = ui._is_portrait()
		base.cam.h_offset = 0.0 if portrait else -1.3
		base.cam.v_offset = -1.1 if portrait else 0.0
	else:
		base.cam.h_offset = 0.0
		base.cam.v_offset = 0.0
	ui.show_mode(m)

func enter_base() -> void:
	base.place_player_at_base()
	set_mode("base" if save["suited"] else "customize")
	toast("Gale Crater: 154 km wide, explored by NASA’s Curiosity rover since 2012")

func go_orbit() -> void:
	fade(_to_orbit)

func _to_orbit() -> void:
	set_mode("orbit")
	orbit.reset_after_base()

func open_customize() -> void:
	if base.in_rover:
		base.exit_rover(true)
	set_mode("customize")

func finish_customize() -> void:
	save["suited"] = true
	persist()
	base.cam_yaw = base.p_heading + PI + 0.6
	set_mode("base")
	toast("Walk with WASD or the joystick, jump with Space. Collect the glowing gems!")


# ======================================================================
# Mesh, material and label helpers
# ======================================================================
class Mk extends RefCounted:
	static var _mats := {}

	static func col(hex: String) -> Color:
		return Color(hex)

	static func mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
		var key := "s%s_%.2f_%.2f" % [c.to_html(), rough, metal]
		if _mats.has(key):
			return _mats[key]
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
		return m

	static func emissive(c: Color, energy := 1.0) -> StandardMaterial3D:
		var key := "e%s_%.2f" % [c.to_html(), energy]
		if _mats.has(key):
			return _mats[key]
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
		return m

	static func unshaded(c: Color, alpha := 1.0, additive := false, no_depth := false) -> StandardMaterial3D:
		var key := "u%s_%.2f_%s_%s" % [c.to_html(), alpha, additive, no_depth]
		if _mats.has(key):
			return _mats[key]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if alpha < 1.0 or additive:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		if no_depth:
			m.no_depth_test = true
		_mats[key] = m
		return m

	static func glass() -> StandardMaterial3D:
		if _mats.has("glass"):
			return _mats["glass"]
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.93, 1.0, 0.22)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["glass"] = m
		return m

	static func mi(parent: Node, mesh: Mesh, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
		var n := MeshInstance3D.new()
		n.mesh = mesh
		n.material_override = m
		n.position = pos
		if parent:
			parent.add_child(n)
		return n

	static func box(parent: Node, size: Vector3, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
		var b := BoxMesh.new()
		b.size = size
		return mi(parent, b, m, pos)

	static func cyl(parent: Node, rt: float, rb: float, h: float, m: Material, pos := Vector3.ZERO, segs := 16) -> MeshInstance3D:
		var c := CylinderMesh.new()
		c.top_radius = rt
		c.bottom_radius = rb
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		return mi(parent, c, m, pos)

	static func sphere(parent: Node, r: float, m: Material, pos := Vector3.ZERO, segs := 16, hemi := false) -> MeshInstance3D:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r if hemi else r * 2.0
		s.is_hemisphere = hemi
		s.radial_segments = segs
		s.rings = max(4, segs / 2)
		return mi(parent, s, m, pos)

	## Torus lying flat (ring around the Y axis).
	static func torus(parent: Node, r: float, thick: float, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
		var t := TorusMesh.new()
		t.inner_radius = r - thick
		t.outer_radius = r + thick
		t.rings = 48
		t.ring_segments = 8
		return mi(parent, t, m, pos)

	static func label(parent: Node, text: String, pos: Vector3, size := 64, color := Color.WHITE, pixel := 0.012, billboard := true) -> Label3D:
		var l := Label3D.new()
		l.text = text
		l.font_size = size
		l.pixel_size = pixel
		l.position = pos
		l.modulate = color
		l.outline_size = 14
		l.outline_modulate = Color(0.05, 0.03, 0.08, 0.9)
		if billboard:
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.double_sided = true
		if parent:
			parent.add_child(l)
		return l

	## Flat octahedron (used for gems).
	static func octa_mesh(r: float) -> ArrayMesh:
		var v := [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r * 1.2, 0), Vector3(0, -r * 1.2, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]
		var faces := [[2, 4, 0], [2, 1, 4], [2, 5, 1], [2, 0, 5], [3, 0, 4], [3, 4, 1], [3, 1, 5], [3, 5, 0]]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in faces:
			for i in f:
				st.add_vertex(v[i])
		st.generate_normals()
		return st.commit()

	## Half cylinder (top half) along Z, with end caps. Used for greenhouses.
	static func half_cyl_mesh(r: float, length: float, segs := 28) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hz := length / 2.0
		for i in segs:
			var a0 := PI * float(i) / segs
			var a1 := PI * float(i + 1) / segs
			var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
			var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
			var n0 := Vector3(cos(a0), sin(a0), 0)
			var n1 := Vector3(cos(a1), sin(a1), 0)
			for q in [[p0, n0, -hz], [p1, n1, -hz], [p1, n1, hz], [p0, n0, -hz], [p1, n1, hz], [p0, n0, hz]]:
				st.set_normal(q[1])
				st.add_vertex(q[0] + Vector3(0, 0, q[2]))
			for z in [-hz, hz]:
				st.set_normal(Vector3(0, 0, sign(z)))
				st.add_vertex(Vector3(0, 0, z))
				st.set_normal(Vector3(0, 0, sign(z)))
				st.add_vertex(p0 + Vector3(0, 0, z))
				st.set_normal(Vector3(0, 0, sign(z)))
				st.add_vertex(p1 + Vector3(0, 0, z))
		return st.commit()

	## Line loop (circle) in the XZ plane.
	static func circle_lines(r: float, c: Color, segs := 160) -> MeshInstance3D:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in segs + 1:
			var a := TAU * float(i) / segs
			st.add_vertex(Vector3(cos(a) * r, 0, sin(a) * r))
		var n := MeshInstance3D.new()
		n.mesh = st.commit()
		n.material_override = unshaded(c, c.a)
		return n

	## One-shot particle burst.
	static func burst(parent: Node, pos: Vector3, c: Color) -> void:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 18
		p.lifetime = 0.9
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -3.71, 0)
		var s := SphereMesh.new()
		s.radius = 0.08
		s.height = 0.16
		s.radial_segments = 6
		s.rings = 3
		p.mesh = s
		p.material_override = unshaded(c, 1.0)
		p.position = pos
		parent.add_child(p)
		p.emitting = true
		p.get_tree().create_timer(1.6).timeout.connect(p.queue_free)


# ======================================================================
# Static game data: missions, challenges, scenarios and text
# ======================================================================
class D extends RefCounted:
	const MISSIONS := [
		{"id": "mariner4", "name": "Mariner 4", "years": "1964–1965", "diff": "Easy", "reward": 10, "kind": "Explore",
		"brief": "The first spacecraft to photograph Mars up close. Recreate its photo pass over craters near the base, then send the pictures home.",
		"steps": [
			{"type": "visit", "text": "Photograph the craters", "verb": "Photograph", "points": [[75, 32], [105, 44], [165, 36]], "crater": true, "r": 3.2},
			{"type": "deliver", "text": "Transmit the photos from Mission Control", "to": "mc"}],
		"history": {"sub": "First close-up photos of another planet",
			"dates": [["Nov 28, 1964", "Launched from Cape Kennedy, Florida"], ["Jul 14, 1965", "Started photographing Mars on approach"], ["Jul 15, 1965", "Closest approach, 9,846 km above the surface"], ["Dec 1967", "Mission ended after extra tests while orbiting the Sun"]],
			"facts": ["It took 21 full photos plus part of a 22nd, covering about 1% of Mars.", "Data reached Earth at 8⅓ bits per second, so each photo took about 8 hours to send.", "Engineers were so eager that they hand-coloured the first image with pastel crayons from printed numbers before the computer finished it.", "Its cratered, Moon-like photos ended old ideas of canals and a lush Mars."]}},
		{"id": "viking1", "name": "Viking 1", "years": "1975–1982", "diff": "Easy", "reward": 15, "kind": "Collect",
		"brief": "The first US spacecraft to land safely on Mars and search for life. Scoop soil samples and run the biology experiments.",
		"steps": [
			{"type": "collect", "text": "Scoop soil samples", "cluster": [200, 46, 7], "items": [["Soil sample", "can", "c8763e"], ["Soil sample", "can", "c8763e"], ["Soil sample", "can", "c8763e"]]},
			{"type": "deliver", "text": "Run the biology experiments at Mission Control", "to": "mc"}],
		"history": {"sub": "First successful US landing on Mars",
			"dates": [["Aug 20, 1975", "Launched from Cape Canaveral"], ["Jun 19, 1976", "Entered orbit around Mars"], ["Jul 20, 1976", "Landed in Chryse Planitia, 7 years to the day after Apollo 11 landed on the Moon"], ["Nov 1982", "Contact with the lander was lost"]],
			"facts": ["It sent the first photo ever taken on the Martian surface, minutes after landing.", "A robotic arm scooped soil into three biology experiments looking for microbes.", "Most scientists concluded the results came from unusual soil chemistry, not life.", "The lander worked for more than 6 years, far beyond its 90-day goal."]}},
		{"id": "pathfinder", "name": "Mars Pathfinder & Sojourner", "years": "1996–1997", "diff": "Medium", "reward": 25, "kind": "Collect & assemble",
		"brief": "Pathfinder bounced to a landing on airbags and released Sojourner, the first rover on Mars. Gather its parts, build it, then scan a rock.",
		"steps": [
			{"type": "collect", "text": "Find the Sojourner parts", "cluster": [250, 48, 9], "items": [["Chassis", "box", "d8d2c8"], ["Rocker-bogie wheels", "wheel", "50545c"], ["Solar panel", "panel", "2a3f7a"], ["APXS spectrometer", "can", "d4a43a"]]},
			{"type": "deliver", "text": "Bring the parts to the garage workbench", "to": "bench"},
			{"type": "assemble", "title": "Assemble Sojourner", "text": "Tap the parts in the order the rover goes together.", "parts": [
				{"name": "Chassis", "clue": "Start with the insulated box that holds the computer. Everything else mounts on it.", "fact": "The “warm electronics box” kept the computer from freezing at night."},
				{"name": "Rocker-bogie wheels", "clue": "Next comes what lets the rover roll and climb over rocks.", "fact": "Six wheels on rocker-bogie suspension, a design later used on every NASA Mars rover."},
				{"name": "Solar panel", "clue": "Now the flat power source that sits on top.", "fact": "A small solar panel on top powered the rover."},
				{"name": "APXS spectrometer", "clue": "Last, the science instrument on the back.", "fact": "The APXS measured which chemical elements a rock contained."}]},
			{"type": "visit", "text": "Scan the rock Barnacle Bill", "verb": "Scan Barnacle Bill", "points": [[290, 36]], "rock": true, "r": 3.0}],
		"history": {"sub": "The first rover on another planet",
			"dates": [["Dec 4, 1996", "Launched from Cape Canaveral"], ["Jul 4, 1997", "Landed in Ares Vallis, bouncing about 15 times on airbags"], ["Jul 1997", "Sojourner rolled down a ramp onto the surface"], ["Sep 27, 1997", "Last transmission from the mission"]],
			"facts": ["Sojourner was about the size of a microwave oven and weighed roughly 11 kg.", "It was planned to work for 7 sols and lasted 83.", "Its name honours Sojourner Truth and was chosen in a student essay contest.", "Barnacle Bill was the first rock it analysed."]}},
		{"id": "opportunity", "name": "Opportunity rover", "years": "2003–2019", "diff": "Medium", "reward": 20, "kind": "Collect & drive",
		"brief": "Opportunity found tiny hematite “blueberries” that formed in water, then drove a marathon across Mars. Collect blueberries, then drive to a crater rim.",
		"steps": [
			{"type": "collect", "text": "Collect hematite blueberries", "cluster": [25, 64, 6], "items": [["Blueberry", "berry", "7d8aa6"], ["Blueberry", "berry", "7d8aa6"], ["Blueberry", "berry", "7d8aa6"], ["Blueberry", "berry", "7d8aa6"], ["Blueberry", "berry", "7d8aa6"]]},
			{"type": "visit", "text": "Drive ARES to the crater rim", "verb": "Reach the rim", "points": [[335, 150]], "need_rover": true, "r": 6.0}],
		"history": {"sub": "A 90-sol mission that lasted almost 15 years",
			"dates": [["Jul 7, 2003", "Launched from Cape Canaveral"], ["Jan 25, 2004", "Landed in Meridiani Planum and rolled into a small crater, a “hole in one”"], ["Mar 2015", "Passed marathon distance, 42.2 km"], ["Jun 10, 2018", "Last contact, during a planet-wide dust storm"], ["Feb 13, 2019", "NASA declared the mission complete"]],
			"facts": ["It was designed to last 90 sols and worked for more than 5,000.", "The hematite “blueberries” showed liquid water once soaked the rocks.", "It drove 45.16 km in total, a record for driving on another world.", "Its twin, Spirit, landed three weeks earlier on the other side of Mars."]}},
		{"id": "insight", "name": "InSight lander", "years": "2018–2022", "diff": "Medium", "reward": 25, "kind": "Collect & assemble",
		"brief": "InSight listened for marsquakes to map the inside of Mars. Gather the instruments and set them up on flat ground.",
		"steps": [
			{"type": "collect", "text": "Collect the instruments", "cluster": [135, 62, 7], "items": [["SEIS seismometer", "can", "d4a43a"], ["Wind & thermal shield", "dome", "e8e4de"], ["Heat probe (the mole)", "blade", "8a9099"]]},
			{"type": "deliver", "text": "Carry them to the deployment site", "to": [118, 80], "label": "Deployment site"},
			{"type": "assemble", "title": "Deploy InSight’s instruments", "text": "Tap the instruments in the order the robotic arm placed them.", "parts": [
				{"name": "SEIS seismometer", "clue": "First, the instrument that feels the ground shake goes down.", "fact": "Dec 19, 2018: the arm set the seismometer on the surface."},
				{"name": "Wind & thermal shield", "clue": "Next, cover the seismometer to protect it from wind and cold.", "fact": "Feb 2, 2019: the dome-shaped shield was lowered over it."},
				{"name": "Heat probe (the mole)", "clue": "Last, the instrument meant to hammer itself into the ground.", "fact": "Feb 12, 2019: the heat probe was placed beside them."}]}],
		"history": {"sub": "The first spacecraft to study the deep interior of Mars",
			"dates": [["May 5, 2018", "Launched from Vandenberg, California, the first interplanetary launch from the US West Coast"], ["Nov 26, 2018", "Landed on the flat plain of Elysium Planitia"], ["Apr 6, 2019", "Detected its first marsquake"], ["May 4, 2022", "Recorded the largest marsquake ever measured, magnitude 4.7"], ["Dec 2022", "Mission ended as dust covered its solar panels"]],
			"facts": ["It detected 1,319 marsquakes.", "Quake waves revealed the thickness of the crust and mantle and the size of the liquid core, the numbers in this simulator’s Inside Mars view.", "The “mole” never dug deep enough because the soil was unexpectedly clumpy.", "The seismometer could sense movements smaller than the width of a hydrogen atom."]}},
		{"id": "curiosity", "name": "Curiosity rover", "years": "2011–today", "diff": "Hard", "reward": 35, "kind": "Collect, assemble & drive",
		"brief": "Curiosity landed right here in Gale Crater and drilled rock to find an ancient lake. Build its drill, fit it to ARES, and drill the first rock.",
		"steps": [
			{"type": "collect", "text": "Find the drill parts", "cluster": [225, 72, 9], "items": [["MMRTG power unit", "can", "8a9099"], ["Robotic arm", "blade", "d8d2c8"], ["Drill bit", "box", "b8bcc4"]]},
			{"type": "deliver", "text": "Bring the parts to the garage workbench", "to": "bench"},
			{"type": "assemble", "title": "Build the drill", "text": "Tap the parts in the order needed to get the drill working.", "parts": [
				{"name": "MMRTG power unit", "clue": "Start with the power source. Nothing works without it.", "fact": "Curiosity runs on heat from decaying plutonium-238, not solar panels."},
				{"name": "Robotic arm", "clue": "Next, the 2.1 m limb that carries tools to a rock.", "fact": "The arm is 2.1 m long and holds five tools at its end."},
				{"name": "Drill bit", "clue": "Last, the tool on the very end of the arm.", "fact": "The drill hammers and spins to turn rock into powder for analysis."}]},
			{"type": "act", "text": "Drive ARES to John Klein and drill", "label": "Drill John Klein", "to": [305, 105], "loc_label": "John Klein", "need_rover": true, "anim": "drill"}],
		"history": {"sub": "The car-sized rover exploring Gale Crater",
			"dates": [["Nov 26, 2011", "Launched from Cape Canaveral"], ["Aug 6, 2012", "Landed in Gale Crater, lowered on cables by a rocket-powered sky crane"], ["Feb 8, 2013", "Drilled its first rock, named John Klein"], ["Mar 12, 2013", "NASA announced Gale once had a lake that could have supported microbes"], ["Today", "Still climbing Mount Sharp"]],
			"facts": ["It is the size of a small car and weighs about 900 kg.", "Engineers called the landing “seven minutes of terror” because it had to happen entirely on its own.", "Powder from John Klein contained clay minerals formed in water that was neither too acidic nor too salty.", "Mount Sharp, on your horizon, is the layered mountain Curiosity has been climbing for years."]}},
		{"id": "ingenuity", "name": "Perseverance & Ingenuity", "years": "2020–2024", "diff": "Hard", "reward": 40, "kind": "Collect, assemble & fly",
		"brief": "Perseverance carried Ingenuity, the first aircraft to fly on another planet. Gather its parts, assemble it on the landing pad and make the first flight.",
		"steps": [
			{"type": "collect", "text": "Find the helicopter parts", "cluster": [60, 84, 9], "items": [["Landing legs", "wheel", "b8bcc4"], ["Fuselage", "box", "d4a43a"], ["Rotor blades", "blade", "30333a"], ["Solar panel", "panel", "2a3f7a"]]},
			{"type": "deliver", "text": "Bring the parts to the landing pad", "to": "pad"},
			{"type": "assemble", "title": "Assemble Ingenuity", "text": "Build the helicopter from the ground up.", "parts": [
				{"name": "Landing legs", "clue": "Start at the bottom, with what it stands on.", "fact": "Four springy carbon-fibre legs absorb the landing."},
				{"name": "Fuselage", "clue": "Next, the tissue-box-sized body holding the batteries and computer.", "fact": "Heaters in the fuselage kept it alive through nights near −90 °C."},
				{"name": "Rotor blades", "clue": "Then the two blades that spin in opposite directions.", "fact": "Two 1.2 m rotors spin at about 2,400 rpm because the air is so thin."},
				{"name": "Solar panel", "clue": "Finally, the part that sits right on top of the mast.", "fact": "A small solar panel above the rotors recharged the batteries."}]},
			{"type": "act", "text": "Fly Ingenuity from the landing pad", "label": "Fly Ingenuity", "to": "pad", "anim": "heli"}],
		"history": {"sub": "The first powered flight on another planet",
			"dates": [["Jul 30, 2020", "Perseverance launched from Cape Canaveral with Ingenuity tucked underneath"], ["Feb 18, 2021", "Landed in Jezero Crater, an ancient lake bed"], ["Apr 19, 2021", "Ingenuity’s first flight: 39 seconds, 3 m high"], ["Apr 20, 2021", "MOXIE made oxygen from Martian air for the first time"], ["Jan 18, 2024", "72nd and final flight; a damaged rotor ended the mission"]],
			"facts": ["Ingenuity weighed 1.8 kg. It was planned to fly 5 times and flew 72.", "It carried a tiny piece of fabric from the Wright brothers’ 1903 Flyer.", "In total it flew about 17 km.", "MOXIE made 122 g of oxygen, about what a small dog breathes in 10 hours."]}}
	]

	const LOCATIONS := {
		"mc": {"p": [4.5, 3.8], "r": 2.9, "label": "Mission Control"},
		"bench": {"p": [49.6, -4.5], "r": 3.6, "label": "Garage workbench"},
		"pad": {"p": [0.0, 46.0], "r": 6.5, "label": "Landing pad"}
	}

	const CHALLENGES := {
		"jump": {"text": "Exercise: do 10 low-gravity jumps", "why": "Astronauts exercise about 2 hours a day so bones and muscles stay strong in low gravity.", "target": 10, "reward": 8},
		"walk": {"text": "Walk 250 m on foot", "target": 250, "unit": " m", "reward": 8},
		"drive": {"text": "Drive ARES 600 m", "target": 600, "unit": " m", "reward": 8},
		"greenhouse": {"text": "Check on 3 greenhouses", "why": "Walk up to a greenhouse to inspect its plants.", "target": 3, "reward": 8},
		"gems": {"text": "Find 3 gems on the terrain", "target": 3, "reward": 8},
		"o2check": {"text": "Inspect the oxygen tanks", "target": 1, "reward": 5},
		"comms": {"text": "Call home from the Mission Control desk", "why": "A message takes between 3 and 22 minutes to reach Earth, depending on where the planets are.", "target": 1, "reward": 5}
	}

	const DAILY_REWARD := {"meals": 6, "rest": 4, "sleep": 6, "bonus": 10}

	const MEALS := ["freeze-dried tacos", "Martian potato stew from Greenhouse 1", "space lasagne", "tomato soup with greenhouse basil", "a peanut butter tortilla"]

	const SCENARIOS := [
		{"id": "storm", "title": "Dust storm incoming", "blurb": "A regional storm is heading for Gale Crater.", "nodes": {
			"start": {"text": "Orbital weather data shows a regional dust storm heading for Gale Crater. It will darken the sky and cut solar power for days. In 2018 a storm like this ended NASA’s Opportunity rover.", "options": [
				{"label": "Seal the base and power down", "gain": "Crew and batteries stay safe", "loss": "Greenhouse grow lights go dark", "next": "a"},
				{"label": "Drive out and recover the weather station", "gain": "Save weeks of storm data", "loss": "A risky drive with low visibility", "next": "b"}]},
			"a": {"text": "Day two of the storm. Solar power has dropped to 10%, and the batteries are getting low.", "options": [
				{"label": "Power only life support", "gain": "Oxygen keeps flowing", "loss": "No contact with Earth for a sol", "next": "e1"},
				{"label": "Start the backup fuel cell", "gain": "Everything stays on and the plants survive", "loss": "Uses your emergency fuel reserve (costs gems)", "next": "e2"}]},
			"b": {"text": "You reach the station as the sky turns brown. Visibility is down to 20 m.", "options": [
				{"label": "Follow the rover’s recorded track home", "gain": "A safe, known route", "loss": "It’s slow, and the drive eats oxygen", "next": "e3"},
				{"label": "Take the shortcut through the gully", "gain": "Home in half the time", "loss": "Unknown terrain, you could get stuck", "next": "e4"}]},
			"e1": {"end": true, "title": "Quiet sols", "text": "The base rides out the storm on minimal power. Earth worries for a sol, but everyone is fine. A few lettuce plants wilt.", "fx": {"gems": 10, "energy": -10}},
			"e2": {"end": true, "title": "Lights on", "text": "The fuel cell keeps the greenhouses alive and the crew comfortable, but the emergency reserve is gone.", "fx": {"gems": -5, "energy": 30, "o2": 20}},
			"e3": {"end": true, "title": "Data delivered", "text": "You crawl home along your own tracks with the station strapped on. Scientists get the best storm record ever taken in Gale.", "fx": {"gems": 25, "o2": -30}},
			"e4": {"end": true, "title": "Stuck in the gully", "text": "A wheel sinks into soft sand. You dig ARES out by hand and limp home exhausted, but the station is safe.", "fx": {"gems": 15, "energy": -40, "o2": -20}}}},
		{"id": "water", "title": "Water recycler failure", "blurb": "The machine that recycles your drinking water has stopped.", "nodes": {
			"start": {"text": "The recycler that turns used water back into drinking water has stopped. You have 3 sols of stored water.", "options": [
				{"label": "Repair it yourself now", "gain": "Water flowing again today", "loss": "Uses spare parts and lots of energy", "next": "a"},
				{"label": "Ask Earth for help", "gain": "Engineers send an exact fix", "loss": "Each message takes up to 22 minutes to reach Earth", "next": "b"}]},
			"a": {"text": "Inside the recycler you find a cracked filter and a clogged pump.", "options": [
				{"label": "Swap in your only spare pump", "gain": "A quick, reliable fix", "loss": "No spare left for next time", "next": "e1"},
				{"label": "Clean the old pump and patch the filter", "gain": "Saves the spare", "loss": "Takes hours and tires you out", "next": "e2"}]},
			"b": {"text": "Earth replies the next morning: try a software reset first, then swap the pump if needed.", "options": [
				{"label": "Try the software reset", "gain": "Free and fast if it works", "loss": "Might not fix a hardware fault", "next": "e3"},
				{"label": "Go straight to the pump swap", "gain": "Certain to work", "loss": "Uses your only spare pump", "next": "e4"}]},
			"e1": {"end": true, "title": "Fixed fast", "text": "Water flows within the hour. Mission Control adds a spare pump to the next cargo flight.", "fx": {"gems": 15, "energy": -15}},
			"e2": {"end": true, "title": "Resourceful", "text": "After a long shift the patched pump hums back to life. Saving the spare is a real Mars skill.", "fx": {"gems": 25, "energy": -40}},
			"e3": {"end": true, "title": "Lucky reset", "text": "The reset clears a faulty sensor and the recycler restarts. The wait cost you a thirsty sol.", "fx": {"gems": 20, "energy": -20}},
			"e4": {"end": true, "title": "By the book", "text": "The new pump works perfectly, following Earth’s checklist step by step.", "fx": {"gems": 12, "energy": -5}}}},
		{"id": "rock", "title": "A strange rock", "blurb": "You spot an unusual rock that may have formed in water.", "nodes": {
			"start": {"text": "On a drive near Mount Sharp you spot a pale rock streaked with white veins. It might have formed in water.", "options": [
				{"label": "Drill a sample right now", "gain": "Science results today", "loss": "Wears the drill bit and drains the battery", "next": "a"},
				{"label": "Photograph it and return with the full science kit", "gain": "Better instruments, better data", "loss": "Costs time, and the route back is long", "next": "b"}]},
			"a": {"text": "The drill reaches 2 cm and the powder looks unusual. The rover battery is at 30%.", "options": [
				{"label": "Analyse the powder in the rover’s lab", "gain": "Instant answers", "loss": "The battery will be nearly empty for the drive home", "next": "e1"},
				{"label": "Seal the sample and analyse it at base", "gain": "A safe trip home", "loss": "Results wait until tomorrow", "next": "e2"}]},
			"b": {"text": "Next sol you return with the full kit. A ridge of similar rocks runs uphill.", "options": [
				{"label": "Carefully sample just the first rock", "gain": "One high-quality result", "loss": "You might miss the bigger picture", "next": "e3"},
				{"label": "Survey the whole ridge", "gain": "Map a possible ancient stream", "loss": "A long, exhausting day", "next": "e4"}]},
			"e1": {"end": true, "title": "Gypsum!", "text": "The lab finds calcium sulfate, the same mineral Curiosity found in white veins in Gale Crater, left behind by groundwater. You coast home on fumes.", "fx": {"gems": 20, "o2": -25}},
			"e2": {"end": true, "title": "Patient science", "text": "Back at base the sample confirms water-formed minerals. Safe and solid work.", "fx": {"gems": 15}},
			"e3": {"end": true, "title": "One perfect sample", "text": "Your sample is pristine and goes into a sealed tube for a future return to Earth, like Perseverance’s samples.", "fx": {"gems": 20}},
			"e4": {"end": true, "title": "The ancient stream", "text": "The ridge traces an old streambed. Scientists are thrilled, and you are exhausted.", "fx": {"gems": 35, "energy": -45}}}}
	]

	const FACTS_TEXT := """[b]Gravity[/b]  3.72 m/s², 38% of Earth’s
	[b]One full spin[/b]  24 h 37 min (a sol is 24 h 40 min)
	[b]One Mars year[/b]  687 Earth days
	[b]Radius[/b]  3,390 km, about half of Earth’s
	[b]Average temperature[/b]  −63 °C
	[b]Axial tilt[/b]  25.2°, so Mars has seasons

	[b]Moons[/b]
	[b]Phobos[/b], about 22 km across, circles Mars every 7 h 39 min only ~6,000 km above the surface. It is slowly spiralling inward.
	[b]Deimos[/b], about 12 km across, takes 30 h 18 min per orbit at ~20,000 km up.
	[i]Moon sizes and distances are enlarged so both fit on screen.[/i]"""

	const LAYERS_TEXT := """You’re looking at a slice cut out of Mars. Zoom out to see the surface again.

	[b][color=#d08a5e]Crust[/color][/b]
	Thickness: 24–72 km (avg. ~40 km)
	Temperature: −63 °C at the surface, a few hundred °C at its base
	Made of: basalt rock; iron-oxide dust makes it red
	State: solid

	[b][color=#ff8a3a]Mantle[/color][/b]
	Thickness: ~1,550 km
	Temperature: ~500 °C near the top to ~1,500 °C near the core
	Made of: silicate rock rich in iron and magnesium
	State: solid, with a likely molten layer at the very bottom

	[b][color=#ffc04a]Core[/color][/b]
	Radius: ~1,650–1,830 km
	Temperature: ~1,600–2,000 °C (estimated)
	Made of: iron and nickel with lots of sulfur and lighter elements
	State: liquid, but no longer powers a global magnetic field

	[i]Figures come from NASA’s InSight lander (2018–2022). The crust is drawn thicker than real life so you can see it.[/i]"""


# ======================================================================
# The astronaut model and animation
# ======================================================================
class Avatar extends Node3D:
	const SUITS := [
		{"name": "NASA white", "main": "f1ede6", "accent": "2f6fb5", "trim": "c23b2a"},
		{"name": "Mars orange", "main": "e8742f", "accent": "f2e6d8", "trim": "3a2a24"},
		{"name": "Explorer blue", "main": "3c74c4", "accent": "f2c14e", "trim": "e8e8ea"},
		{"name": "Stealth", "main": "30333a", "accent": "5fd3c4", "trim": "8a9099"},
		{"name": "Desert camo", "main": "b59a6a", "accent": "5b6b3a", "trim": "6e4b2a"},
		{"name": "Nebula purple", "main": "7a54b8", "accent": "ffb0e0", "trim": "e8e2f2"}]
	const SKINS := ["f3d2b6", "d9a77f", "a96e48", "6e4429"]
	const HELMETS := [["classic", "Classic"], ["bubble", "Bubble"], ["visor", "Visor pro"], ["retro", "Retro"]]

	var leg_l: Node3D
	var leg_r: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var swing := 0.0

	func build(cfg: Dictionary) -> void:
		for c in get_children():
			c.queue_free()
		var suit: Dictionary = SUITS[clampi(int(cfg.get("suit", 0)), 0, SUITS.size() - 1)]
		var fem: bool = cfg.get("gender", "female") == "female"
		var m_suit := Mk.mat(Color(suit["main"]), 0.75)
		var m_acc := Mk.mat(Color(suit["accent"]), 0.5, 0.15)
		var m_trim := Mk.mat(Color(suit["trim"]), 0.6)
		var m_skin := Mk.mat(Color(SKINS[clampi(int(cfg.get("skin", 1)), 0, 3)]), 0.8)
		var m_dark := Mk.mat(Color("24262c"), 0.6, 0.3)
		var m_hair := Mk.mat(Color("3b2416") if fem else Color("2a1a10"), 0.9)
		var sh := 0.27 if fem else 0.33
		var hip := 0.15 if fem else 0.13
		leg_l = _leg(1, hip, fem, m_suit, m_trim, m_dark)
		leg_r = _leg(-1, hip, fem, m_suit, m_trim, m_dark)
		Mk.cyl(self, 0.25 if fem else 0.3, 0.26 if fem else 0.24, 0.62, m_suit, Vector3(0, 1.22, 0))
		Mk.torus(self, 0.25, 0.04, m_acc, Vector3(0, 0.94, 0))
		var front := 0.24 if fem else 0.27
		Mk.box(self, Vector3(0.3, 0.2, 0.08), m_trim, Vector3(0, 1.28, front))
		var bc := [Color("ff5a4a"), Color("f2c14e"), Color("5fd3c4")]
		for i in 3:
			Mk.sphere(self, 0.025, Mk.unshaded(bc[i]), Vector3(-0.08 + i * 0.08, 1.3, front + 0.045), 8)
		Mk.box(self, Vector3(0.46, 0.62, 0.24), Mk.mat(Color("e8e4de"), 0.6), Vector3(0, 1.25, -0.36))
		Mk.cyl(self, 0.07, 0.07, 0.55, m_acc, Vector3(0.12, 1.27, -0.5), 10)
		Mk.cyl(self, 0.07, 0.07, 0.55, m_acc, Vector3(-0.12, 1.27, -0.5), 10)
		arm_l = _arm(1, sh, m_suit, m_acc, m_trim)
		arm_r = _arm(-1, sh, m_suit, m_acc, m_trim)
		Mk.torus(self, 0.17, 0.035, m_trim, Vector3(0, 1.56, 0))
		var head := Node3D.new()
		head.position.y = 1.76
		add_child(head)
		Mk.sphere(head, 0.15, m_skin, Vector3.ZERO, 20)
		var eye := Mk.unshaded(Color("1a1210"))
		Mk.sphere(head, 0.02, eye, Vector3(0.05, 0.02, 0.135), 8)
		Mk.sphere(head, 0.02, eye, Vector3(-0.05, 0.02, 0.135), 8)
		Mk.box(head, Vector3(0.05, 0.012, 0.01), Mk.mat(Color("9a4a3a")), Vector3(0, -0.055, 0.142))
		var cap := Mk.sphere(head, 0.158, m_hair, Vector3(0, 0.03, -0.02), 18, true)
		cap.rotation.x = -0.3
		if fem:
			var back := Mk.sphere(head, 0.162, m_hair, Vector3(0, -0.04, -0.03), 18)
			back.scale = Vector3(1.04, 1.1, 0.9)
			Mk.sphere(head, 0.06, m_hair, Vector3(0, 0.0, -0.17), 10)
		var glass := Mk.glass()
		var hw := Mk.mat(Color("f2efe9"), 0.4, 0.1)
		match str(cfg.get("helmet", "classic")):
			"bubble":
				Mk.sphere(head, 0.27, glass, Vector3.ZERO, 24)
				Mk.cyl(head, 0.006, 0.006, 0.25, Mk.mat(Color("9aa0a8")), Vector3(0.12, 0.33, -0.05), 6)
				Mk.sphere(head, 0.02, Mk.unshaded(Color("ff5a4a")), Vector3(0.12, 0.46, -0.05), 8)
			"visor":
				Mk.box(head, Vector3(0.46, 0.44, 0.46), hw, Vector3(0, 0.02, 0))
				Mk.box(head, Vector3(0.4, 0.18, 0.02), Mk.emissive(Color("0b2a3a"), 0.6), Vector3(0, 0.04, 0.235))
				Mk.box(head, Vector3(0.06, 0.12, 0.36), m_acc, Vector3(0, 0.28, -0.02))
			"retro":
				Mk.cyl(head, 0.24, 0.24, 0.42, glass, Vector3.ZERO, 24)
				Mk.sphere(head, 0.245, Mk.mat(Color("b8bcc4"), 0.35, 0.6), Vector3(0, 0.2, 0), 20, true)
				Mk.torus(head, 0.245, 0.025, Mk.mat(Color("b8bcc4"), 0.35, 0.6), Vector3(0, -0.2, 0))
				Mk.torus(head, 0.245, 0.02, m_acc, Vector3(0, 0.19, 0))
			_:
				Mk.sphere(head, 0.27, hw, Vector3.ZERO, 24)
				var vis := Mk.sphere(head, 0.2, Mk.emissive(Color("d4a43a"), 0.35), Vector3(0, 0.0, 0.12), 20)
				vis.scale = Vector3(1.0, 0.75, 0.8)
				Mk.box(head, Vector3(0.06, 0.06, 0.06), Mk.unshaded(Color("fff6d8")), Vector3(0.22, 0.1, 0.13))
				Mk.box(head, Vector3(0.06, 0.06, 0.06), Mk.unshaded(Color("fff6d8")), Vector3(-0.22, 0.1, 0.13))
		var nm := str(cfg.get("name", "")).strip_edges()
		if nm == "":
			nm = "Astronaut"
		Mk.label(self, nm, Vector3(0, 2.45, 0), 40, Color(suit["accent"]).lightened(0.3), 0.008)

	func _leg(side: int, hip: float, fem: bool, m_suit, m_trim, m_dark) -> Node3D:
		var p := Node3D.new()
		p.position = Vector3(side * hip, 0.92, 0)
		add_child(p)
		Mk.cyl(p, 0.1 if fem else 0.11, 0.09, 0.82, m_suit, Vector3(0, -0.41, 0), 12)
		var kn := Mk.sphere(p, 0.1, m_trim, Vector3(0, -0.45, 0.02), 10)
		kn.scale = Vector3(1, 0.6, 1)
		Mk.box(p, Vector3(0.2, 0.16, 0.32), m_dark, Vector3(0, -0.84, 0.05))
		return p

	func _arm(side: int, sh: float, m_suit, m_acc, m_trim) -> Node3D:
		var p := Node3D.new()
		p.position = Vector3(side * (sh + 0.04), 1.47, 0)
		add_child(p)
		Mk.cyl(p, 0.08, 0.07, 0.6, m_suit, Vector3(0, -0.3, 0), 12)
		Mk.sphere(p, 0.085, m_acc, Vector3(0, -0.63, 0), 10)
		var pad := Mk.sphere(p, 0.11, m_trim, Vector3.ZERO, 12)
		pad.scale = Vector3(1, 0.8, 1)
		return p

	## Walking / jumping / seated poses.
	func pose(dt: float, moving: bool, on_ground: bool, walk_t: float, seated: bool) -> void:
		if leg_l == null:
			return
		if seated:
			leg_l.rotation.x = -1.45
			leg_r.rotation.x = -1.45
			arm_l.rotation.x = -0.9
			arm_r.rotation.x = -0.9
			return
		var k := 1.0 - exp(-dt * 12.0)
		swing = lerp(swing, 1.0 if (moving and on_ground) else 0.0, 1.0 - exp(-dt * 10.0))
		var s := sin(walk_t) * 0.75 * swing
		var l_l := s
		var l_r := -s
		var a_l := -s * 0.8
		var a_r := s * 0.8
		if not on_ground:
			l_l = -0.6
			l_r = 0.25
			a_l = -2.5
			a_r = -2.5
		leg_l.rotation.x = lerp(leg_l.rotation.x, l_l, k)
		leg_r.rotation.x = lerp(leg_r.rotation.x, l_r, k)
		arm_l.rotation.x = lerp(arm_l.rotation.x, a_l, k)
		arm_r.rotation.x = lerp(arm_r.rotation.x, a_r, k)
		arm_l.rotation.z = 0.12
		arm_r.rotation.z = -0.12


# ======================================================================
# ARES, the six-wheeled rover
# ======================================================================
class Rover extends Node3D:
	var heading := -PI / 2.0
	var speed := 0.0
	var pitch := 0.0
	var roll := 0.0
	var wheels: Array = []
	var steers: Array = []
	var body: Node3D
	var drill_fore: Node3D
	var drill_bit: Node3D

	func _ready() -> void:
		body = Node3D.new()
		add_child(body)
		var white := Mk.mat(Color("ece7e0"), 0.55, 0.1)
		var orange := Mk.mat(Color("e0632c"), 0.5, 0.1)
		var dark := Mk.mat(Color("2c3038"), 0.6, 0.3)
		var grey := Mk.mat(Color("9aa0a8"), 0.5, 0.35)
		var solar := Mk.mat(Color("1b2b5a"), 0.25, 0.6)
		Mk.box(body, Vector3(2.1, 0.5, 3.8), white, Vector3(0, 0.98, 0))
		Mk.box(body, Vector3(2.16, 0.12, 3.86), orange, Vector3(0, 0.72, 0))
		for side in [1, -1]:
			var ares := Mk.label(body, "ARES", Vector3(side * 1.07, 0.98, 0.3), 110, Color.WHITE, 0.004, false)
			ares.outline_size = 18
			ares.rotation.y = PI / 2.0 * side
			var sub := Mk.label(body, "MARS ROVER 01", Vector3(side * 1.07, 0.84, -1.05), 34, Color("3a2a24"), 0.004, false)
			sub.outline_size = 0
			sub.rotation.y = PI / 2.0 * side
		Mk.box(body, Vector3(0.8, 0.14, 0.7), dark, Vector3(0, 1.3, 0.15))
		Mk.box(body, Vector3(0.8, 0.75, 0.14), dark, Vector3(0, 1.62, -0.25))
		Mk.box(body, Vector3(1.8, 0.45, 0.35), grey, Vector3(0, 1.45, 1.55))
		Mk.box(body, Vector3(1.0, 0.04, 0.25), Mk.unshaded(Color("5fd3c4")), Vector3(0, 1.69, 1.5))
		Mk.box(body, Vector3(0.08, 1.1, 0.08), dark, Vector3(0.95, 1.75, -0.55))
		Mk.box(body, Vector3(0.08, 1.1, 0.08), dark, Vector3(-0.95, 1.75, -0.55))
		Mk.box(body, Vector3(2.0, 0.08, 0.08), dark, Vector3(0, 2.3, -0.55))
		var sp := Mk.box(body, Vector3(2.0, 0.06, 1.2), solar, Vector3(0, 1.45, -1.25))
		sp.rotation.x = -0.12
		Mk.cyl(body, 0.05, 0.05, 1.5, grey, Vector3(0.75, 2.0, -1.6), 8)
		Mk.box(body, Vector3(0.36, 0.22, 0.28), white, Vector3(0.75, 2.8, -1.55))
		var lm := Mk.unshaded(Color("fff6d8"))
		Mk.box(body, Vector3(0.3, 0.14, 0.05), lm, Vector3(0.65, 1.05, 1.92))
		Mk.box(body, Vector3(0.3, 0.14, 0.05), lm, Vector3(-0.65, 1.05, 1.92))
		var tire := Mk.mat(Color("26272b"), 0.95)
		var hubm := Mk.mat(Color("b8bcc4"), 0.4, 0.5)
		for w in [[1.22, 1.35, true], [-1.22, 1.35, true], [1.22, 0.0, false], [-1.22, 0.0, false], [1.22, -1.35, false], [-1.22, -1.35, false]]:
			var st := Node3D.new()
			st.position = Vector3(w[0], 0.48, w[1])
			add_child(st)
			var spin := Node3D.new()
			st.add_child(spin)
			var t := Mk.cyl(spin, 0.48, 0.48, 0.4, tire, Vector3.ZERO, 20)
			t.rotation.z = PI / 2.0
			var h := Mk.cyl(spin, 0.22, 0.22, 0.42, hubm, Vector3.ZERO, 12)
			h.rotation.z = PI / 2.0
			for i in 10:
				var a := TAU * i / 10.0
				var tr := Mk.box(spin, Vector3(0.42, 0.07, 0.12), tire, Vector3(0, cos(a) * 0.49, sin(a) * 0.49))
				tr.rotation.x = a
			Mk.box(self, Vector3(0.12, 0.12, 0.5), grey, Vector3(w[0] * 0.9, 0.75, w[1]))
			wheels.append(spin)
			if w[2]:
				steers.append(st)

	## Curiosity mission reward: a drill arm on the front.
	func add_drill() -> void:
		if drill_fore:
			return
		var grey := Mk.mat(Color("9aa0a8"), 0.5, 0.35)
		var arm := Node3D.new()
		arm.position = Vector3(0.55, 1.05, 1.9)
		body.add_child(arm)
		Mk.box(arm, Vector3(0.1, 0.1, 0.7), grey, Vector3(0, 0, 0.35))
		drill_fore = Node3D.new()
		drill_fore.position.z = 0.7
		arm.add_child(drill_fore)
		Mk.box(drill_fore, Vector3(0.09, 0.6, 0.09), grey, Vector3(0, -0.3, 0))
		Mk.box(drill_fore, Vector3(0.2, 0.18, 0.2), Mk.mat(Color("2c3038")), Vector3(0, -0.58, 0))
		drill_bit = Mk.cyl(drill_fore, 0.03, 0.01, 0.3, Mk.mat(Color("b8bcc4"), 0.3, 0.7), Vector3(0, -0.72, 0), 8)


# ======================================================================
# On-screen joystick for touch screens
# ======================================================================
class Joystick extends Control:
	var value := Vector2.ZERO
	var touch_index := -1
	var _knob := Vector2.ZERO
	const R := 55.0

	func _ready() -> void:
		custom_minimum_size = Vector2(140, 140)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch:
			if ev.pressed and touch_index == -1:
				touch_index = ev.index
				_move(ev.position)
			elif not ev.pressed and ev.index == touch_index:
				touch_index = -1
				value = Vector2.ZERO
				_knob = Vector2.ZERO
				queue_redraw()
			accept_event()
		elif ev is InputEventScreenDrag and ev.index == touch_index:
			_move(ev.position)
			accept_event()

	func _move(local: Vector2) -> void:
		var d := local - size / 2.0
		if d.length() > R:
			d = d.normalized() * R
		_knob = d
		value = Vector2(d.x / R, -d.y / R)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, R + 12.0, Color(0.08, 0.04, 0.03, 0.35))
		draw_arc(c, R + 12.0, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0)
		draw_circle(c + _knob, 27.0, Color(1, 0.94, 0.9, 0.85))


# ======================================================================
# Round minimap that turns with the camera
# ======================================================================
class Minimap extends Control:
	var base

	func _ready() -> void:
		custom_minimum_size = Vector2(150, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if base == null:
			return
		var R := size.x / 2.0
		var c := Vector2(R, R)
		var sc := R / 110.0
		draw_circle(c, R, Color(0.48, 0.21, 0.12, 0.85))
		var cp: Vector3 = base.r_pos if base.in_rover else base.p_pos
		var fwd := Vector2(-sin(base.cam_yaw), -cos(base.cam_yaw))
		var ang := -PI / 2.0 - atan2(fwd.y, fwd.x)
		var to_screen := func(wx: float, wz: float) -> Vector2:
			return Vector2(wx - cp.x, wz - cp.z).rotated(ang) * sc
		_dot(c, to_screen.call(0.0, 0.0), 9.0 * sc, Color(0.94, 0.91, 0.87, 0.85), R, false)
		for g in base.gh_centers:
			_dot(c, to_screen.call(g.x, g.y), 5.0 * sc, Color(0.49, 0.86, 0.52, 0.85), R, false)
		_dot(c, to_screen.call(44.0, 0.0), 7.0 * sc, Color(0.94, 0.91, 0.87, 0.7), R, false)
		_dot(c, to_screen.call(0.0, 46.0), 7.0 * sc, Color(0.95, 0.76, 0.3, 0.6), R, false)
		for g in base.gems:
			if not g["taken"]:
				var p: Vector3 = g["node"].position
				var s: Vector2 = to_screen.call(p.x, p.z)
				if s.length() < R:
					_dot(c, s, 4.0, g["col"], R, false)
		for p in base.prizes:
			if not p["taken"]:
				var pp: Vector3 = p["node"].position
				_dot(c, to_screen.call(pp.x, pp.z), 5.0, Color("ffd24a"), R, true)
		if not base.in_rover:
			_dot(c, to_screen.call(base.r_pos.x, base.r_pos.z), 5.0, Color("ff7a3a"), R, true)
		for t in base.m_targets:
			_dot(c, to_screen.call(t.x, t.y), 7.0, Color("5fd3c4"), R, true)
		var h: float = base.rover.heading if base.in_rover else base.p_heading
		var dir := Vector2(sin(h), cos(h)).rotated(ang)
		var a := dir.angle()
		var pts := PackedVector2Array([c + Vector2(12, 0).rotated(a), c + Vector2(-8, -8).rotated(a), c + Vector2(-3, 0).rotated(a), c + Vector2(-8, 8).rotated(a)])
		draw_colored_polygon(pts, Color.WHITE)
		draw_arc(c, R - 1.0, 0, TAU, 64, Color(1, 1, 1, 0.4), 2.0)

	func _dot(c: Vector2, p: Vector2, r: float, col: Color, R: float, clamp_edge: bool) -> void:
		var q := p
		if q.length() > R - 8.0:
			if not clamp_edge:
				if q.length() > R + r:
					return
			else:
				q = q.normalized() * (R - 8.0)
		if clamp_edge:
			draw_rect(Rect2(c + q - Vector2(r, r), Vector2(r, r) * 2.0), col)
		else:
			draw_circle(c + q, r, col)


# ======================================================================
# Orbit view: Mars, moons, stars, interior cutaway, Gale pin
# ======================================================================
class OrbitWorld extends Node3D:
	const NOISE_LIB := """
	float hash(vec3 p){ p = fract(p*0.3183099 + vec3(0.11,0.17,0.13)); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
	float vnoise(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f*f*(3.0-2.0*f);
		return mix(mix(mix(hash(i), hash(i+vec3(1.0,0.0,0.0)), f.x), mix(hash(i+vec3(0.0,1.0,0.0)), hash(i+vec3(1.0,1.0,0.0)), f.x), f.y),
			mix(mix(hash(i+vec3(0.0,0.0,1.0)), hash(i+vec3(1.0,0.0,1.0)), f.x), mix(hash(i+vec3(0.0,1.0,1.0)), hash(i+vec3(1.0,1.0,1.0)), f.x), f.y), f.z); }
	float fbm(vec3 p){ float s = 0.0; float a = 0.5; for (int i = 0; i < 5; i++){ s += a*vnoise(p); p *= 2.03; a *= 0.5; } return s/0.96875; }
	"""

	const MARS_SHADER := """
	shader_type spatial;
	uniform bool cut = false;
	uniform vec3 n0 = vec3(1.0,0.0,0.0);
	uniform vec3 n1 = vec3(0.0,1.0,0.0);
	uniform vec3 n2 = vec3(0.0,0.0,1.0);
	uniform vec3 gale_dir = vec3(0.0,0.0,1.0);
	varying vec3 objp;
	varying vec3 wpos;
	%s
	vec3 h3(vec3 p){ return fract(sin(vec3(dot(p,vec3(127.1,311.7,74.7)), dot(p,vec3(269.5,183.3,246.1)), dot(p,vec3(113.5,271.9,124.6))))*43758.5453); }
	float craters(vec3 p){
		vec3 i = floor(p); vec3 f = fract(p); float res = 0.0;
		for (int x = -1; x <= 1; x++) { for (int y = -1; y <= 1; y++) { for (int z = -1; z <= 1; z++) {
			vec3 g = vec3(float(x), float(y), float(z)); vec3 o = h3(i + g);
			if (o.y > 0.5) { continue; }
			float rad = 0.12 + 0.25*o.x; float d = length(g + o - f);
			res += smoothstep(rad*0.75, rad, d)*(1.0 - smoothstep(rad, rad*1.25, d))*0.6 - (1.0 - smoothstep(rad*0.55, rad*0.85, d))*0.35;
		}}}
		return res;
	}
	void vertex(){ objp = VERTEX; wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
	void fragment(){
		if (cut && dot(wpos,n0) > 0.0 && dot(wpos,n1) > 0.0 && dot(wpos,n2) > 0.0) { discard; }
		vec3 p = normalize(objp);
		float n = fbm(p*1.8 + vec3(7.1,3.3,1.7));
		float d = fbm(p*7.0 + vec3(2.0,9.0,4.0));
		float dark = smoothstep(0.5, 0.62, n + (d - 0.5)*0.15);
		vec3 col = vec3(0.80 - 0.37*dark, 0.41 - 0.20*dark, 0.22 - 0.10*dark);
		col += (d - 0.5)*vec3(0.24, 0.15, 0.10);
		col += craters(p*9.0)*vec3(0.10, 0.06, 0.04) + craters(p*21.0 + vec3(3.0))*vec3(0.05, 0.03, 0.02);
		float lat = degrees(asin(clamp(p.y, -1.0, 1.0)));
		float lon = degrees(atan(-p.z, p.x));
		if (lon > -100.0 && lon < -35.0) {
			float c = -9.0 + 3.0*sin(lon*0.12);
			float w = 1.0 + 1.8*smoothstep(-100.0, -65.0, lon)*(1.0 - smoothstep(-55.0, -35.0, lon));
			float k = clamp(1.0 - abs(lat - c)/w, 0.0, 1.0);
			col -= vec3(0.20, 0.11, 0.05)*k;
		}
		float gd = degrees(acos(clamp(dot(p, gale_dir), -1.0, 1.0)));
		col += vec3(0.09, 0.05, 0.0)*exp(-pow((gd - 2.2)/0.35, 2.0));
		if (gd < 1.9) { col -= vec3(0.06, 0.04, 0.0); }
		float cap = max(smoothstep(76.0, 80.0, lat + (d - 0.5)*9.0), smoothstep(77.0, 82.0, -lat + (d - 0.5)*9.0));
		col = mix(col, vec3(0.96, 0.93, 0.90), cap);
		ALBEDO = clamp(col, 0.0, 1.0);
		ROUGHNESS = 0.95;
		SPECULAR = 0.15;
	}
	"""

	const ATMO_SHADER := """
	shader_type spatial;
	render_mode unshaded, blend_add, depth_draw_never, cull_back;
	void fragment(){ float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0); ALBEDO = vec3(1.0, 0.55, 0.35)*f*1.2; ALPHA = f; }
	"""

	const MOON_SHADER := """
	shader_type spatial;
	uniform float seed = 1.0;
	%s
	void vertex(){ VERTEX *= 0.72 + 0.55*fbm(VERTEX*1.6 + vec3(seed)); }
	void fragment(){ ALBEDO = vec3(0.55, 0.48, 0.43); ROUGHNESS = 1.0; }
	"""

	const SKY_SHADER := """
	shader_type sky;
	float hs(vec3 p){ p = fract(p*0.3183099 + vec3(0.11,0.17,0.13)); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
	void sky(){
		vec3 d = EYEDIR;
		vec3 cell = floor(d*320.0);
		float h = hs(cell);
		float star = step(0.9965, h)*(0.35 + 0.65*hs(cell + 3.1));
		vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), hs(cell + 7.7));
		float band = exp(-pow(dot(d, normalize(vec3(0.35, 1.0, 0.25))), 2.0)*28.0);
		vec3 c = tint*star + vec3(0.05, 0.04, 0.07)*band + vec3(0.008, 0.006, 0.014);
		if (LIGHT0_ENABLED) {
			float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
			c += vec3(1.0, 0.93, 0.8)*pow(s, 900.0)*6.0 + vec3(1.0, 0.7, 0.45)*pow(s, 60.0)*0.25;
		}
		COLOR = c;
	}
	"""

	var main
	var world_env: WorldEnvironment
	var env_res: Environment
	var cam: Camera3D
	var tilt: Node3D
	var spin: Node3D
	var mars: MeshInstance3D
	var mars_mat: ShaderMaterial
	var atmo: MeshInstance3D
	var caps: Node3D
	var pin: Node3D
	var pin_ring: MeshInstance3D
	var pin_label: Label3D
	var phobos_pivot: Node3D
	var deimos_pivot: Node3D
	var moon_labels: Array = []
	var sun_dir := Vector3(0.75, 0.25, 0.62).normalized()
	var gale_dir: Vector3

	var theta := 0.15
	var phi := 1.3
	var radius := 12.0
	var t_theta := 0.15
	var t_phi := 1.3
	var t_radius := 6.5
	var spin_paused := false
	var spin_target = null
	var cut := false
	var flying = null
	var touches := {}
	var pinch_d := 0.0
	var last_tap := 0.0

	const S_DIAG := Vector3(0.57735, 0.57735, 0.57735)

	static func ll2v(lat_deg: float, lon_deg: float) -> Vector3:
		var la := deg_to_rad(lat_deg)
		var lo := deg_to_rad(lon_deg)
		return Vector3(cos(la) * cos(lo), sin(la), -cos(la) * sin(lo))

	func _ready() -> void:
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SKY_SHADER
		sm.shader = sh
		sky.sky_material = sm
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("3a2a33")
		env.ambient_light_energy = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		world_env = WorldEnvironment.new()
		world_env.environment = env
		env_res = env
		add_child(world_env)
		var sun := DirectionalLight3D.new()
		sun.light_color = Color("fff1e2")
		sun.light_energy = 1.4
		add_child(sun)
		sun.look_at_from_position(sun_dir * 10.0, Vector3.ZERO, Vector3.UP)

		cam = Camera3D.new()
		cam.fov = 45
		cam.near = 0.01
		cam.far = 3000
		add_child(cam)

		tilt = Node3D.new()
		tilt.rotation.z = deg_to_rad(25.19)
		add_child(tilt)
		spin = Node3D.new()
		tilt.add_child(spin)

		gale_dir = ll2v(-5.4, 137.8)
		var smesh := SphereMesh.new()
		smesh.radius = 1.0
		smesh.height = 2.0
		smesh.radial_segments = 128
		smesh.rings = 64
		mars_mat = ShaderMaterial.new()
		var msh := Shader.new()
		msh.code = MARS_SHADER % NOISE_LIB
		mars_mat.shader = msh
		mars_mat.set_shader_parameter("gale_dir", gale_dir)
		mars = Mk.mi(spin, smesh, mars_mat)

		var amesh := SphereMesh.new()
		amesh.radius = 1.045
		amesh.height = 2.09
		amesh.radial_segments = 64
		amesh.rings = 32
		var am := ShaderMaterial.new()
		var ash := Shader.new()
		ash.code = ATMO_SHADER
		am.shader = ash
		atmo = Mk.mi(self, amesh, am)

		_build_caps()
		_build_pin()
		_build_moons()

	func _build_caps() -> void:
		caps = Node3D.new()
		caps.visible = false
		add_child(caps)
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.vertex_color_use_as_albedo = true
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var layers := [[0.82, 1.0, Color("8c4a2c"), Color("b86a43")], [0.5, 0.82, Color("ff8a2a"), Color("a8401a")], [0.0, 0.5, Color("fff1a8"), Color("ffa630")]]
		var shades := [1.0, 0.8, 0.64]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 40
		var rsegs := 6
		for face in 3:
			for L in layers:
				var r0: float = L[0]
				var r1: float = L[1]
				for i in segs:
					for j in rsegs:
						var quad := []
						for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
							var a: float = (PI / 2.0) * q[0] / segs
							var rr: float = lerp(r0, r1, float(q[1]) / rsegs)
							var x := cos(a) * rr
							var y := sin(a) * rr
							var v := Vector3(x, y, 0.0)
							if face == 1:
								v = Vector3(0.0, y, x)
							elif face == 2:
								v = Vector3(x, 0.0, y)
							var t := 0.0 if r1 == r0 else (rr - r0) / (r1 - r0)
							var c: Color = L[2].lerp(L[3], t) * shades[face]
							c.a = 1.0
							st.set_color(c)
							st.add_vertex(v)
		Mk.mi(caps, st.commit(), cm)
		var specs := [["Crust", "24–72 km thick", Vector3(0.66, 0.03, 0.62), Color("e0a07a")], ["Mantle", "~1,550 km thick", Vector3(0.03, 0.47, 0.47), Color("ff9a4a")], ["Core", "liquid iron", Vector3(0.24, 0.03, 0.24), Color("ffd36a")]]
		for s in specs:
			var l := Mk.label(caps, "%s\n%s" % [s[0], s[1]], s[2], 40, s[3], 0.0011)
			l.no_depth_test = true
			l.render_priority = 10

	func _build_pin() -> void:
		pin = Node3D.new()
		pin.position = gale_dir
		pin.quaternion = Quaternion(Vector3.UP, gale_dir)
		spin.add_child(pin)
		Mk.cyl(pin, 0.004, 0.004, 0.12, Mk.unshaded(Color("fff0c8")), Vector3(0, 0.06, 0), 8)
		Mk.sphere(pin, 0.022, Mk.unshaded(Color("ffd24a")), Vector3(0, 0.125, 0), 12)
		pin_ring = Mk.torus(pin, 0.036, 0.006, Mk.unshaded(Color("ffd24a"), 0.9), Vector3(0, 0.004, 0))
		pin_label = Mk.label(pin, "Gale Crater\ndouble-click to land", Vector3(0, 0.23, 0), 40, Color("ffd24a"), 0.0018)
		pin_label.no_depth_test = true
		pin_label.render_priority = 10

	func _build_moons() -> void:
		phobos_pivot = Node3D.new()
		deimos_pivot = Node3D.new()
		tilt.add_child(phobos_pivot)
		tilt.add_child(deimos_pivot)
		deimos_pivot.rotation.y = 2.2
		var data := [[phobos_pivot, 1.9, 0.085, 3.0, "Phobos"], [deimos_pivot, 3.4, 0.055, 9.0, "Deimos"]]
		for d in data:
			var mm := ShaderMaterial.new()
			var msh := Shader.new()
			msh.code = MOON_SHADER % NOISE_LIB
			mm.shader = msh
			mm.set_shader_parameter("seed", d[3])
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			var m := Mk.mi(d[0], s, mm, Vector3(d[1], 0, 0))
			m.scale = Vector3(d[2] * 1.35, d[2], d[2] * 1.1)
			var l := Mk.label(d[0], d[4], Vector3(d[1], 0.17, 0), 40, Color("c9b8ab"), 0.0026)
			moon_labels.append(l)
			tilt.add_child(Mk.circle_lines(d[1], Color(1.0, 0.69, 0.54, 0.3)))

	func activate(on: bool) -> void:
		visible = on
		world_env.environment = env_res if on else null
		process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		cam.current = on

	func pin_world() -> Vector3:
		return pin.global_position

	func _process(dt: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0
		if spin_target != null:
			spin.rotation.y = lerp(spin.rotation.y, float(spin_target), 1.0 - exp(-dt * 3.0))
			if abs(spin.rotation.y - float(spin_target)) < 0.002:
				spin_target = null
		elif not spin_paused:
			spin.rotation.y += dt * TAU / 45.0
		phobos_pivot.rotation.y += dt * TAU / 14.0
		deimos_pivot.rotation.y += dt * TAU / 56.0
		var ph := fmod(t * 1.1, 1.0)
		pin_ring.scale = Vector3.ONE * (1.0 + ph * 0.9)

		if flying != null:
			flying["t"] = min(1.0, flying["t"] + dt / 1.8)
			var f: float = flying["t"]
			var e := 2.0 * f * f if f < 0.5 else 1.0 - pow(-2.0 * f + 2.0, 2.0) / 2.0
			var pw := pin_world()
			var from_dir: Vector3 = flying["from"].normalized()
			var to_dir := pw.normalized()
			var q := Quaternion(from_dir, to_dir) if from_dir.dot(to_dir) > -0.999 else Quaternion(Vector3.UP, PI)
			var qt := Quaternion.IDENTITY.slerp(q, e)
			var r: float = lerp(flying["from"].length(), 1.7, e)
			cam.position = (qt * from_dir) * r
			cam.look_at(Vector3.ZERO.lerp(pw, e), Vector3.UP)
			if f >= 0.88 and not flying["done"]:
				flying["done"] = true
				main.fade(main.enter_base)
		else:
			var k := 1.0 - exp(-dt * 7.0)
			theta = lerp(theta, t_theta, k)
			phi = lerp(phi, t_phi, k)
			radius = lerp(radius, t_radius, 1.0 - exp(-dt * 3.5))
			cam.position = Vector3(radius * sin(phi) * sin(theta), radius * cos(phi), radius * sin(phi) * cos(theta))
			cam.look_at(Vector3.ZERO, Vector3.UP)
			var want_cut := radius < 3.0
			if want_cut != cut:
				set_cut(want_cut)

		if cut:
			var d := cam.position.normalized()
			var side := Vector3.UP.cross(d)
			if side.length() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized()
			d = d.rotated(Vector3.UP, 0.55).rotated(side, -0.3).normalized()
			var q := Quaternion(S_DIAG, d)
			caps.quaternion = q
			mars_mat.set_shader_parameter("n0", q * Vector3.RIGHT)
			mars_mat.set_shader_parameter("n1", q * Vector3.UP)
			mars_mat.set_shader_parameter("n2", q * Vector3.BACK)

		var pw2 := pin_world()
		var vis := pw2.normalized().dot((cam.position - pw2).normalized()) > 0.06
		if cut:
			var q2 := caps.quaternion
			if pw2.dot(q2 * Vector3.RIGHT) > 0 and pw2.dot(q2 * Vector3.UP) > 0 and pw2.dot(q2 * Vector3.BACK) > 0:
				vis = false
		if flying != null and flying["t"] > 0.55:
			vis = false
		pin_label.visible = vis
		pin.visible = vis or not cut
		if flying != null and flying["t"] > 0.55:
			pin.visible = false

	func set_cut(c: bool) -> void:
		cut = c
		caps.visible = c
		atmo.visible = not c
		for l in moon_labels:
			l.visible = not c
		mars_mat.set_shader_parameter("cut", c)
		main.ui.set_fact_mode(c)

	func toggle_inside() -> void:
		var portrait := get_viewport().get_visible_rect().size.y > get_viewport().get_visible_rect().size.x
		t_radius = 6.5 if cut else (2.75 if portrait else 2.3)

	func best_spin_angle() -> float:
		var cur := spin.rotation.y
		var best := cur
		var bd := -2.0
		for i in 120:
			var a := cur + TAU * i / 120.0
			spin.rotation.y = a
			var d := pin.global_position.normalized().dot(sun_dir)
			if d > bd:
				bd = d
				best = a
		spin.rotation.y = cur
		return cur + wrapf(best - cur, -PI, PI)

	func aim_at_pin(r: float) -> void:
		var d := pin_world().normalized()
		var th := atan2(d.x, d.z)
		t_theta = theta + wrapf(th - theta, -PI, PI)
		t_phi = clamp(acos(d.y), 0.2, PI - 0.2)
		t_radius = r

	func find_gale() -> void:
		spin_paused = true
		spin_target = null
		spin.rotation.y = best_spin_angle()
		aim_at_pin(3.6)
		main.toast("Double-click (or double-tap) the glowing pin to land")

	func fly_to_gale() -> void:
		if flying != null:
			return
		spin_paused = true
		if cut:
			set_cut(false)
		spin_target = best_spin_angle()
		flying = {"t": 0.0, "from": cam.position, "done": false}
		main.ui.set_orbit_hint("Descending to Gale Crater…")

	func reset_after_base() -> void:
		flying = null
		spin_paused = false
		spin_target = null
		spin.rotation.y = best_spin_angle()
		var d := pin_world().normalized()
		theta = atan2(d.x, d.z)
		t_theta = theta
		phi = clamp(acos(d.y), 0.2, PI - 0.2)
		t_phi = phi
		radius = 3.1
		t_radius = 6.5
		main.ui.set_orbit_hint("")

	func _pin_hit(screen: Vector2) -> bool:
		if not pin_label.visible:
			return false
		var pw := pin_world()
		if cam.is_position_behind(pw):
			return false
		var sp := cam.unproject_position(pw + pw.normalized() * 0.1)
		return sp.distance_to(screen) < 60.0

	func _try_land(screen: Vector2) -> void:
		if _pin_hit(screen):
			fly_to_gale()

	func _unhandled_input(ev: InputEvent) -> void:
		if flying != null:
			return
		var touch := DisplayServer.is_touchscreen_available()
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
				t_radius = clamp(t_radius * 0.9, 1.75, 14.0)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
				t_radius = clamp(t_radius * 1.1, 1.75, 14.0)
			elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed and ev.double_click:
				_try_land(ev.position)
			elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed and _pin_hit(ev.position):
				main.toast("Double-click the pin to land")
		elif ev is InputEventMouseMotion and not touch:
			if ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
				t_theta -= ev.relative.x * 0.006
				t_phi = clamp(t_phi - ev.relative.y * 0.006, 0.15, PI - 0.15)
		elif ev is InputEventScreenTouch:
			if ev.pressed:
				touches[ev.index] = ev.position
				if ev.double_tap:
					_try_land(ev.position)
			else:
				touches.erase(ev.index)
			pinch_d = 0.0
		elif ev is InputEventScreenDrag:
			touches[ev.index] = ev.position
			if touches.size() >= 2:
				var k := touches.keys()
				var d: float = touches[k[0]].distance_to(touches[k[1]])
				if pinch_d > 0.0 and d > 0.0:
					t_radius = clamp(t_radius * pinch_d / d, 1.75, 14.0)
				pinch_d = d
			else:
				t_theta -= ev.relative.x * 0.006
				t_phi = clamp(t_phi - ev.relative.y * 0.006, 0.15, PI - 0.15)
		elif ev is InputEventMagnifyGesture:
			t_radius = clamp(t_radius / ev.factor, 1.75, 14.0)


# ======================================================================
# Gale Crater base: terrain, buildings, player, rover, gems, missions, daily life
# ======================================================================
class BaseWorld extends Node3D:
	const HUB_R := 9.0
	const DOOR_HALF := 0.2
	const GRAVITY := 3.71

	var main
	var world_env: WorldEnvironment
	var env_res: Environment
	var cam: Camera3D
	var avatar: Node3D
	var rover: Node3D
	var obstacles: Array = []
	var labels: Array = []
	var gems: Array = []
	var prizes: Array = []

	# player
	var p_pos := Vector3(18, 0, -1)
	var p_vy := 0.0
	var p_ground := true
	var p_heading := PI / 2.0
	var in_rover := false
	var walk_t := 0.0
	var o2 := 100.0
	var energy := 100.0
	var r_pos := Vector3(45, 0.2, 0)

	# camera
	var cam_yaw := -PI / 2.0 + 0.6
	var cam_pitch := 0.32
	var cam_dist := 7.0
	var cam_dist_t := 7.0
	var last_drag := -10.0

	var customizing := false
	var busy := false
	var jump_queued := false
	var gems_got := 0
	var prizes_got := 0
	var prize_nag := 0.0
	var o2_warned := false
	var en_warned := false
	var o2_resetting := false
	var rover_hinted := false
	var daily_dirty := false
	var daily_persist_t := 0.0
	var tracker_t := 0.0
	var current_action := ""

	# missions
	var mres := {}
	var m_group: Node3D
	var m_items: Array = []
	var m_targets: Array = []
	var m_labels: Array = []
	var trophies := {}
	var heli_anim = null
	var drill_anim = null
	var asm = null
	var gh_centers: Array = []

	func _ready() -> void:
		_build_environment()
		_build_terrain()
		_build_hub()
		_build_outside()
		_build_greenhouses()
		_build_garage()
		rover = Rover.new()
		add_child(rover)
		rover.heading = -PI / 2.0
		avatar = Avatar.new()
		add_child(avatar)
		avatar.build(main.save["cfg"])
		m_group = Node3D.new()
		add_child(m_group)
		spawn_collectibles()
		_resolve_missions()
		for k in [1, 3, 5, 7]:
			gh_centers.append(Vector2(cos(k * PI / 4.0) * 24.0, sin(k * PI / 4.0) * 24.0))
		apply_trophies()
		build_step_objects()
		p_pos.y = ground_at(p_pos.x, p_pos.z)

	func activate(on: bool) -> void:
		visible = on
		world_env.environment = env_res if on else null
		process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		cam.current = on

	# ------------------------------------------------------------------ world
	func _build_environment() -> void:
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color("9a5a3e")
		psm.sky_horizon_color = Color("d9a27c")
		psm.ground_horizon_color = Color("d9a27c")
		psm.ground_bottom_color = Color("7a4a32")
		psm.sun_angle_max = 15.0
		sky.sky_material = psm
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.6
		env.fog_enabled = true
		env.fog_light_color = Color("d9a27c")
		env.fog_density = 0.0035
		env.fog_sky_affect = 0.2
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		world_env = WorldEnvironment.new()
		world_env.environment = env
		env_res = env
		add_child(world_env)
		var sun := DirectionalLight3D.new()
		sun.light_color = Color("fff0dd")
		sun.light_energy = 1.25
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 110.0
		add_child(sun)
		sun.look_at_from_position(Vector3(45, 55, -70), Vector3.ZERO, Vector3.UP)
		cam = Camera3D.new()
		cam.fov = 60
		cam.near = 0.1
		cam.far = 2500
		add_child(cam)

	func terrain_h(x: float, z: float) -> float:
		var d := sqrt(x * x + z * z)
		var h := 2.2 * sin(x * 0.045 + 0.5) * cos(z * 0.038) + 4.5 * sin(x * 0.013 + 1.7) * cos(z * 0.017 + 0.4) + 1.1 * sin(x * 0.11) * sin(z * 0.09) + 0.5 * sin(x * 0.31 + z * 0.23)
		h = (h + 3.0) * smoothstep(58.0, 120.0, d)
		var mx := x - 60.0
		var mz := z + 330.0
		h += 150.0 * exp(-(mx * mx + mz * mz) / (2.0 * 95.0 * 95.0)) * smoothstep(80.0, 180.0, d)
		h += smoothstep(360.0, 460.0, d) * 55.0
		return h

	func ground_at(x: float, z: float) -> float:
		var d := sqrt(x * x + z * z)
		if d < HUB_R:
			return 0.3
		if x > 36.0 and x < 52.0 and abs(z) < 7.0:
			return max(0.2, terrain_h(x, z))
		return terrain_h(x, z)

	func _build_terrain() -> void:
		var size := 1000.0
		var seg := 160
		var noise := FastNoiseLite.new()
		noise.frequency = 0.02
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in seg + 1:
			for i in seg + 1:
				var x := -size / 2.0 + size * i / seg
				var z := -size / 2.0 + size * j / seg
				var h := terrain_h(x, z)
				var n := noise.get_noise_2d(x, z)
				var c := Color(0.70 + 0.07 * n, 0.37 + 0.05 * n, 0.21 + 0.03 * n)
				c = c * (0.9 + 0.1 * clamp(h / 12.0, -1.0, 1.0))
				c.a = 1.0
				st.set_color(c)
				st.add_vertex(Vector3(x, h, z))
		for j in seg:
			for i in seg:
				var a := j * (seg + 1) + i
				var b := a + 1
				var c2 := a + seg + 1
				var d2 := c2 + 1
				st.add_index(a)
				st.add_index(b)
				st.add_index(c2)
				st.add_index(b)
				st.add_index(d2)
				st.add_index(c2)
		st.generate_normals()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		Mk.mi(self, st.commit(), m)
		# rocks
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var rock := SphereMesh.new()
		rock.radius = 0.5
		rock.height = 1.0
		rock.radial_segments = 7
		rock.rings = 3
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock
		mm.instance_count = 320
		for i in 320:
			var x := 0.0
			var z := 0.0
			while true:
				x = rng.randf_range(-320, 320)
				z = rng.randf_range(-320, 320)
				if sqrt(x * x + z * z) >= 26.0 and not (x > 32 and x < 56 and abs(z) < 11):
					break
			var sc := 0.25 + pow(rng.randf(), 3.0) * 2.2
			var basis := Basis.from_euler(Vector3(rng.randf() * 3.0, rng.randf() * 3.0, rng.randf() * 3.0)).scaled(Vector3(sc * (0.8 + rng.randf() * 0.6), sc * 0.6, sc * (0.8 + rng.randf() * 0.6)))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(x, terrain_h(x, z) + sc * 0.1, z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mk.mat(Color("6e3a24"), 1.0)
		add_child(mmi)
		var mt := Mk.label(self, "Mount Sharp\n5.5 km peak in Gale’s centre", Vector3(60, 175, -330), 64, Color("ffcfa6"), 0.15)
		mt.no_depth_test = false

	func add_label(text: String, pos: Vector3, color := Color.WHITE, size := 64) -> Label3D:
		var l := Mk.label(self, text, pos, size, color, 0.009)
		l.visibility_range_begin = 9.0
		l.visibility_range_end = 95.0
		labels.append(l)
		return l

	# ------------------------------------------------------------------ collision
	func add_c(x: float, z: float, r: float, rover_only := false) -> void:
		obstacles.append({"t": "c", "x": x, "z": z, "r": r, "ro": rover_only})

	func add_s(ax: float, az: float, bx: float, bz: float, r: float) -> void:
		obstacles.append({"t": "s", "ax": ax, "az": az, "bx": bx, "bz": bz, "r": r, "ro": false})

	## Pushes position p (Vector3, x/z used) out of obstacles. Returns true if it hit something.
	func resolve(p: Vector3, r: float, is_rover: bool) -> Array:
		var hit := false
		for o in obstacles:
			if o["ro"] and not is_rover:
				continue
			match o["t"]:
				"c":
					var dx: float = p.x - o["x"]
					var dz: float = p.z - o["z"]
					var d := sqrt(dx * dx + dz * dz)
					var m: float = o["r"] + r
					if d < m and d > 0.0001:
						p.x = o["x"] + dx / d * m
						p.z = o["z"] + dz / d * m
						hit = true
				"s":
					var abx: float = o["bx"] - o["ax"]
					var abz: float = o["bz"] - o["az"]
					var t: float = clamp(((p.x - o["ax"]) * abx + (p.z - o["az"]) * abz) / (abx * abx + abz * abz), 0.0, 1.0)
					var cx: float = o["ax"] + abx * t
					var cz: float = o["az"] + abz * t
					var dx2 := p.x - cx
					var dz2 := p.z - cz
					var d2 := sqrt(dx2 * dx2 + dz2 * dz2)
					var m2: float = o["r"] + r
					if d2 < m2 and d2 > 0.0001:
						p.x = cx + dx2 / d2 * m2
						p.z = cz + dz2 / d2 * m2
						hit = true
				"ring":
					var d3 := sqrt(p.x * p.x + p.z * p.z)
					if abs(d3 - HUB_R) < r + 0.15 and d3 > 0.0001:
						var a := atan2(p.z, p.x)
						if abs(wrapf(a, -PI, PI)) > DOOR_HALF * 0.82:
							var nd := HUB_R - r - 0.15 if d3 < HUB_R else HUB_R + r + 0.15
							p.x = p.x / d3 * nd
							p.z = p.z / d3 * nd
							hit = true
		var dd := sqrt(p.x * p.x + p.z * p.z)
		if dd > 440.0:
			p.x *= 440.0 / dd
			p.z *= 440.0 / dd
		return [p, hit]

	func free_spot(x: float, z: float, r: float) -> bool:
		if sqrt(x * x + z * z) < 14.0:
			return false
		if x > 32 and x < 56 and abs(z) < 11:
			return false
		return not resolve(Vector3(x, 0, z), r, true)[1]

	func spot(deg: float, r: float) -> Vector2:
		for k in 48:
			var sgn := 1.0 if k % 2 == 1 else -1.0
			var a := deg_to_rad(deg + sgn * ceilf(k / 2.0) * 6.0)
			var rr := r + floorf(k / 4.0) * 2.0
			var x := cos(a) * rr
			var z := sin(a) * rr
			if free_spot(x, z, 2.6):
				return Vector2(x, z)
		return Vector2(cos(deg_to_rad(deg)) * r, sin(deg_to_rad(deg)) * r)

	func cluster(deg: float, r: float, n: int, spread: float) -> Array:
		var c := spot(deg, r)
		var out: Array = []
		var rng := RandomNumberGenerator.new()
		rng.seed = int(deg * 31 + r * 7)
		for i in n:
			var p := c
			for k in 40:
				var a := rng.randf() * TAU
				var d := spread * (0.45 + rng.randf() * 0.55)
				var q := c + Vector2(cos(a), sin(a)) * d
				var ok := free_spot(q.x, q.y, 1.3)
				for o in out:
					if o.distance_to(q) < 2.5:
						ok = false
				if ok:
					p = q
					break
			out.append(p)
		return out

	# ------------------------------------------------------------------ buildings
	func _build_hub() -> void:
		var white := Mk.mat(Color("ece7e0"), 0.55, 0.1)
		var orange := Mk.mat(Color("e0632c"), 0.5, 0.1)
		var grey := Mk.mat(Color("9aa0a8"), 0.5, 0.35)
		var dark := Mk.mat(Color("2c3038"), 0.6, 0.3)
		Mk.cyl(self, HUB_R + 0.3, HUB_R + 0.5, 0.3, Mk.mat(Color("7b7f86"), 0.8, 0.2), Vector3(0, 0.15, 0), 48)
		var segs := 56
		var seg_w := TAU * HUB_R / segs + 0.06
		for i in segs:
			var a := TAU * (i + 0.5) / segs
			if abs(wrapf(a, -PI, PI)) < DOOR_HALF + PI / segs:
				continue
			var w := Mk.box(self, Vector3(seg_w, 2.6, 0.25), white, Vector3(cos(a) * HUB_R, 1.6, sin(a) * HUB_R))
			w.rotation.y = PI / 2.0 - a
			var s := Mk.box(self, Vector3(seg_w, 0.25, 0.27), orange, Vector3(cos(a) * (HUB_R + 0.02), 2.2, sin(a) * (HUB_R + 0.02)))
			s.rotation.y = PI / 2.0 - a
		Mk.sphere(self, HUB_R, Mk.glass(), Vector3(0, 2.9, 0), 48, true)
		for i in 6:
			var rib := Mk.torus(self, HUB_R, 0.07, white, Vector3(0, 2.9, 0))
			rib.rotation = Vector3(PI / 2.0, i * PI / 6.0, 0)
			rib.rotation_order = EULER_ORDER_YXZ
		Mk.torus(self, HUB_R, 0.12, white, Vector3(0, 2.9, 0))
		var dz := sin(DOOR_HALF) * HUB_R
		var dx := cos(DOOR_HALF) * HUB_R
		Mk.box(self, Vector3(0.5, 2.9, 0.3), orange, Vector3(dx, 1.45, dz))
		Mk.box(self, Vector3(0.5, 2.9, 0.3), orange, Vector3(dx, 1.45, -dz))
		Mk.box(self, Vector3(0.5, 0.35, dz * 2 + 0.3), orange, Vector3(dx, 2.75, 0))
		obstacles.append({"t": "ring", "ro": false})
		add_c(dx, dz, 0.25)
		add_c(dx, -dz, 0.25)
		add_c(0, 0, HUB_R + 0.6, true)
		# bed
		var bed := Node3D.new()
		bed.position = Vector3(-4.6, 0.3, 4.2)
		bed.rotation.y = 0.5
		add_child(bed)
		Mk.box(bed, Vector3(2.4, 0.45, 1.4), grey, Vector3(0, 0.25, 0))
		Mk.box(bed, Vector3(2.3, 0.22, 1.32), Mk.mat(Color("f4f1ea"), 0.9), Vector3(0, 0.58, 0))
		Mk.box(bed, Vector3(1.5, 0.08, 1.34), Mk.mat(Color("3e6d8e"), 0.9), Vector3(0.4, 0.71, 0))
		Mk.box(bed, Vector3(0.5, 0.16, 0.9), Mk.mat(Color.WHITE, 0.9), Vector3(-0.85, 0.76, 0))
		Mk.box(bed, Vector3(0.15, 1.0, 1.4), grey, Vector3(-1.25, 0.6, 0))
		add_c(-4.6, 4.2, 1.35)
		# sofa
		var sofa := Node3D.new()
		sofa.position = Vector3(-5.6, 0.3, -1.6)
		sofa.rotation.y = PI / 2.0
		add_child(sofa)
		var sm := Mk.mat(Color("c4532a"), 0.9)
		Mk.box(sofa, Vector3(2.4, 0.45, 0.9), sm, Vector3(0, 0.28, 0))
		Mk.box(sofa, Vector3(2.4, 0.7, 0.25), sm, Vector3(0, 0.6, -0.35))
		Mk.box(sofa, Vector3(0.25, 0.6, 0.9), sm, Vector3(-1.2, 0.45, 0))
		Mk.box(sofa, Vector3(0.25, 0.6, 0.9), sm, Vector3(1.2, 0.45, 0))
		add_c(-5.6, -1.6, 1.25)
		Mk.cyl(self, 1.7, 1.7, 0.03, Mk.mat(Color("6b4a8a"), 1.0), Vector3(-3.4, 0.32, 0.8), 32)
		Mk.cyl(self, 0.55, 0.55, 0.08, Mk.mat(Color("8a5a3a"), 0.8), Vector3(-3.6, 0.75, -1.4), 24)
		Mk.cyl(self, 0.07, 0.07, 0.4, dark, Vector3(-3.6, 0.52, -1.4), 8)
		add_c(-3.6, -1.4, 0.6)
		Mk.cyl(self, 0.04, 0.04, 1.6, dark, Vector3(-6.6, 1.1, 2), 8)
		Mk.sphere(self, 0.22, Mk.unshaded(Color("fff0c0")), Vector3(-6.6, 1.95, 2), 12)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(-6.6, 2.0, 2)
		lamp.light_color = Color("fff0c0")
		lamp.omni_range = 7.0
		lamp.light_energy = 0.8
		add_child(lamp)
		add_label("Living room\nBed & sleep quarters", Vector3(-4.6, 3.1, 3.2), Color("9ac8ff"))
		# food
		var food := Node3D.new()
		food.position = Vector3(1.5, 0.3, -6.4)
		add_child(food)
		Mk.box(food, Vector3(4.2, 2.2, 0.9), grey, Vector3(0, 1.1, 0))
		var fc := ["e0632c", "3e9a45", "f2c14e", "2f6fb5", "c23b2a", "ece7e0"]
		for r in 3:
			for c in 6:
				Mk.box(food, Vector3(0.55, 0.5, 0.55), Mk.mat(Color(fc[(r * 2 + c) % 6]), 0.7), Vector3(-1.6 + c * 0.64, 0.35 + r * 0.68, 0.25))
		add_s(-0.6, -6.4, 3.6, -6.4, 0.6)
		add_label("Food supply\nFreeze-dried meals", Vector3(1.5, 3.3, -6.4), Color("f2c14e"))
		# console
		var cons := Node3D.new()
		cons.position = Vector3(4.5, 0.3, 3.8)
		cons.rotation.y = -2.3
		add_child(cons)
		Mk.box(cons, Vector3(2.6, 0.9, 0.8), dark, Vector3(0, 0.45, 0))
		Mk.box(cons, Vector3(2.4, 0.05, 0.6), Mk.unshaded(Color("5fd3c4")), Vector3(0, 0.93, 0.05))
		Mk.box(cons, Vector3(2.6, 1.0, 0.08), dark, Vector3(0, 1.6, -0.35))
		Mk.box(cons, Vector3(2.3, 0.8, 0.02), Mk.emissive(Color("1a8f84"), 1.2), Vector3(0, 1.6, -0.3))
		add_c(4.5, 3.8, 1.3)
		add_label("Mission Control", Vector3(4.5, 3.0, 3.8), Color("5fd3c4"))
		Mk.cyl(self, 0.7, 0.7, 0.06, white, Vector3(3.2, 1.1, -2.2), 24)
		Mk.cyl(self, 0.08, 0.12, 0.8, grey, Vector3(3.2, 0.7, -2.2), 8)
		add_c(3.2, -2.2, 0.75)
		var title := Mk.label(self, "Base Ares-1\nGale Crater, Mars", Vector3(0, 13.5, 0), 80, Color("ff9a6b"), 0.02)
		title.visibility_range_end = 160.0

	func _build_outside() -> void:
		var white := Mk.mat(Color("ece7e0"), 0.55, 0.1)
		var grey := Mk.mat(Color("9aa0a8"), 0.5, 0.35)
		for pz in [[-11.2, -2.4], [-11.8, -0.8], [-11.8, 0.8], [-11.2, 2.4]]:
			var g := Node3D.new()
			g.position = Vector3(pz[0], 0, pz[1])
			add_child(g)
			Mk.cyl(g, 0.55, 0.55, 2.6, white, Vector3(0, 1.5, 0), 20)
			Mk.sphere(g, 0.55, white, Vector3(0, 2.8, 0), 20, true)
			Mk.cyl(g, 0.56, 0.56, 0.35, Mk.mat(Color("2f6fb5"), 0.5), Vector3(0, 2.0, 0), 20)
			Mk.box(g, Vector3(1.3, 0.2, 1.3), grey, Vector3(0, 0.1, 0))
			add_c(pz[0], pz[1], 0.65)
		add_label("Oxygen tanks\nO₂ refill station", Vector3(-11.6, 4.6, 0), Color("7fb8ff"))
		var solar := Mk.mat(Color("1b2b5a"), 0.25, 0.6)
		for i in 3:
			for j in 4:
				var x := -40.0 - i * 5.0
				var z := -9.0 + j * 6.0
				Mk.cyl(self, 0.08, 0.08, 1.4, grey, Vector3(x, 0.7, z), 6)
				var p := Mk.box(self, Vector3(3.6, 0.08, 2.2), solar, Vector3(x, 1.45, z))
				p.rotation.z = -0.45
				add_c(x, z, 1.4)
		add_label("Solar array", Vector3(-45, 5, 0), Color("9ab0ff"))
		Mk.cyl(self, 0.3, 0.5, 4.0, grey, Vector3(2, 2, -44), 10)
		var bowl := Mk.sphere(self, 2.6, Mk.mat(Color("f0ece6"), 0.5, 0.2), Vector3(2, 4.8, -44), 24, true)
		bowl.rotation.x = PI + 0.7
		bowl.scale = Vector3(1, 0.45, 1)
		add_c(2, -44, 0.8)
		add_label("Earth comms dish", Vector3(2, 9.5, -44), Color("cfd6e0"))
		Mk.cyl(self, 7.0, 7.3, 0.16, Mk.mat(Color("5a5c62"), 0.9), Vector3(0, 0.08, 46), 40)
		var h := Mk.label(self, "H", Vector3(0, 0.2, 46), 300, Color("f2c14e"), 0.025, false)
		h.rotation.x = -PI / 2.0
		add_label("Landing pad", Vector3(0, 4, 46), Color("f2c14e"))

	func _build_greenhouses() -> void:
		var white := Mk.mat(Color("ece7e0"), 0.55, 0.1)
		var grey := Mk.mat(Color("9aa0a8"), 0.5, 0.35)
		var leaf_m := MultiMesh.new()
		leaf_m.transform_format = MultiMesh.TRANSFORM_3D
		var fruit_m := MultiMesh.new()
		fruit_m.transform_format = MultiMesh.TRANSFORM_3D
		var leaves: Array = []
		var fruits: Array = []
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var L := 12.0
		var R := 4.0
		var D0 := HUB_R - 0.3
		var DC := 24.0
		var names := ["Potatoes", "Lettuce & herbs", "Tomatoes", "Soybeans"]
		var idx := 0
		for k in [1, 3, 5, 7]:
			var a := float(k) * PI / 4.0
			var dir := Vector2(cos(a), sin(a))
			var g := Node3D.new()
			g.position = Vector3(dir.x * DC, 0, dir.y * DC)
			g.rotation.y = PI / 2.0 - a
			add_child(g)
			Mk.mi(g, Mk.half_cyl_mesh(R, L), Mk.glass())
			for s in 7:
				var t := Mk.torus(g, R, 0.07, white, Vector3(0, 0, -L / 2.0 + s * L / 6.0))
				t.rotation.x = PI / 2.0
			Mk.box(g, Vector3(R * 2 + 0.3, 0.3, L + 0.3), Mk.mat(Color("7b7f86"), 0.8), Vector3(0, 0.15, 0))
			var glow := Mk.unshaded(Color("ff70d0"))
			for px in [0.0, 1.6, -1.6]:
				Mk.box(g, Vector3(0.08, 0.08, L - 0.6), glow, Vector3(px, 3.2 if px == 0.0 else 2.6, 0))
			for px in [-2.1, 0.0, 2.1]:
				Mk.box(g, Vector3(1.1, 0.45, L - 1.4), Mk.mat(Color("4a2c1c"), 1.0), Vector3(px, 0.52, 0))
				for j in 9:
					var pz := -L / 2.0 + 1.3 + j * 1.17
					var sc := 0.35 + rng.randf() * 0.25
					var local := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * 3.0, 0)).scaled(Vector3(sc, sc * 1.6, sc)), Vector3(px, 0.75 + sc * 0.9, pz))
					leaves.append(g.transform * local)
					if rng.randf() < 0.55:
						fruits.append(g.transform * Transform3D(Basis().scaled(Vector3.ONE * 0.12), Vector3(px + rng.randf_range(-0.2, 0.2), 0.9 + sc * 1.2, pz + rng.randf_range(-0.2, 0.2))))
			add_label("Greenhouse %d\n%s" % [idx + 1, names[idx]], Vector3(dir.x * DC, 6, dir.y * DC), Color("7ddc84"))
			var tg := Node3D.new()
			tg.rotation.y = PI / 2.0 - a
			add_child(tg)
			var length := DC - L / 2.0 - D0
			var tun := Mk.cyl(tg, 1.3, 1.3, length, white, Vector3(0, 1.3, D0 + length / 2.0), 20)
			tun.rotation.x = PI / 2.0
			for r in 4:
				var rib := Mk.torus(tg, 1.34, 0.08, grey, Vector3(0, 1.3, D0 + 0.5 + r * (length - 1.0) / 3.0))
				rib.rotation.x = PI / 2.0
			add_s(dir.x * (DC - L / 2.0), dir.y * (DC - L / 2.0), dir.x * (DC + L / 2.0), dir.y * (DC + L / 2.0), R)
			add_s(dir.x * D0, dir.y * D0, dir.x * (DC - L / 2.0), dir.y * (DC - L / 2.0), 1.3)
			idx += 1
		var leaf := SphereMesh.new()
		leaf.radius = 1.0
		leaf.height = 2.0
		leaf.radial_segments = 6
		leaf.rings = 3
		leaf_m.mesh = leaf
		leaf_m.instance_count = leaves.size()
		for i in leaves.size():
			leaf_m.set_instance_transform(i, leaves[i])
		var fruit := SphereMesh.new()
		fruit.radius = 1.0
		fruit.height = 2.0
		fruit.radial_segments = 8
		fruit.rings = 4
		fruit_m.mesh = fruit
		fruit_m.instance_count = fruits.size()
		for i in fruits.size():
			fruit_m.set_instance_transform(i, fruits[i])
		var li := MultiMeshInstance3D.new()
		li.multimesh = leaf_m
		li.material_override = Mk.mat(Color("3faa4c"), 0.8)
		add_child(li)
		var fi := MultiMeshInstance3D.new()
		fi.multimesh = fruit_m
		fi.material_override = Mk.mat(Color("e0402a"), 0.6)
		add_child(fi)

	func _build_garage() -> void:
		var white := Mk.mat(Color("ece7e0"), 0.55, 0.1)
		var grey := Mk.mat(Color("9aa0a8"), 0.5, 0.35)
		var dark := Mk.mat(Color("2c3038"), 0.6, 0.3)
		var g := Node3D.new()
		g.position = Vector3(44, 0, 0)
		add_child(g)
		Mk.box(g, Vector3(16, 0.2, 14), Mk.mat(Color("7b7f86"), 0.8), Vector3(0, 0.1, 0))
		Mk.box(g, Vector3(0.4, 6, 14), white, Vector3(8, 3, 0))
		Mk.box(g, Vector3(16, 6, 0.4), white, Vector3(0, 3, 7))
		Mk.box(g, Vector3(16, 6, 0.4), white, Vector3(0, 3, -7))
		Mk.box(g, Vector3(16.6, 0.4, 14.6), grey, Vector3(0, 6.1, 0))
		for k in 8:
			Mk.box(g, Vector3(0.42, 0.6, 1.8), dark if k % 2 == 1 else Mk.mat(Color("f2c14e"), 0.6), Vector3(-8, 5.6, -6.3 + k * 1.8))
		Mk.box(g, Vector3(1.2, 2.4, 3.5), grey, Vector3(6.8, 1.3, -4.5))
		Mk.box(g, Vector3(0.8, 1.6, 0.8), dark, Vector3(6.6, 1, 4.5))
		var cols := ["e0632c", "2f6fb5", "3e9a45", "f2c14e"]
		for k in 4:
			Mk.box(g, Vector3(1.1, 0.4, 0.6), Mk.mat(Color(cols[k]), 0.7), Vector3(6.8, 0.9 + k * 0.55, -4.5 + ((k % 2) - 0.5) * 0.9))
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, 5.4, 0)
		lamp.omni_range = 22.0
		lamp.light_energy = 1.0
		g.add_child(lamp)
		add_s(52, -7, 52, 7, 0.3)
		add_s(36, 7, 52, 7, 0.3)
		add_s(36, -7, 52, -7, 0.3)
		add_label("Rover garage", Vector3(44, 8.4, 0), Color("ff9a6b"), 80)
		add_label("Workbench", Vector3(50.5, 3.4, -4.5), Color("cfd6e0"), 48)

	# ------------------------------------------------------------------ collectibles
	func spawn_collectibles() -> void:
		for o in gems + prizes:
			o["node"].queue_free()
		gems.clear()
		prizes.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + int(main.save["seed"]) * 17
		var gem_cols := [Color("ff3b5c"), Color("34e08a"), Color("3aa0ff"), Color("b36bff"), Color("ffd23a")]
		var gem_mesh := Mk.octa_mesh(0.42)
		for i in 30:
			var x := 0.0
			var z := 0.0
			for t in 50:
				var a := rng.randf() * TAU
				var d := 14.0 + pow(rng.randf(), 0.8) * 130.0
				x = cos(a) * d
				z = sin(a) * d
				if free_spot(x, z, 1.2):
					break
			var c: Color = gem_cols[i % 5]
			var g := Node3D.new()
			g.position = Vector3(x, terrain_h(x, z) + 1.0, z)
			add_child(g)
			var m := Mk.mi(g, gem_mesh, Mk.emissive(c, 0.8))
			var ol := OmniLight3D.new()
			ol.light_color = c
			ol.omni_range = 3.0
			ol.light_energy = 0.6
			g.add_child(ol)
			gems.append({"node": g, "base": g.position.y, "taken": false, "col": c, "ph": rng.randf() * TAU})
		for i in 12:
			var x := 0.0
			var z := 0.0
			for t in 50:
				var a := rng.randf() * TAU
				var d := 70.0 + rng.randf() * 220.0
				x = cos(a) * d
				z = sin(a) * d
				if free_spot(x, z, 2.0):
					break
			var g := Node3D.new()
			g.position = Vector3(x, terrain_h(x, z), z)
			add_child(g)
			var b := Mk.box(g, Vector3(1.4, 1.4, 1.4), Mk.emissive(Color("e0a52a"), 0.5), Vector3(0, 1.2, 0))
			Mk.box(b, Vector3(1.45, 0.25, 1.45), Mk.mat(Color("7a4a10"), 0.6))
			Mk.cyl(g, 0.35, 0.35, 40.0, Mk.unshaded(Color("ffd24a"), 0.22, true), Vector3(0, 20, 0), 10)
			prizes.append({"node": g, "box": b, "taken": false, "ph": rng.randf() * TAU})
		main.ui.set_totals(gems.size(), prizes.size())

	func respawn_treasure() -> void:
		main.save["seed"] = int(main.save["seed"]) + 1
		main.persist()
		spawn_collectibles()
		gems_got = 0
		prizes_got = 0
		main.ui.update_hud()
		main.toast("New gems and prize crates have landed around the base")

	# ------------------------------------------------------------------ main loop
	func _get_input() -> Vector2:
		var v: Vector2 = main.ui.joy_vector
		v.y += Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		v.x += Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		return Vector2(clamp(v.x, -1.0, 1.0), clamp(v.y, -1.0, 1.0))

	func _process(dt: float) -> void:
		dt = min(dt, 0.05)
		var t := Time.get_ticks_msec() / 1000.0
		for g in gems:
			if not g["taken"]:
				g["node"].rotation.y += dt * 1.6
				g["node"].position.y = g["base"] + sin(t * 2.0 + g["ph"]) * 0.25
		for p in prizes:
			if not p["taken"]:
				p["box"].rotation.y += dt * 0.8
				p["box"].position.y = 1.2 + sin(t * 1.6 + p["ph"]) * 0.15
		_update_anims(dt)
		if customizing:
			cam_yaw += dt * 0.3
			avatar.position = p_pos
			avatar.rotation.y = p_heading
			avatar.pose(dt, false, true, walk_t, false)
			var ty := p_pos.y + 1.0
			cam.position = Vector3(p_pos.x + sin(cam_yaw) * 5.4 * cos(0.15), ty + sin(0.15) * 5.4, p_pos.z + cos(cam_yaw) * 5.4 * cos(0.15))
			cam.look_at(Vector3(p_pos.x, ty, p_pos.z), Vector3.UP)
			return
		var paused: bool = main.ui.modal_open()
		var inp := Vector2.ZERO if paused else _get_input()
		if paused:
			jump_queued = false
		elif Input.is_action_just_pressed("jump"):
			jump_queued = true
		if not paused and Input.is_action_just_pressed("interact"):
			do_action()
		if not paused and Input.is_action_just_pressed("missions"):
			main.ui.open_mc("")
		var moving := false
		if not in_rover:
			var fx := -sin(cam_yaw)
			var fz := -cos(cam_yaw)
			var mx := fx * inp.y - fz * inp.x
			var mz := fz * inp.y + fx * inp.x
			var mag := sqrt(mx * mx + mz * mz)
			if mag > 0.08:
				moving = true
				var sp := (7.5 if Input.is_action_pressed("sprint") else 4.4) * minf(1.0, mag) * (0.55 if energy < 15.0 else 1.0)
				mx /= mag
				mz /= mag
				p_pos.x += mx * sp * dt
				p_pos.z += mz * sp * dt
				p_heading = lerp_angle(p_heading, atan2(mx, mz), 1.0 - exp(-dt * 12.0))
				walk_t += dt * sp * 2.1
				daily_progress("walk", sp * dt)
			p_pos = resolve(p_pos, 0.45, false)[0]
			var gy := ground_at(p_pos.x, p_pos.z)
			if jump_queued and p_ground and not busy:
				p_vy = 4.4
				p_ground = false
				daily_progress("jump", 1)
				energy = max(0.0, energy - 0.6)
			p_vy -= GRAVITY * dt
			p_pos.y += p_vy * dt
			if p_pos.y <= gy:
				p_pos.y = gy
				p_vy = 0.0
				p_ground = true
			elif p_ground and p_pos.y - gy < 0.45:
				p_pos.y = gy
				p_vy = 0.0
			elif p_pos.y - gy >= 0.45:
				p_ground = false
			avatar.position = p_pos
			avatar.rotation.y = p_heading
			for s in rover.steers:
				s.rotation.y = 0.0
		else:
			var thr := inp.y
			rover.speed += thr * 13.0 * dt
			rover.speed *= exp(-dt * (0.35 if abs(thr) > 0.05 else 1.4))
			rover.speed = clamp(rover.speed, -6.0, 18.0)
			rover.heading -= inp.x * 1.7 * dt * clamp(rover.speed / 5.0, -1.0, 1.0)
			r_pos.x += sin(rover.heading) * rover.speed * dt
			r_pos.z += cos(rover.heading) * rover.speed * dt
			daily_progress("drive", abs(rover.speed) * dt)
			var res := resolve(r_pos, 2.1, true)
			r_pos = res[0]
			if res[1]:
				rover.speed *= 0.6
			for s in rover.steers:
				s.rotation.y = -inp.x * 0.42
			moving = abs(rover.speed) > 0.5
		jump_queued = false
		_place_rover(dt)
		avatar.pose(dt, moving, p_ground, walk_t, in_rover)
		if not paused:
			var in_hub := not in_rover and Vector2(p_pos.x, p_pos.z).length() < HUB_R
			if in_rover:
				o2 = min(100.0, o2 + dt * 3.0)
			elif in_hub:
				o2 = min(100.0, o2 + dt * 25.0)
			else:
				o2 = max(0.0, o2 - dt * 0.5)
			if o2 > 40.0:
				o2_warned = false
			if o2 < 25.0 and not o2_warned:
				o2_warned = true
				main.toast("Oxygen low! Head back to the base, the O₂ tanks, or the rover.")
			if o2 <= 0.0 and not o2_resetting:
				o2_resetting = true
				main.fade(_o2_reset_done)
			_update_energy(dt, moving)
			update_missions(dt)
			_daily_location_checks()
			_check_collect(t)
		else:
			update_missions(0.0)
		var a = compute_action()
		var aid: String = a["id"] if a else ""
		if aid != current_action:
			current_action = aid
			main.ui.set_action(a["label"] if a else "")
		if t - tracker_t > 0.2:
			tracker_t = t
			main.ui.update_tracker()
			main.ui.update_bars(o2, energy)
			main.ui.minimap.queue_redraw()
		if daily_dirty and t - daily_persist_t > 3.0:
			daily_persist_t = t
			daily_dirty = false
			main.persist()
		_update_camera(dt, t)

	func _place_rover(dt: float) -> void:
		var h: float = rover.heading
		var c := cos(h)
		var s := sin(h)
		var hf := ground_at(r_pos.x + s * 1.6, r_pos.z + c * 1.6)
		var hb := ground_at(r_pos.x - s * 1.6, r_pos.z - c * 1.6)
		var hl := ground_at(r_pos.x + c * 1.2, r_pos.z - s * 1.2)
		var hr := ground_at(r_pos.x - c * 1.2, r_pos.z + s * 1.2)
		r_pos.y = max(ground_at(r_pos.x, r_pos.z), (hf + hb + hl + hr) / 4.0)
		var k := 1.0 - exp(-dt * 8.0)
		rover.pitch = lerp(rover.pitch, atan2(hb - hf, 3.2), k)
		rover.roll = lerp(rover.roll, atan2(hl - hr, 2.4), k)
		rover.position = r_pos
		rover.rotation_order = EULER_ORDER_YXZ
		rover.rotation = Vector3(rover.pitch, h, rover.roll)
		for w in rover.wheels:
			w.rotation.x += rover.speed * dt / 0.48

	func _update_camera(dt: float, t: float) -> void:
		var tgt: Vector3 = r_pos if in_rover else p_pos
		if in_rover and t - last_drag > 1.2:
			cam_yaw = lerp_angle(cam_yaw, rover.heading + PI, 1.0 - exp(-dt * 2.2))
		cam_dist = lerp(cam_dist, cam_dist_t, 1.0 - exp(-dt * 5.0))
		var ty := tgt.y + (2.2 if in_rover else 1.5)
		var cp := Vector3(tgt.x + sin(cam_yaw) * cos(cam_pitch) * cam_dist, ty + sin(cam_pitch) * cam_dist, tgt.z + cos(cam_yaw) * cos(cam_pitch) * cam_dist)
		cp.y = max(cp.y, terrain_h(cp.x, cp.z) + 0.7)
		if tgt.x > 36.0 and tgt.x < 52.0 and abs(tgt.z) < 7.0:
			cp.x = clampf(cp.x, 30.0, 51.3)
			cp.z = clampf(cp.z, -6.5, 6.5)
			cp.y = minf(cp.y, 5.4)
		cam.position = cp
		cam.look_at(Vector3(tgt.x, ty, tgt.z), Vector3.UP)
		for l in m_labels:
			if is_instance_valid(l):
				l.visible = not busy and l.global_position.distance_to(cp) > 7.5

	func _unhandled_input(ev: InputEvent) -> void:
		if customizing or main.ui.modal_open():
			return
		if ev is InputEventScreenDrag:
			if ev.index == main.ui.joy_index:
				return
			cam_yaw -= ev.relative.x * 0.007
			cam_pitch = clamp(cam_pitch + ev.relative.y * 0.005, 0.02, 1.25)
			last_drag = Time.get_ticks_msec() / 1000.0
		elif ev is InputEventMouseMotion and not DisplayServer.is_touchscreen_available():
			if ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
				cam_yaw -= ev.relative.x * 0.007
				cam_pitch = clamp(cam_pitch + ev.relative.y * 0.005, 0.02, 1.25)
				last_drag = Time.get_ticks_msec() / 1000.0
		elif ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				cam_dist_t = clamp(cam_dist_t * 0.9, 3.0, 24.0)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cam_dist_t = clamp(cam_dist_t * 1.1, 3.0, 24.0)

	func _check_collect(t: float) -> void:
		var cp: Vector3 = r_pos if in_rover else p_pos
		for g in gems:
			if g["taken"]:
				continue
			var gp: Vector3 = g["node"].position
			var r := 3.0 if in_rover else 1.5
			if Vector2(gp.x - cp.x, gp.z - cp.z).length() < r and abs(gp.y - (cp.y + 1.0)) < 2.6:
				g["taken"] = true
				g["node"].visible = false
				Mk.burst(self, gp, g["col"])
				gems_got += 1
				main.add_gems(1)
				daily_progress("gems", 1)
				main.toast("Gem found! +1 gem")
				_check_win()
		for p in prizes:
			if p["taken"]:
				continue
			var pp: Vector3 = p["node"].position
			var d := Vector2(pp.x - cp.x, pp.z - cp.z).length()
			if in_rover and d < 3.8:
				p["taken"] = true
				p["node"].visible = false
				Mk.burst(self, pp + Vector3(0, 1.2, 0), Color("ffd24a"))
				prizes_got += 1
				main.add_gems(5)
				main.toast("Prize crate loaded into ARES! +5 gems")
				_check_win()
			elif not in_rover and d < 2.8 and t > prize_nag:
				prize_nag = t + 6.0
				main.toast("This crate is too heavy to carry. Bring the rover here to haul it!")

	func _check_win() -> void:
		main.ui.update_hud()
		if gems_got >= gems.size() and prizes_got >= prizes.size():
			main.ui.show_win()

	# ------------------------------------------------------------------ player helpers
	func place_player_at_base() -> void:
		if in_rover:
			exit_rover(true)
		p_pos = Vector3(18, ground_at(18, -1), -1)
		p_vy = 0.0
		p_ground = true
		p_heading = PI / 2.0
		cam_yaw = -PI / 2.0 + 0.6
		cam_pitch = 0.32
		cam_dist = 7.0
		cam_dist_t = 7.0

	func enter_rover() -> void:
		in_rover = true
		avatar.reparent(rover, false)
		avatar.position = Vector3(0, 0.45, 0.15)
		avatar.rotation = Vector3.ZERO
		cam_dist_t = 12.0
		cam_pitch = 0.3
		main.ui.update_hud()
		if not rover_hinted:
			rover_hinted = true
			main.toast("You’re driving ARES. Follow the golden beams to the prize crates!")

	func exit_rover(silent := false) -> void:
		in_rover = false
		avatar.reparent(self, false)
		var h: float = rover.heading
		var p := r_pos + Vector3(cos(h), 0, -sin(h)) * 2.9
		p = resolve(p, 0.45, false)[0]
		p.y = ground_at(p.x, p.z)
		p_pos = p
		p_vy = 0.0
		p_ground = true
		p_heading = h
		rover.speed = 0.0
		cam_dist_t = 7.0
		if not silent:
			main.ui.update_hud()

	func compute_action() -> Variant:
		var st = cur_step()
		if st and st["type"] == "act" and not busy:
			var L := loc_of(st)
			var P: Vector3 = r_pos if in_rover else p_pos
			var need: bool = st.get("need_rover", false)
			if Vector2(P.x, P.z).distance_to(L["p"]) < L["r"] + (1.5 if in_rover else 0.0) and (not need or in_rover):
				return {"id": "mact", "label": st["label"]}
		if in_rover:
			return {"id": "exit", "label": "Exit rover"}
		var p := Vector2(p_pos.x, p_pos.z)
		if p.distance_to(Vector2(r_pos.x, r_pos.z)) < 4.2:
			return {"id": "enter", "label": "Drive the rover"}
		if p.distance_to(Vector2(4.5, 3.8)) < 2.9:
			return {"id": "mc", "label": "Open Mission Control"}
		if p.distance_to(Vector2(-4.6, 4.2)) < 2.7:
			return {"id": "sleep", "label": "Sleep (end the sol)"}
		if p.distance_to(Vector2(-5.6, -1.6)) < 2.5:
			return {"id": "rest", "label": "Rest on the sofa"}
		if p.distance_to(Vector2(1.5, -6.4)) < 2.9:
			return {"id": "eat", "label": "Eat a meal"}
		if p.distance_to(Vector2(-11.4, 0)) < 3.4:
			return {"id": "o2", "label": "Refill O₂"}
		return null

	func do_action() -> void:
		if busy or main.ui.modal_open():
			return
		var a = compute_action()
		if a == null:
			return
		match a["id"]:
			"enter":
				enter_rover()
			"exit":
				exit_rover()
			"mact":
				start_mission_anim(cur_step())
			"mc":
				daily_progress("comms", 1)
				main.ui.open_mc("")
			"sleep":
				do_sleep()
			"rest":
				do_rest()
			"eat":
				do_eat()
			"o2":
				o2 = 100.0
				o2_warned = false
				main.toast("Oxygen refilled to 100%")

	func _update_energy(dt: float, moving: bool) -> void:
		var drain := 0.04 if in_rover else (0.22 if moving else 0.05)
		energy = max(0.0, energy - drain * dt)
		if energy < 15.0 and not en_warned:
			en_warned = true
			main.toast("You’re exhausted and moving slowly. Eat a meal or rest on the sofa.")
		if energy > 30.0:
			en_warned = false

	# ------------------------------------------------------------------ daily log
	func new_daily(sol: int) -> Dictionary:
		var ids: Array = D.CHALLENGES.keys()
		var rng := RandomNumberGenerator.new()
		rng.seed = sol * 977 + 3
		var pick: Array = []
		while pick.size() < 2:
			var id: String = ids[rng.randi() % ids.size()]
			if not pick.has(id):
				pick.append(id)
		var ch: Array = []
		for id in pick:
			ch.append({"id": id, "prog": 0.0, "done": false})
		return {"sol": sol, "meals": 0, "rested": false, "ch": ch, "gh": [], "earned": 0}

	func daily_progress(id: String, amt: float) -> void:
		var d: Dictionary = main.save["daily"]
		for c in d["ch"]:
			if c["id"] == id and not c["done"]:
				var C: Dictionary = D.CHALLENGES[id]
				c["prog"] = min(float(C["target"]), float(c["prog"]) + amt)
				if c["prog"] >= C["target"]:
					c["done"] = true
					main.add_gems(int(C["reward"]))
					main.toast("Daily challenge done: %s. +%d gems" % [C["text"], C["reward"]])
				else:
					daily_dirty = true

	func _daily_location_checks() -> void:
		if in_rover:
			return
		var d: Dictionary = main.save["daily"]
		var p := Vector2(p_pos.x, p_pos.z)
		for i in gh_centers.size():
			if not d["gh"].has(i) and p.distance_to(gh_centers[i]) < 8.0:
				d["gh"].append(i)
				daily_progress("greenhouse", 1)
				main.toast("Greenhouse %d checked" % (i + 1))
		if p.distance_to(Vector2(-11.4, 0)) < 3.6:
			daily_progress("o2check", 1)

	func do_eat() -> void:
		var d: Dictionary = main.save["daily"]
		d["meals"] = int(d["meals"]) + 1
		energy = min(100.0, energy + 30.0)
		var meal: String = D.MEALS[randi() % D.MEALS.size()]
		if d["meals"] == 2:
			main.add_gems(D.DAILY_REWARD["meals"])
			main.toast("You ate %s. Daily log: 2 meals done. +%d gems" % [meal, D.DAILY_REWARD["meals"]])
		else:
			main.toast("You ate %s. Energy +30" % meal)
		main.persist()

	func do_rest() -> void:
		busy = true
		main.fade(_rest_done)

	func _rest_done() -> void:
		busy = false
		energy = min(100.0, energy + 40.0)
		var d: Dictionary = main.save["daily"]
		if not d["rested"]:
			d["rested"] = true
			main.add_gems(D.DAILY_REWARD["rest"])
			main.toast("You put your feet up for an hour. Daily log: rest done. +%d gems" % D.DAILY_REWARD["rest"])
		else:
			main.toast("A nice break. Energy +40")
		main.persist()

	func do_sleep() -> void:
		busy = true
		main.fade(_sleep_done)

	func _sleep_done() -> void:
		busy = false
		var d: Dictionary = main.save["daily"]
		main.add_gems(D.DAILY_REWARD["sleep"])
		var all_done: bool = int(d["meals"]) >= 2 and d["rested"]
		for c in d["ch"]:
			if not c["done"]:
				all_done = false
		if all_done:
			main.add_gems(D.DAILY_REWARD["bonus"])
		var prev: Dictionary = d.duplicate(true)
		main.save["sol"] = int(main.save["sol"]) + 1
		main.save["daily"] = new_daily(main.save["sol"])
		o2 = 100.0
		energy = 100.0
		main.persist()
		main.ui.update_hud()
		main.ui.show_sol_summary(prev, all_done)

	func _o2_reset_done() -> void:
		place_player_at_base()
		o2 = 100.0
		o2_resetting = false
		main.toast("Your oxygen ran out, so mission control brought you back inside the base.")

	func apply_fx(fx: Dictionary) -> void:
		if fx.has("o2"):
			o2 = clamp(o2 + fx["o2"], 5.0, 100.0)
		if fx.has("energy"):
			energy = clamp(energy + fx["energy"], 5.0, 100.0)
		if fx.has("gems"):
			main.add_gems(int(fx["gems"]))

	# ------------------------------------------------------------------ missions
	func _resolve_missions() -> void:
		for m in D.MISSIONS:
			var steps: Array = []
			for s in m["steps"]:
				var r: Dictionary = s.duplicate(true)
				if s.has("points"):
					var pts: Array = []
					for pr in s["points"]:
						pts.append(spot(pr[0], pr[1]))
					r["pts"] = pts
				if s.has("cluster"):
					var c: Array = s["cluster"]
					r["ipos"] = cluster(c[0], c[1], s["items"].size(), c[2])
				if s.has("to") and typeof(s["to"]) == TYPE_ARRAY:
					r["to_pos"] = spot(s["to"][0], s["to"][1])
				steps.append(r)
			mres[m["id"]] = steps

	func mission_by_id(id: String) -> Variant:
		for m in D.MISSIONS:
			if m["id"] == id:
				return m
		return null

	func active_mission() -> Variant:
		var a = main.save.get("active")
		if a == null:
			return null
		return mission_by_id(a["id"])

	func cur_step() -> Variant:
		var a = main.save.get("active")
		if a == null or not mres.has(a["id"]):
			return null
		var steps: Array = mres[a["id"]]
		var i := int(a["step"])
		return steps[i] if i < steps.size() else null

	func loc_of(st: Dictionary) -> Dictionary:
		var t = st["to"]
		if typeof(t) == TYPE_STRING:
			var L: Dictionary = D.LOCATIONS[t]
			return {"p": Vector2(L["p"][0], L["p"][1]), "r": L["r"], "label": L["label"]}
		return {"p": st["to_pos"], "r": 4.5, "label": st.get("loc_label", st.get("label", "Target"))}

	func step_text(st) -> String:
		if st == null:
			return ""
		var a = main.save["active"]
		var d: int = a["done"].size() if a else 0
		var rv := " (use the rover)" if st.get("need_rover", false) and not in_rover else ""
		match st["type"]:
			"visit":
				return "%s %d/%d%s" % [st["text"], d, st["pts"].size(), rv]
			"collect":
				return "%s %d/%d" % [st["text"], d, st["items"].size()]
			"assemble":
				return st["title"]
		return st["text"] + rv

	func _marker(p: Vector2, r: float, text: String) -> void:
		var g := Node3D.new()
		g.position = Vector3(p.x, ground_at(p.x, p.y), p.y)
		m_group.add_child(g)
		var teal := Color("5fd3c4")
		Mk.torus(g, r, 0.12, Mk.unshaded(teal, 0.9), Vector3(0, 0.12, 0))
		Mk.cyl(g, 0.3, 0.3, 30.0, Mk.unshaded(teal, 0.3, true), Vector3(0, 15, 0), 10)
		if text != "":
			m_labels.append(Mk.label(g, text, Vector3(0, 3.6, 0), 64, teal, 0.012))

	func _item(it: Array, p: Vector2) -> void:
		var g := Node3D.new()
		g.position = Vector3(p.x, ground_at(p.x, p.y), p.y)
		m_group.add_child(g)
		var c := Color(it[2])
		var m := Mk.emissive(c, 0.3)
		var holder := Node3D.new()
		holder.position.y = 0.7
		g.add_child(holder)
		match it[1]:
			"can":
				Mk.cyl(holder, 0.22, 0.22, 0.5, m)
			"berry":
				Mk.sphere(holder, 0.2, m)
			"wheel":
				var t := Mk.torus(holder, 0.28, 0.1, m)
				t.rotation.x = PI / 2.0
			"panel":
				Mk.box(holder, Vector3(0.9, 0.06, 0.55), m)
			"blade":
				Mk.box(holder, Vector3(1.1, 0.08, 0.18), m)
			"dome":
				Mk.sphere(holder, 0.38, m, Vector3.ZERO, 16, true)
			_:
				Mk.box(holder, Vector3(0.6, 0.45, 0.6), m)
		Mk.cyl(g, 0.12, 0.12, 8.0, Mk.unshaded(Color("5fd3c4"), 0.3, true), Vector3(0, 4, 0), 8)
		m_labels.append(Mk.label(g, it[0], Vector3(0, 1.7, 0), 48, Color("5fd3c4"), 0.01))
		m_items.append({"node": g, "holder": holder, "ph": randf() * TAU})

	func build_step_objects() -> void:
		for c in m_group.get_children():
			c.queue_free()
		m_items.clear()
		m_targets.clear()
		m_labels.clear()
		var st = cur_step()
		if st == null:
			return
		var done: Array = main.save["active"]["done"]
		match st["type"]:
			"visit":
				for i in st["pts"].size():
					if done.has(i):
						continue
					var p: Vector2 = st["pts"][i]
					_marker(p, st.get("r", 3.2), st["verb"])
					m_targets.append(p)
					var y := ground_at(p.x, p.y)
					if st.get("crater", false):
						var rim := Mk.torus(m_group, 2.4, 0.35, Mk.mat(Color("9a5434"), 1.0), Vector3(p.x, y + 0.05, p.y))
						Mk.cyl(m_group, 2.2, 2.2, 0.05, Mk.mat(Color("5a2a16"), 1.0), Vector3(p.x, y + 0.03, p.y), 32)
					if st.get("rock", false):
						var rk := Mk.sphere(m_group, 0.8, Mk.mat(Color("b8a898"), 0.9), Vector3(p.x, y + 0.5, p.y), 7)
						rk.scale = Vector3(1.2, 0.8, 1.0)
			"collect":
				for i in st["items"].size():
					if done.has(i):
						continue
					_item(st["items"][i], st["ipos"][i])
					m_targets.append(st["ipos"][i])
			"deliver", "act":
				var L := loc_of(st)
				_marker(L["p"], min(float(L["r"]), 4.0), st["label"] if st["type"] == "act" else L["label"])
				m_targets.append(L["p"])

	func start_mission(id: String) -> void:
		main.save["active"] = {"id": id, "step": 0, "done": []}
		asm = null
		main.persist()
		build_step_objects()
		main.ui.close_modal()
		main.ui.update_tracker()
		main.toast("%s started. %s." % [mission_by_id(id)["name"], step_text(cur_step())])

	func abandon_mission() -> void:
		main.save["active"] = null
		asm = null
		main.persist()
		build_step_objects()
		main.ui.update_tracker()

	func advance_step() -> void:
		var m = active_mission()
		if m == null:
			return
		var a: Dictionary = main.save["active"]
		a["step"] = int(a["step"]) + 1
		a["done"] = []
		main.persist()
		if a["step"] >= m["steps"].size():
			complete_mission(m)
			return
		build_step_objects()
		main.ui.update_tracker()
		var st = cur_step()
		main.toast("Next: " + step_text(st))
		if st["type"] == "assemble":
			get_tree().create_timer(0.7).timeout.connect(open_assembly)

	func complete_mission(m: Dictionary) -> void:
		var first: bool = not main.save["completed"].has(m["id"])
		if first:
			main.save["completed"].append(m["id"])
		main.save["active"] = null
		main.persist()
		build_step_objects()
		main.ui.update_tracker()
		if first:
			main.add_gems(int(m["reward"]))
		main.ui.show_history(m, int(m["reward"]) if first else 0)

	func update_missions(dt: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0
		for it in m_items:
			if is_instance_valid(it["holder"]):
				it["holder"].rotation.y += dt * 1.2
				it["holder"].position.y = 0.7 + sin(t * 2.0 + it["ph"]) * 0.15
		var st = cur_step()
		if st == null or busy or dt == 0.0:
			return
		var P := Vector2(r_pos.x, r_pos.z) if in_rover else Vector2(p_pos.x, p_pos.z)
		var done: Array = main.save["active"]["done"]
		match st["type"]:
			"visit":
				for i in st["pts"].size():
					if done.has(i):
						continue
					if st.get("need_rover", false) and not in_rover:
						continue
					var p: Vector2 = st["pts"][i]
					if P.distance_to(p) < float(st.get("r", 3.2)) + (1.5 if in_rover else 0.0):
						done.append(i)
						main.persist()
						Mk.burst(self, Vector3(p.x, ground_at(p.x, p.y) + 1.5, p.y), Color("5fd3c4"))
						main.toast("%s: %d/%d done" % [st["verb"], done.size(), st["pts"].size()])
						if done.size() >= st["pts"].size():
							advance_step()
						else:
							build_step_objects()
						return
			"collect":
				var r := 2.8 if in_rover else 1.7
				for i in st["items"].size():
					if done.has(i):
						continue
					var p: Vector2 = st["ipos"][i]
					if P.distance_to(p) < r:
						done.append(i)
						main.persist()
						Mk.burst(self, Vector3(p.x, ground_at(p.x, p.y) + 0.8, p.y), Color("5fd3c4"))
						main.toast("Picked up %s (%d/%d)" % [st["items"][i][0], done.size(), st["items"].size()])
						if done.size() >= st["items"].size():
							advance_step()
						else:
							build_step_objects()
						return
			"deliver":
				var L := loc_of(st)
				if P.distance_to(L["p"]) < L["r"]:
					advance_step()

	func nearest_target_dist() -> float:
		var P := Vector2(r_pos.x, r_pos.z) if in_rover else Vector2(p_pos.x, p_pos.z)
		var best := INF
		for p in m_targets:
			best = min(best, P.distance_to(p))
		return best

	# assembly
	func open_assembly() -> void:
		var st = cur_step()
		if st == null or st["type"] != "assemble":
			return
		if asm == null or asm["st"] != st:
			var sh: Array = range(st["parts"].size())
			var rng := RandomNumberGenerator.new()
			rng.seed = st["parts"].size() * 13 + int(main.save["active"]["step"]) * 7
			for i in range(sh.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var tmp = sh[i]
				sh[i] = sh[j]
				sh[j] = tmp
			var sorted := true
			for i in sh.size():
				if sh[i] != i:
					sorted = false
			if sorted:
				sh.reverse()
			asm = {"st": st, "placed": 0, "order": sh, "msg": "", "ok": true}
		main.ui.show_assembly(asm)

	func asm_pick(idx: int) -> void:
		if asm == null:
			return
		var st: Dictionary = asm["st"]
		var parts: Array = st["parts"]
		if asm["placed"] >= parts.size():
			return
		if idx == asm["placed"]:
			asm["placed"] += 1
			asm["ok"] = true
			if asm["placed"] >= parts.size():
				asm["msg"] = "✓ " + parts[idx]["fact"] + " Assembly complete!"
				main.ui.show_assembly(asm)
				get_tree().create_timer(1.7).timeout.connect(_asm_done)
			else:
				asm["msg"] = "✓ " + parts[idx]["fact"]
				main.ui.show_assembly(asm)
		else:
			asm["ok"] = false
			asm["msg"] = "Not quite. " + parts[asm["placed"]]["clue"]
			main.ui.show_assembly(asm)

	func _asm_done() -> void:
		main.ui.close_modal()
		_finish_assembly()

	func _finish_assembly() -> void:
		var m = active_mission()
		if m == null:
			return
		if not main.save["assembled"].has(m["id"]):
			main.save["assembled"].append(m["id"])
		asm = null
		apply_trophies()
		main.persist()
		advance_step()

	# trophies & animations
	func apply_trophies() -> void:
		var A: Array = main.save["assembled"]
		if A.has("pathfinder") and not trophies.has("soj"):
			var s := Node3D.new()
			s.position = Vector3(31, ground_at(31, -11), -11)
			s.rotation.y = -PI / 2.0
			add_child(s)
			Mk.box(s, Vector3(0.65, 0.2, 0.48), Mk.mat(Color("d8d2c8"), 0.5, 0.2), Vector3(0, 0.26, 0))
			Mk.box(s, Vector3(0.62, 0.03, 0.46), Mk.mat(Color("1b2b5a"), 0.25, 0.6), Vector3(0, 0.4, 0))
			for x in [-0.24, 0.0, 0.24]:
				for z in [0.28, -0.28]:
					var w := Mk.cyl(s, 0.07, 0.07, 0.06, Mk.mat(Color("2c3038")), Vector3(x, 0.07, z), 12)
					w.rotation.x = PI / 2.0
			s.scale = Vector3.ONE * 1.8
			trophies["soj"] = s
			add_label("Sojourner\nbuilt by you", Vector3(31, 2.2, -11), Color("d4a43a"), 48)
		if A.has("ingenuity") and not trophies.has("heli"):
			var h := Node3D.new()
			h.position = Vector3(0, 0.16, 46)
			add_child(h)
			Mk.box(h, Vector3(0.26, 0.2, 0.22), Mk.mat(Color("d4a43a"), 0.35, 0.5), Vector3(0, 0.46, 0))
			Mk.cyl(h, 0.02, 0.02, 0.55, Mk.mat(Color("9aa0a8")), Vector3(0, 0.83, 0), 6)
			Mk.box(h, Vector3(0.42, 0.02, 0.26), Mk.mat(Color("1b2b5a"), 0.25, 0.6), Vector3(0, 1.12, 0))
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				var l := Mk.cyl(h, 0.012, 0.012, 0.5, Mk.mat(Color("9aa0a8")), Vector3(cos(a) * 0.2, 0.22, sin(a) * 0.2), 6)
				l.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
			var r1 := Node3D.new()
			r1.position.y = 0.92
			var r2 := Node3D.new()
			r2.position.y = 1.02
			r2.rotation.y = PI / 2.0
			h.add_child(r1)
			h.add_child(r2)
			Mk.box(r1, Vector3(1.2, 0.015, 0.07), Mk.mat(Color("2c3038")))
			Mk.box(r2, Vector3(1.2, 0.015, 0.07), Mk.mat(Color("2c3038")))
			h.scale = Vector3.ONE * 1.6
			trophies["heli"] = {"node": h, "r1": r1, "r2": r2}
			add_c(0, 46, 1.1)
		if A.has("insight") and not trophies.has("seis"):
			var p: Vector2 = mres["insight"][1]["to_pos"]
			var s := Node3D.new()
			s.position = Vector3(p.x, ground_at(p.x, p.y), p.y)
			add_child(s)
			Mk.sphere(s, 0.6, Mk.mat(Color("e8e4de"), 0.6), Vector3.ZERO, 24, true)
			Mk.cyl(s, 0.68, 0.72, 0.08, Mk.mat(Color("d4a43a"), 0.4, 0.4), Vector3(0, 0.04, 0), 24)
			Mk.box(s, Vector3(0.4, 0.3, 0.3), Mk.mat(Color("8a9099"), 0.5, 0.3), Vector3(1.3, 0.15, 0.2))
			trophies["seis"] = s
			add_label("InSight seismometer\nlistening for marsquakes", Vector3(p.x, 2.6, p.y), Color("d4a43a"), 48)
		if A.has("curiosity") and not trophies.has("drill"):
			rover.add_drill()
			trophies["drill"] = true

	func start_mission_anim(st: Dictionary) -> void:
		busy = true
		if st.get("anim", "") == "heli":
			apply_trophies()
			heli_anim = {"t": 0.0}
			main.toast("Spinning up the rotors… Ingenuity is flying!")
		elif st.get("anim", "") == "drill":
			apply_trophies()
			drill_anim = {"t": 0.0, "next": 0.0}
			main.toast("Drilling into John Klein…")
		else:
			busy = false
			advance_step()

	func _update_anims(dt: float) -> void:
		if heli_anim != null and trophies.has("heli"):
			var hh: Dictionary = trophies["heli"]
			heli_anim["t"] += dt
			var T: float = heli_anim["t"]
			var y := 0.0
			if T < 1.6:
				y = T / 1.6 * 3.0
			elif T < 4.6:
				y = 3.0 + sin((T - 1.6) * 2.2) * 0.15
			else:
				y = max(0.0, 3.0 * (1.0 - (T - 4.6) / 1.6))
			hh["node"].position.y = 0.16 + y
			hh["r1"].rotation.y += dt * 45.0
			hh["r2"].rotation.y -= dt * 45.0
			if T > 6.4:
				heli_anim = null
				hh["node"].position.y = 0.16
				busy = false
				advance_step()
		if drill_anim != null and rover.drill_fore:
			drill_anim["t"] += dt
			var T2: float = drill_anim["t"]
			rover.drill_fore.rotation.x = -min(1.0, T2) * 0.5
			rover.drill_bit.rotation.y += dt * 30.0
			if T2 > drill_anim["next"] and T2 > 0.8:
				drill_anim["next"] = T2 + 0.35
				Mk.burst(self, rover.drill_bit.global_position, Color("c8763e"))
			if T2 > 3.0:
				drill_anim = null
				rover.drill_fore.rotation.x = 0.0
				busy = false
				advance_step()


# ======================================================================
# All 2D interface: panels, HUD, Mission Control, modals, toasts
# ======================================================================
class UI extends CanvasLayer:
	const TEXT := Color("f3e9df")
	const MUTED := Color("b8a49a")
	const RUST := Color("e2683a")
	const TEAL := Color("5fd3c4")
	const WARN := Color("ff6a4d")
	const GOOD := Color("6fd08f")

	var main
	var root: Control
	var touch := false

	# orbit
	var orbit_ui: Control
	var fact_panel: PanelContainer
	var fact_text: RichTextLabel
	var fact_head: Button
	var fact_calc: VBoxContainer
	var kg_box: SpinBox
	var calc_out: Label
	var fact_open := true
	var fact_scroll: ScrollContainer
	var btn_inside: Button
	var orbit_hint: Label
	var orbit_buttons: HBoxContainer

	# hud
	var hud: Control
	var stats_line: Label
	var o2_bar: ProgressBar
	var en_bar: ProgressBar
	var o2_lbl: Label
	var en_lbl: Label
	var mode_lbl: Label
	var tracker: PanelContainer
	var tr_name: Label
	var tr_step: Label
	var tr_btn: Button
	var minimap: Control
	var joystick: Control
	var action_btn: Button
	var jump_btn: Button
	var keys_hint: Label
	var gem_total := 30
	var prize_total := 12

	# customise
	var custom_panel: PanelContainer
	var custom_rows := {}
	var name_edit: LineEdit

	# modal
	var modal: Control
	var modal_card: PanelContainer
	var modal_title: Label
	var modal_sub: Label
	var modal_body: VBoxContainer
	var modal_scroll: ScrollContainer
	var modal_kind := ""
	var modal_after: Callable = Callable()
	var mc_tab := "missions"
	var dec = null

	var toast_panel: PanelContainer
	var toast_label: Label
	var toast_tween: Tween
	var fade_rect: ColorRect

	var joy_vector: Vector2:
		get:
			return joystick.value if joystick else Vector2.ZERO
	var joy_index: int:
		get:
			return joystick.touch_index if joystick else -1

	func _ready() -> void:
		touch = DisplayServer.is_touchscreen_available()
		root = Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.theme = _make_theme()
		add_child(root)
		fact_open = not _is_portrait()
		_build_orbit_ui()
		_build_hud()
		_build_customize()
		_build_modal()
		_build_toast()
		fade_rect = ColorRect.new()
		fade_rect.color = Color(0, 0, 0, 0)
		fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fade_rect)
		get_viewport().size_changed.connect(_layout)
		_layout()

	# ------------------------------------------------------------------ helpers
	func _sb(bg: Color, radius := 14, margin := 12, border := Color(1, 0.8, 0.7, 0.14)) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(radius)
		sb.set_content_margin_all(margin)
		sb.border_color = border
		sb.set_border_width_all(1)
		return sb

	func _make_theme() -> Theme:
		var t := Theme.new()
		t.default_font_size = 17
		t.set_color("font_color", "Label", TEXT)
		t.set_color("default_color", "RichTextLabel", TEXT)
		t.set_stylebox("normal", "Button", _sb(Color(0.13, 0.1, 0.18, 0.92), 22, 10))
		t.set_stylebox("hover", "Button", _sb(Color(0.2, 0.15, 0.25, 0.95), 22, 10))
		t.set_stylebox("pressed", "Button", _sb(Color(0.25, 0.18, 0.3, 0.95), 22, 10))
		t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), 22, 10, TEAL))
		t.set_stylebox("disabled", "Button", _sb(Color(0.1, 0.08, 0.12, 0.6), 22, 10))
		t.set_color("font_color", "Button", TEXT)
		t.set_color("font_hover_color", "Button", Color.WHITE)
		t.set_stylebox("panel", "PanelContainer", _sb(Color(0.07, 0.05, 0.11, 0.88)))
		t.set_stylebox("background", "ProgressBar", _sb(Color(1, 1, 1, 0.12), 6, 0, Color(0, 0, 0, 0)))
		t.set_stylebox("fill", "ProgressBar", _sb(TEAL, 6, 0, Color(0, 0, 0, 0)))
		t.set_stylebox("normal", "LineEdit", _sb(Color(0.13, 0.1, 0.18, 1), 10, 8))
		return t

	func _label(text: String, size := 17, color := TEXT, wrap := false) -> Label:
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		if wrap:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return l

	func _rich(bb: String, size := 16) -> RichTextLabel:
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.text = bb
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_font_size_override("normal_font_size", size)
		r.add_theme_font_size_override("bold_font_size", size)
		r.add_theme_font_size_override("italics_font_size", size)
		return r

	func _btn(text: String, cb: Callable, primary := false) -> Button:
		var b := Button.new()
		b.text = text
		b.pressed.connect(cb)
		b.focus_mode = Control.FOCUS_NONE
		if primary:
			b.add_theme_stylebox_override("normal", _sb(RUST, 22, 10, Color(0, 0, 0, 0)))
			b.add_theme_stylebox_override("hover", _sb(RUST.lightened(0.1), 22, 10, Color(0, 0, 0, 0)))
			b.add_theme_stylebox_override("pressed", _sb(RUST.darkened(0.15), 22, 10, Color(0, 0, 0, 0)))
			b.add_theme_color_override("font_color", Color("1b0904"))
			b.add_theme_color_override("font_hover_color", Color("1b0904"))
			b.add_theme_color_override("font_pressed_color", Color("1b0904"))
		return b

	func _is_portrait() -> bool:
		var s := root.get_viewport_rect().size
		return s.y > s.x

	# ------------------------------------------------------------------ orbit UI
	func _build_orbit_ui() -> void:
		orbit_ui = Control.new()
		orbit_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		orbit_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(orbit_ui)
		var title := VBoxContainer.new()
		title.position = Vector2(18, 14)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orbit_ui.add_child(title)
		title.add_child(_label("Mars Simulator", 38, Color("f6ebe2")))
		title.add_child(_label("The red planet, 228 million km from the Sun.", 15, MUTED))

		fact_panel = PanelContainer.new()
		orbit_ui.add_child(fact_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		fact_panel.add_child(v)
		fact_head = _btn("Mars fact sheet  ▾", _toggle_facts)
		fact_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(fact_head)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		fact_scroll = sc
		v.add_child(sc)
		var inner := VBoxContainer.new()
		inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(inner)
		fact_calc = VBoxContainer.new()
		inner.add_child(fact_calc)
		fact_calc.add_child(_label("Your weight on Mars", 18, TEAL))
		var h := HBoxContainer.new()
		fact_calc.add_child(h)
		h.add_child(_label("On Earth I weigh", 16))
		kg_box = SpinBox.new()
		kg_box.min_value = 1
		kg_box.max_value = 500
		kg_box.value = 70
		kg_box.suffix = "kg"
		kg_box.value_changed.connect(func(_v): _update_calc())
		h.add_child(kg_box)
		calc_out = _label("", 15, TEXT, true)
		fact_calc.add_child(calc_out)
		fact_text = _rich(D.FACTS_TEXT, 15)
		inner.add_child(fact_text)
		_update_calc()

		orbit_buttons = HBoxContainer.new()
		orbit_buttons.add_theme_constant_override("separation", 8)
		orbit_ui.add_child(orbit_buttons)
		orbit_buttons.add_child(_btn("Find Gale Crater", func(): main.orbit.find_gale()))
		btn_inside = _btn("See inside", func(): main.orbit.toggle_inside())
		orbit_buttons.add_child(btn_inside)
		orbit_buttons.add_child(_btn("Land at Gale", func(): main.orbit.fly_to_gale(), true))
		orbit_hint = _label("", 14, Color("e9d8cc"))
		orbit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		orbit_ui.add_child(orbit_hint)
		set_orbit_hint("")

	func _update_calc() -> void:
		var kg := kg_box.value
		var feel := kg * 3.721 / 9.807
		calc_out.text = "You’d feel like %.1f kg. Your mass stays %d kg, but gravity pulls with %d N instead of %d N, so you could jump about 2.6× higher." % [feel, int(kg), int(kg * 3.721), int(kg * 9.807)]

	func _toggle_facts() -> void:
		fact_open = not fact_open
		_layout()

	func set_fact_mode(cut: bool) -> void:
		fact_text.text = D.LAYERS_TEXT if cut else D.FACTS_TEXT
		fact_calc.visible = not cut
		fact_head.text = ("Inside Mars" if cut else "Mars fact sheet") + ("  ▾" if fact_open else "  ▴")
		btn_inside.text = "See surface" if cut else "See inside"
		if cut:
			toast("You’re looking inside Mars: crust, mantle and core")

	func set_orbit_hint(t: String) -> void:
		if t == "":
			t = "Drag to spin · Scroll or pinch to zoom inside · Double-click the Gale pin to land"
		orbit_hint.text = t

	# ------------------------------------------------------------------ HUD
	func _build_hud() -> void:
		hud = Control.new()
		hud.set_anchors_preset(Control.PRESET_FULL_RECT)
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(hud)
		var col := VBoxContainer.new()
		col.position = Vector2(10, 10)
		col.add_theme_constant_override("separation", 8)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		row.add_child(_btn("Orbit", func(): main.go_orbit()))
		row.add_child(_btn("Suit", func(): main.open_customize()))
		row.add_child(_btn("Missions (M)", func(): open_mc(""), true))
		var stats := PanelContainer.new()
		stats.custom_minimum_size = Vector2(250, 0)
		col.add_child(stats)
		var sv := VBoxContainer.new()
		stats.add_child(sv)
		stats_line = _label("", 16)
		sv.add_child(stats_line)
		var r1 := _bar_row("O₂")
		o2_bar = r1[0]
		o2_lbl = r1[1]
		sv.add_child(r1[2])
		var r2 := _bar_row("Energy")
		en_bar = r2[0]
		en_lbl = r2[1]
		en_bar.add_theme_stylebox_override("fill", _sb(Color("e8a33a"), 6, 0, Color(0, 0, 0, 0)))
		sv.add_child(r2[2])
		mode_lbl = _label("", 13, MUTED)
		sv.add_child(mode_lbl)
		tracker = PanelContainer.new()
		tracker.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.12, 0.12, 0.9), 12, 10, TEAL))
		tracker.custom_minimum_size = Vector2(250, 0)
		col.add_child(tracker)
		var tv := VBoxContainer.new()
		tracker.add_child(tv)
		tr_name = _label("", 14, TEAL, true)
		tv.add_child(tr_name)
		tr_step = _label("", 15, TEXT, true)
		tv.add_child(tr_step)
		tr_btn = _btn("Open assembly", func(): main.base.open_assembly())
		tv.add_child(tr_btn)
		tracker.visible = false

		minimap = Minimap.new()
		hud.add_child(minimap)

		if touch:
			joystick = Joystick.new()
			hud.add_child(joystick)
		var pad := VBoxContainer.new()
		pad.name = "Pad"
		pad.alignment = BoxContainer.ALIGNMENT_END
		pad.add_theme_constant_override("separation", 12)
		hud.add_child(pad)
		action_btn = _btn("", func(): main.base.do_action(), true)
		action_btn.visible = false
		action_btn.custom_minimum_size = Vector2(0, 52)
		pad.add_child(action_btn)
		if touch:
			jump_btn = Button.new()
			jump_btn.text = "Jump"
			jump_btn.custom_minimum_size = Vector2(80, 80)
			jump_btn.focus_mode = Control.FOCUS_NONE
			jump_btn.button_down.connect(func(): main.base.jump_queued = true)
			pad.add_child(jump_btn)
		keys_hint = _label("WASD move · Space jump · Shift sprint · E interact · M missions · Drag to look", 14, Color.WHITE)
		keys_hint.visible = not touch
		hud.add_child(keys_hint)

	func _bar_row(name: String) -> Array:
		var h := HBoxContainer.new()
		h.add_child(_label(name, 13, MUTED))
		h.get_child(0).custom_minimum_size = Vector2(56, 0)
		var b := ProgressBar.new()
		b.show_percentage = false
		b.custom_minimum_size = Vector2(120, 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.value = 100
		h.add_child(b)
		var l := _label("100%", 13, MUTED)
		l.custom_minimum_size = Vector2(44, 0)
		h.add_child(l)
		return [b, l, h]

	func set_totals(g: int, p: int) -> void:
		gem_total = g
		prize_total = p
		update_hud()

	func update_hud() -> void:
		if main == null or main.base == null:
			return
		stats_line.text = "Gems %d    Found %d/%d    Crates %d/%d" % [int(main.save["wallet"]), main.base.gems_got, gem_total, main.base.prizes_got, prize_total]
		mode_lbl.text = ("Driving ARES" if main.base.in_rover else "On foot") + " · Sol %d" % int(main.save["sol"])

	func update_bars(o2: float, en: float) -> void:
		o2_bar.value = o2
		o2_lbl.text = "%d%%" % int(o2)
		o2_bar.add_theme_stylebox_override("fill", _sb(WARN if o2 < 25 else TEAL, 6, 0, Color(0, 0, 0, 0)))
		en_bar.value = en
		en_lbl.text = "%d%%" % int(en)

	func set_action(label: String) -> void:
		action_btn.visible = label != ""
		action_btn.text = label + ("" if touch else "  (E)")

	func update_tracker() -> void:
		var b = main.base
		var m = b.active_mission()
		tracker.visible = m != null and main.mode == "base"
		if m == null:
			return
		var a: Dictionary = main.save["active"]
		var st = b.cur_step()
		var d: float = b.nearest_target_dist()
		tr_name.text = "%s · step %d/%d%s" % [m["name"], int(a["step"]) + 1, m["steps"].size(), ("   %d m" % int(d)) if d < INF else ""]
		tr_step.text = b.step_text(st)
		tr_btn.visible = st != null and st["type"] == "assemble"

	func show_win() -> void:
		open_modal("Gale Crater cleared", "You found every gem and prize crate.")
		modal_body.add_child(_label("Your wallet holds %d gems." % int(main.save["wallet"]), 16, TEXT, true))
		modal_body.add_child(_btn("Scatter new treasure", _win_respawn, true))

	func _win_respawn() -> void:
		close_modal()
		main.base.respawn_treasure()

	# ------------------------------------------------------------------ customise
	func _build_customize() -> void:
		custom_panel = PanelContainer.new()
		root.add_child(custom_panel)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		custom_panel.add_child(sc)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 8)
		sc.add_child(v)
		v.add_child(_label("Suit up", 28))
		v.add_child(_label("Create your astronaut before you step onto Gale Crater.", 15, MUTED, true))
		v.add_child(_label("Name", 14, MUTED))
		name_edit = LineEdit.new()
		name_edit.placeholder_text = "Astronaut name"
		name_edit.max_length = 14
		name_edit.text_changed.connect(_on_name)
		v.add_child(name_edit)
		var opts := {
			"gender": [["female", "Female"], ["male", "Male"]],
			"helmet": Avatar.HELMETS,
			"suit": [],
			"skin": [[0, "Light"], [1, "Medium"], [2, "Tan"], [3, "Deep"]]}
		for i in Avatar.SUITS.size():
			opts["suit"].append([i, Avatar.SUITS[i]["name"]])
		for key in ["gender", "helmet", "suit", "skin"]:
			v.add_child(_label({"gender": "Gender", "helmet": "Helmet", "suit": "Suit", "skin": "Skin tone"}[key], 14, MUTED))
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)
			v.add_child(flow)
			var btns: Array = []
			for o in opts[key]:
				var b := _btn(o[1], _pick_option.bind(key, o[0]))
				b.toggle_mode = true
				flow.add_child(b)
				btns.append([b, o[0]])
			custom_rows[key] = btns
		v.add_child(_btn("Start mission", func(): main.finish_customize(), true))

	func _on_name(t: String) -> void:
		main.save["cfg"]["name"] = t
		main.base.avatar.build(main.save["cfg"])

	func _pick_option(key: String, val) -> void:
		main.save["cfg"][key] = val
		main.base.avatar.build(main.save["cfg"])
		_refresh_custom()

	func _refresh_custom() -> void:
		var cfg: Dictionary = main.save["cfg"]
		name_edit.text = str(cfg.get("name", ""))
		for key in custom_rows:
			for pair in custom_rows[key]:
				var cur = cfg.get(key)
				var on: bool = str(cur) == str(pair[1])
				pair[0].button_pressed = on
				pair[0].add_theme_color_override("font_color", RUST if on else TEXT)

	# ------------------------------------------------------------------ modal
	func _build_modal() -> void:
		modal = Control.new()
		modal.set_anchors_preset(Control.PRESET_FULL_RECT)
		modal.mouse_filter = Control.MOUSE_FILTER_STOP
		modal.visible = false
		root.add_child(modal)
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.01, 0.05, 0.55)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		modal.add_child(dim)
		modal_card = PanelContainer.new()
		modal_card.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.07, 0.14, 0.97), 18, 16))
		modal.add_child(modal_card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		modal_card.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		modal_title = _label("", 24, TEXT, true)
		head.add_child(modal_title)
		head.add_child(_btn("Close", close_modal))
		modal_sub = _label("", 14, MUTED, true)
		v.add_child(modal_sub)
		modal_scroll = ScrollContainer.new()
		modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(modal_scroll)
		modal_body = VBoxContainer.new()
		modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modal_body.add_theme_constant_override("separation", 10)
		modal_scroll.add_child(modal_body)

	func modal_open() -> bool:
		return modal.visible

	func open_modal(title: String, sub: String) -> void:
		modal_title.text = title
		modal_sub.text = sub
		modal_sub.visible = sub != ""
		for c in modal_body.get_children():
			modal_body.remove_child(c)
			c.queue_free()
		modal.visible = true
		modal_scroll.scroll_vertical = 0
		_layout()
		_relayout_later()

	func _relayout_later() -> void:
		await get_tree().process_frame
		_layout()
		await get_tree().process_frame
		_layout()

	func close_modal() -> void:
		if not modal.visible:
			return
		modal.visible = false
		modal_kind = ""
		var cb := modal_after
		modal_after = Callable()
		if cb.is_valid():
			cb.call()

	func _card(bg := Color(0.13, 0.1, 0.18, 1.0), border := Color(1, 0.8, 0.7, 0.14)) -> Array:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _sb(bg, 14, 12, border))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		p.add_child(v)
		modal_body.add_child(p)
		return [p, v]

	func _diff_color(diff: String) -> String:
		return {"Easy": "#6fd08f", "Medium": "#f2b84e", "Hard": "#ff6a4d"}.get(diff, "#ffffff")

	# Mission Control ---------------------------------------------------
	func open_mc(tab: String) -> void:
		if tab != "":
			mc_tab = tab
		open_modal("NASA Mission Control", "Base Ares-1, Gale Crater · Wallet: %d gems" % int(main.save["wallet"]))
		modal_kind = "mc"
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 6)
		modal_body.add_child(tabs)
		for t in [["missions", "Missions"], ["daily", "Daily log"], ["decisions", "Decisions"]]:
			var b := _btn(t[1], _switch_tab.bind(t[0]), mc_tab == t[0])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tabs.add_child(b)
		match mc_tab:
			"missions":
				_mc_missions()
			"daily":
				_mc_daily()
			_:
				_mc_decisions()

	func _switch_tab(t: String) -> void:
		mc_tab = t
		open_mc(t)

	func _mc_missions() -> void:
		var b = main.base
		modal_body.add_child(_label("Recreate real NASA Mars missions. Harder missions earn more gems, and each one ends with a history card. %d/%d completed." % [main.save["completed"].size(), D.MISSIONS.size()], 15, MUTED, true))
		for m in D.MISSIONS:
			var act: bool = main.save["active"] != null and main.save["active"]["id"] == m["id"]
			var done: bool = main.save["completed"].has(m["id"])
			var c := _card(Color(0.06, 0.14, 0.14, 1) if act else Color(0.13, 0.1, 0.18, 1), TEAL if act else Color(1, 0.8, 0.7, 0.14))
			var v: VBoxContainer = c[1]
			v.add_child(_rich("[b][font_size=19]%s[/font_size][/b]  [color=#b8a49a]%s[/color]" % [m["name"], m["years"]]))
			v.add_child(_rich("[color=%s][b]%s[/b][/color]   [color=#e2683a][b]+%d gems[/b][/color]   [color=#b8a49a]%s[/color]%s" % [_diff_color(m["diff"]), m["diff"], m["reward"], m["kind"], "   [color=#6fd08f]Completed[/color]" if done else ""], 15))
			v.add_child(_label(m["brief"], 15, TEXT, true))
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 8)
			v.add_child(row)
			if act:
				row.add_child(_label("In progress: " + b.step_text(b.cur_step()), 14, TEAL, true))
				row.add_child(_btn("Abandon", _abandon))
			else:
				var txt := "Play again" if done else ("Switch to this mission" if main.save["active"] != null else "Start mission")
				row.add_child(_btn(txt, b.start_mission.bind(m["id"]), not done))
				if done:
					row.add_child(_btn("History card", show_history.bind(m, 0)))

	func _abandon() -> void:
		main.base.abandon_mission()
		open_mc("missions")

	func _check_row(ok: bool, text: String, prog: String, reward: int, why := "") -> void:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		modal_body.add_child(h)
		h.add_child(_label("Done" if ok else "To do", 13, GOOD if ok else MUTED))
		h.get_child(0).custom_minimum_size = Vector2(48, 0)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(_label(text, 16, TEXT, true))
		if why != "":
			v.add_child(_label(why, 13, MUTED, true))
		h.add_child(_label(("%s · " % prog if prog != "" else "") + "+%d" % reward, 14, RUST))

	func _mc_daily() -> void:
		var d: Dictionary = main.save["daily"]
		modal_body.add_child(_label("Sol %d. Look after your body: Mars missions depend on rested, well-fed astronauts. Sleeping in your bed ends the sol. Energy: %d%%" % [int(main.save["sol"]), int(main.base.energy)], 15, MUTED, true))
		modal_body.add_child(_label("Daily routine", 18, TEAL))
		_check_row(int(d["meals"]) >= 2, "Eat 2 meals at the food supply", "%d/2" % mini(int(d["meals"]), 2), D.DAILY_REWARD["meals"])
		_check_row(d["rested"], "Rest on the living-room sofa", "", D.DAILY_REWARD["rest"])
		_check_row(false, "Sleep in your bed to finish the sol", "", D.DAILY_REWARD["sleep"])
		modal_body.add_child(_label("Today’s challenges", 18, TEAL))
		for c in d["ch"]:
			var C: Dictionary = D.CHALLENGES[c["id"]]
			_check_row(c["done"], C["text"], "%d/%d%s" % [int(c["prog"]), int(C["target"]), C.get("unit", "")], C["reward"], C.get("why", ""))
		_check_row(false, "Perfect sol bonus: do everything, then sleep", "", D.DAILY_REWARD["bonus"])

	func _mc_decisions() -> void:
		modal_body.add_child(_label("Every choice has a gain and a loss, and each path leads to a different outcome. If you don’t like where a path leads, retry it before you accept.", 15, MUTED, true))
		for s in D.SCENARIOS:
			var done = main.save["decisions"].get(s["id"])
			var c := _card()
			var v: VBoxContainer = c[1]
			v.add_child(_rich("[b][font_size=19]%s[/font_size][/b]" % s["title"]))
			v.add_child(_label(("Outcome: %s" % done) if done else "Not played yet · up to +35 gems", 14, GOOD if done else MUTED))
			v.add_child(_label(s["blurb"], 15, TEXT, true))
			v.add_child(_btn("Replay for practice" if done else "Play scenario", open_decision.bind(s["id"], false), done == null))

	# Assembly ----------------------------------------------------------
	func show_assembly(asm: Dictionary) -> void:
		var st: Dictionary = asm["st"]
		var parts: Array = st["parts"]
		open_modal(st["title"], st["text"])
		modal_kind = "asm"
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		modal_body.add_child(grid)
		for i in parts.size():
			var filled: bool = i < asm["placed"]
			var nxt: bool = i == asm["placed"]
			var p := PanelContainer.new()
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p.add_theme_stylebox_override("panel", _sb(Color(0.16, 0.1, 0.1, 1) if filled else Color(0.1, 0.08, 0.13, 1), 12, 10, RUST if filled else (TEAL if nxt else Color(1, 1, 1, 0.15))))
			var lv := VBoxContainer.new()
			p.add_child(lv)
			lv.add_child(_label("Step %d" % (i + 1), 13, MUTED))
			lv.add_child(_label(parts[i]["name"] if filled else ("Next part" if nxt else "Empty"), 15, TEXT if filled else MUTED, true))
			grid.add_child(p)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		modal_body.add_child(flow)
		for idx in asm["order"]:
			if idx >= asm["placed"]:
				flow.add_child(_btn(parts[idx]["name"], main.base.asm_pick.bind(idx)))
		if asm["msg"] != "":
			var c := _card(Color(0.08, 0.2, 0.12, 1) if asm["ok"] else Color(0.25, 0.08, 0.06, 1))
			c[1].add_child(_label(asm["msg"], 15, TEXT, true))

	# History card ------------------------------------------------------
	func show_history(m: Dictionary, earned: int) -> void:
		var h: Dictionary = m["history"]
		open_modal(m["name"], h["sub"])
		modal_kind = "hist"
		modal_body.add_child(_rich("[color=%s][b]%s[/b][/color]   [color=#b8a49a]%s[/color]%s" % [_diff_color(m["diff"]), m["diff"], m["years"], ("   [color=#e2683a][b]+%d gems earned[/b][/color]" % earned) if earned > 0 else ""], 16))
		var bb := "[font_size=19][color=#5fd3c4][b]Key dates[/b][/color][/font_size]\n"
		for d in h["dates"]:
			bb += "[b][color=#5fd3c4]%s[/color][/b]\n%s\n\n" % [d[0], d[1]]
		bb += "[font_size=19][color=#5fd3c4][b]Facts[/b][/color][/font_size]\n"
		for f in h["facts"]:
			bb += "•  %s\n" % f
		modal_body.add_child(_rich(bb, 16))
		modal_body.add_child(_btn("Back to Mars", close_modal, true))

	# Daily summary -----------------------------------------------------
	func show_sol_summary(prev: Dictionary, bonus: bool) -> void:
		open_modal("Sol %d complete" % int(prev["sol"]), "Here’s how your day on Mars went.")
		_check_row(int(prev["meals"]) >= 2, "Eat 2 meals", "", D.DAILY_REWARD["meals"])
		_check_row(prev["rested"], "Rest on the sofa", "", D.DAILY_REWARD["rest"])
		_check_row(true, "Sleep in your bed", "", D.DAILY_REWARD["sleep"])
		for c in prev["ch"]:
			_check_row(c["done"], D.CHALLENGES[c["id"]]["text"], "", D.CHALLENGES[c["id"]]["reward"])
		_check_row(bonus, "Perfect sol bonus", "", D.DAILY_REWARD["bonus"])
		modal_body.add_child(_label("Gems earned on Sol %d: %d. Oxygen and energy are back to 100%%." % [int(prev["sol"]), int(prev["earned"])], 15, TEXT, true))
		modal_body.add_child(_btn("Start Sol %d" % int(main.save["sol"]), close_modal, true))
		modal_after = _after_sol

	func _after_sol() -> void:
		for s in D.SCENARIOS:
			if not main.save["decisions"].has(s["id"]):
				get_tree().create_timer(0.4).timeout.connect(open_decision.bind(s["id"], true))
				return

	# Decisions ---------------------------------------------------------
	func open_decision(id: String, incoming: bool) -> void:
		var sc = null
		for s in D.SCENARIOS:
			if s["id"] == id:
				sc = s
		dec = {"sc": sc, "path": ["start"], "choices": [], "incoming": incoming}
		_render_dec()

	func _fx_text(fx: Dictionary) -> String:
		var out: Array = []
		if fx.has("gems"):
			out.append("[color=%s]%s%d gems[/color]" % ["#6fd08f" if fx["gems"] > 0 else "#ff6a4d", "+" if fx["gems"] > 0 else "−", absi(int(fx["gems"]))])
		if fx.has("o2"):
			out.append("[color=%s]%s%d%% O₂[/color]" % ["#6fd08f" if fx["o2"] > 0 else "#ff6a4d", "+" if fx["o2"] > 0 else "−", absi(int(fx["o2"]))])
		if fx.has("energy"):
			out.append("[color=%s]%s%d energy[/color]" % ["#6fd08f" if fx["energy"] > 0 else "#ff6a4d", "+" if fx["energy"] > 0 else "−", absi(int(fx["energy"]))])
		return "   ".join(out) if out.size() > 0 else "No change"

	func _render_dec() -> void:
		var sc: Dictionary = dec["sc"]
		var node: Dictionary = sc["nodes"][dec["path"][-1]]
		var done = main.save["decisions"].get(sc["id"])
		open_modal(sc["title"], "Situation report from Mission Control" if dec["incoming"] else "Decision scenario")
		modal_kind = "dec"
		if not node.get("end", false):
			modal_body.add_child(_label("Decision %d of 2" % dec["path"].size(), 13, MUTED))
			modal_body.add_child(_label(node["text"], 17, TEXT, true))
			for i in node["options"].size():
				var o: Dictionary = node["options"][i]
				var c := _card()
				var p: PanelContainer = c[0]
				p.mouse_filter = Control.MOUSE_FILTER_STOP
				p.gui_input.connect(_opt_input.bind(i))
				c[1].add_child(_rich("[b][font_size=18]%s[/font_size][/b]\n[color=#5fd3c4]+ %s[/color]\n[color=#ff6a4d]− %s[/color]" % [o["label"], o["gain"], o["loss"]], 16))
				c[1].add_child(_btn("Choose this", _choose.bind(i)))
			if dec["path"].size() > 1:
				modal_body.add_child(_btn("Go back to the previous choice", _dec_retry))
		else:
			modal_body.add_child(_rich("[font_size=22][b]%s[/b][/font_size]" % node["title"]))
			modal_body.add_child(_label(node["text"], 17, TEXT, true))
			modal_body.add_child(_rich(_fx_text(node["fx"]), 16))
			modal_body.add_child(_label("Your path: " + " → ".join(dec["choices"]), 14, MUTED, true))
			modal_body.add_child(_btn("Finish practice run" if done else "Accept this outcome", _dec_accept, true))
			modal_body.add_child(_btn("Retry the last choice", _dec_retry))
			modal_body.add_child(_btn("Start the scenario over", _dec_restart))
			modal_body.add_child(_label(("Practice run: you already accepted “%s”, so this outcome won’t change your gems." % done) if done else "Not happy with this result? Retry the path before you accept.", 13, MUTED, true))

	func _opt_input(ev: InputEvent, i: int) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_choose(i)

	func _choose(i: int) -> void:
		var node: Dictionary = dec["sc"]["nodes"][dec["path"][-1]]
		var o: Dictionary = node["options"][i]
		dec["path"].append(o["next"])
		dec["choices"].append(o["label"])
		_render_dec()

	func _dec_retry() -> void:
		if dec["path"].size() > 1:
			dec["path"].pop_back()
			dec["choices"].pop_back()
		_render_dec()

	func _dec_restart() -> void:
		dec["path"] = ["start"]
		dec["choices"] = []
		_render_dec()

	func _dec_accept() -> void:
		var sc: Dictionary = dec["sc"]
		var node: Dictionary = sc["nodes"][dec["path"][-1]]
		if not main.save["decisions"].has(sc["id"]):
			main.save["decisions"][sc["id"]] = node["title"]
			main.base.apply_fx(node["fx"])
			main.persist()
			toast("Outcome: " + node["title"])
		close_modal()

	# ------------------------------------------------------------------ toast & fade
	func _build_toast() -> void:
		toast_panel = PanelContainer.new()
		toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast_panel.modulate.a = 0.0
		root.add_child(toast_panel)
		toast_label = _label("", 16, TEXT, true)
		toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast_panel.add_child(toast_label)

	func toast(msg: String) -> void:
		toast_label.text = msg
		_layout()
		_relayout_later()
		if toast_tween:
			toast_tween.kill()
		toast_tween = create_tween()
		toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
		toast_tween.tween_interval(2.6)
		toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.4)

	func fade(cb: Callable) -> void:
		fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw := create_tween()
		tw.tween_property(fade_rect, "color:a", 1.0, 0.45)
		tw.tween_callback(cb)
		tw.tween_property(fade_rect, "color:a", 0.0, 0.45)
		tw.tween_callback(func(): fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)

	# ------------------------------------------------------------------ mode & layout
	func show_mode(mode: String) -> void:
		orbit_ui.visible = mode == "orbit"
		hud.visible = mode == "base"
		custom_panel.visible = mode == "customize"
		if mode == "customize":
			_refresh_custom()
		if mode == "base":
			update_hud()
			update_tracker()
		_layout()

	func _layout() -> void:
		if root == null:
			return
		var s := root.get_viewport_rect().size
		var portrait := s.y > s.x
		# orbit fact panel
		var fh := 0.0
		if portrait:
			fh = s.y * 0.45 if fact_open else 64.0
			fact_panel.position = Vector2(0, s.y - fh)
			fact_panel.size = Vector2(s.x, fh)
		else:
			fh = s.y - 32.0 if fact_open else 64.0
			fact_panel.position = Vector2(s.x - 376, 16)
			fact_panel.size = Vector2(360, fh)
		fact_scroll.visible = fact_open
		fact_head.text = fact_head.text.trim_suffix("  ▾").trim_suffix("  ▴") + ("  ▾" if fact_open else "  ▴")
		orbit_buttons.reset_size()
		var bw := orbit_buttons.get_combined_minimum_size().x
		var by := (s.y - fh - 64.0) if portrait else (s.y - 64.0)
		var avail := s.x if (portrait or not fact_open) else s.x - 376.0
		orbit_buttons.position = Vector2(maxf(8.0, (avail - bw) / 2.0), by)
		orbit_buttons.visible = not (portrait and fact_open)
		orbit_hint.position = Vector2(0, by - 30)
		orbit_hint.size = Vector2(avail, 24)
		# hud
		minimap.size = Vector2(150, 150)
		minimap.position = Vector2(s.x - 160, 10)
		if joystick:
			joystick.size = Vector2(140, 140)
			joystick.position = Vector2(24, s.y - 170)
		var pad: Control = hud.get_node("Pad")
		pad.reset_size()
		var ps := pad.get_combined_minimum_size()
		pad.size = ps
		pad.position = Vector2(s.x - ps.x - 22, s.y - ps.y - 26)
		keys_hint.reset_size()
		keys_hint.position = Vector2((s.x - keys_hint.get_combined_minimum_size().x) / 2.0, s.y - 34)
		# customise
		if portrait:
			custom_panel.position = Vector2(0, s.y * 0.48)
			custom_panel.size = Vector2(s.x, s.y * 0.52)
		else:
			custom_panel.position = Vector2(18, 18)
			custom_panel.size = Vector2(380, s.y - 36)
		# modal
		if portrait:
			modal_card.position = Vector2(0, s.y * 0.12)
			modal_card.size = Vector2(s.x, s.y * 0.88)
		else:
			var w := minf(640.0, s.x - 40.0)
			modal_card.position = Vector2((s.x - w) / 2.0, 24)
			modal_card.size = Vector2(w, s.y - 48)
		# toast
		var tw := minf(460.0, s.x - 30.0)
		toast_panel.size = Vector2(tw, 0)
		toast_panel.reset_size()
		toast_panel.size.x = tw
		toast_panel.position = Vector2((s.x - tw) / 2.0, s.y - 260 if portrait else s.y - 190)
