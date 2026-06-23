extends Control
# 场景主控:持有 World + 多尺度时钟,搭 UI,驱动 CanvasView 渲染。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const CanvasViewS = preload("res://CanvasView.gd")

const LIFE_STEP := 10
const GEO_STEP := 365
const VIEWS := [["terrain","地表"], ["life","生命"], ["adapt","适应(最适温)"], ["species","物种"], ["temp","气温带"], ["prec","降水"], ["sst","海温"]]
const SEASONS := ["🌱春", "☀️夏", "🍂秋", "❄️冬"]

var world
var geo
var canvas   # CanvasView 实例(类型注解省掉,避免独立 --check 时找不到全局类)
var day := 0
var playing := true
var days_per_sec := 40.0
var _redraw_accum := 0

var clock_label: Label
var view_buttons := {}
var play_btn: Button
var spd_label: Label
var kv := {}   # 生命面板数值 Label

func _ready() -> void:
	geo = GeoS.new()
	geo.generate()                              # 程序化真大陆(确定性,同一颗星球)
	world = Sim.new()
	world.land_mask = geo.coarse_land(Sim.NLat, Sim.NLon)   # 海陆从高程图降采样
	world.spinUp()
	_build_ui()
	canvas.setup(world, geo)
	canvas.refresh()

func _process(delta: float) -> void:
	if playing:
		var adv: int = max(1, int(round(delta * days_per_sec)))
		for k in adv:
			world.stepDay(day % Sim.YEAR)
			if day % LIFE_STEP == 0: world.stepLife(LIFE_STEP)
			if day % GEO_STEP == 0: world.stepGeo()
			day += 1
		_redraw_accum += 1
		if _redraw_accum >= 3:                   # 像素地球重绘节流(演化慢,~20Hz 足够)
			_redraw_accum = 0
			canvas.refresh()
	_update_panel()

# ====================== UI 搭建 ======================
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color8(11, 16, 32)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + s, 16)
	add_child(margin)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	margin.add_child(cols)

	# ---- 左:标题 + 画布 ----
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)

	var title := Label.new()
	title.text = "🌍 全球演化 · Evolve"
	title.add_theme_font_size_override("font_size", 18)
	left.add_child(title)

	clock_label = Label.new()
	clock_label.add_theme_color_override("font_color", Color8(138, 150, 179))
	left.add_child(clock_label)

	canvas = CanvasViewS.new()
	canvas.custom_minimum_size = Vector2(720, 360)
	left.add_child(canvas)

	var hint := Label.new()
	hint.text = "气候=每天 · 生命=每旬(10天) · 地质=每年 —— 各按自己的速度推进"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color8(138, 150, 179))
	left.add_child(hint)

	# ---- 右:控件面板 ----
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.custom_minimum_size = Vector2(360, 0)
	cols.add_child(side)

	side.add_child(_card("视图", _build_views()))
	side.add_child(_card("时间(多尺度)", _build_time()))
	side.add_child(_card("🌱 生命", _build_life()))

func _card(title: String, body: Control) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(20, 27, 48)
	sb.border_color = Color8(38, 48, 77)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var h := Label.new()
	h.text = title
	h.add_theme_color_override("font_color", Color8(138, 150, 179))
	h.add_theme_font_size_override("font_size", 13)
	box.add_child(h)
	box.add_child(body)
	panel.add_child(box)
	return panel

func _build_views() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var flow := HFlowContainer.new()
	for v in VIEWS:
		var b := Button.new()
		b.text = v[1]
		b.toggle_mode = true
		if v[0] == "terrain": b.button_pressed = true
		b.pressed.connect(_on_view.bind(v[0]))
		view_buttons[v[0]] = b
		flow.add_child(b)
	box.add_child(flow)
	var checks := HBoxContainer.new()
	checks.add_child(_check("盛行风", func(on): canvas.show_wind = on; canvas.queue_redraw()))
	checks.add_child(_check("雨带", func(on): canvas.show_belt = on; canvas.queue_redraw()))
	checks.add_child(_check("全海洋", _on_ocean))
	box.add_child(checks)
	return box

func _check(text: String, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(cb)
	return c

func _build_time() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	play_btn = Button.new()
	play_btn.text = "⏸ 暂停"
	play_btn.pressed.connect(_on_play)
	row.add_child(play_btn)
	var reset := Button.new()
	reset.text = "↺ 重置"
	reset.pressed.connect(_on_reset)
	row.add_child(reset)
	box.add_child(row)
	var srow := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "速度"
	srow.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 1; slider.max_value = 120; slider.value = 40
	slider.custom_minimum_size = Vector2(160, 0)
	slider.value_changed.connect(_on_speed)
	srow.add_child(slider)
	spd_label = Label.new()
	spd_label.text = "40 天/秒"
	srow.add_child(spd_label)
	box.add_child(srow)
	return box

func _build_life() -> Control:
	var box := VBoxContainer.new()
	for item in [["cells","已被生命占据的格"], ["bio","全球总生物量"], ["peak","最繁茂纬度带"], ["species","现存物种数"], ["mass","大灭绝(累计)"], ["morph","主导体制"]]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = item[1]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var val := Label.new()
		val.text = "—"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		kv[item[0]] = val
		box.add_child(row)
	return box

# ====================== 回调 ======================
func _on_view(v: String) -> void:
	canvas.view = v
	for k in view_buttons: view_buttons[k].button_pressed = (k == v)
	canvas.refresh()

func _on_play() -> void:
	playing = not playing
	play_btn.text = "⏸ 暂停" if playing else "▶ 播放"

func _on_reset() -> void:
	world.spinUp()
	day = 0
	canvas.refresh()

func _on_speed(v: float) -> void:
	days_per_sec = v
	spd_label.text = "%d 天/秒" % int(v)

func _on_ocean(on: bool) -> void:
	world.WATERWORLD = on
	world.spinUp()
	day = 0
	canvas.refresh()

# ====================== 面板刷新 ======================
func _season(d: int) -> String:
	var q: int = int(posmod(d - Sim.EQX, Sim.YEAR) * 4 / Sim.YEAR)
	return SEASONS[q]

func _update_panel() -> void:
	var w = world
	var ext := ""
	if w.climCool > 5.0: ext += " · ❄️冰期"
	if w.globalCO2 > Sim.CO2ref * 1.8: ext += " · 🌋暖室"
	clock_label.text = "地质 %d 年 · 第 %d 天 · %s%s · CO₂%.1f" % [w.geoT, day % Sim.YEAR, _season(day % Sim.YEAR), ext, w.globalCO2]

	var cells := 0
	var bio := 0.0
	var best_lat := "—"
	var best_v := -1.0
	for j in Sim.NLat:
		var bs := 0.0
		for i in Sim.NLon:
			if w.N[j][i] > Sim.SEED: cells += 1
			bio += w.N[j][i]
			bs += w.N[j][i]
		if bs / Sim.NLon > best_v:
			best_v = bs / Sim.NLon
			best_lat = "%d°" % int(w.latof(j))
	kv["cells"].text = "%d / %d" % [cells, Sim.NLat * Sim.NLon]
	kv["bio"].text = "%.0f" % bio
	kv["peak"].text = best_lat if best_v > 0.5 else "尚无生命"
	kv["species"].text = str(w.phylo.filter(func(p): return p["deathY"] < 0).size())
	if w.massExt.size() > 0:
		var m = w.massExt[-1]
		kv["mass"].text = "%d 次 · 最近 %s@%d年损%d种" % [w.massExt.size(), m["cause"], m["ky"], m["lost"]]
	else:
		kv["mass"].text = "0"
	var bp := {}
	for j in Sim.NLat:
		for i in Sim.NLon:
			if w.N[j][i] > Sim.SEED:
				var b = w.bodyPlan(j, i)
				bp[b] = bp.get(b, 0.0) + w.N[j][i]
	var ent := bp.keys()
	ent.sort_custom(func(a, b): return bp[a] > bp[b])
	if ent.size() > 0:
		var parts := PackedStringArray()
		for k in ent.slice(0, 3): parts.append(str(k) + "门")
		kv["morph"].text = " · ".join(parts)
	else:
		kv["morph"].text = "尚无"
