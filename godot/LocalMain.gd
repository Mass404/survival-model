extends Control
# L10 局部生存层 UI(回合制生存原型):驱动 Local 局部地点层 + 联动全球行星推进。
# 玩家在一个地点求生:看身体/环境/资源,觅食/休息/喝水/旅行/过夜,全球气候随天数演进。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

var world
var geo
var local
var loc_label: Label
var time_label: Label
var status_label: Label
var body_box: VBoxContainer
var env_label: Label
var travel_box: HBoxContainer
var log_label: Label
var _log: Array = []
var _bars := {}

func _ready() -> void:
	geo = GeoS.new(); geo.generate()
	world = Sim.new(); world.geo = geo
	world.land_mask = geo.coarse_land(Sim.NLat, Sim.NLon)
	world.spinUp()
	for d in 180: world.stepDay(d % Sim.YEAR)     # 推到温暖季,出生点宜居
	local = LocalS.new(); local.setup(world, geo)
	var sp: Array = local.find_spawn()             # 两层统一:空降全球宜居格(取代写死地点)
	local.enter_cell(sp[0], sp[1])
	_build_ui()
	_log_add("你在 %s 醒来。" % local.cur_loc()["name"])
	refresh()

# 全球行星每过一个局部日推进一天(季节/气候/海平面/演化 live)
func _advance(mins: int) -> void:
	if local.body.dead: return
	var d0: int = int(local.total / 1440)
	local.step(mins)
	var d1: int = int(local.total / 1440)
	for d in range(d0, d1):
		world.stepDay(d % Sim.YEAR)
		if d > 0 and d % Sim.YEAR == 0: world.stepGeo()
	if local.body.dead: _log_add("⚰ 你死了:%s" % local.body.deathCause)
	refresh()

func _log_add(s: String) -> void:
	_log.append(s)
	if _log.size() > 8: _log.pop_front()

# ====================== UI ======================
func _build_ui() -> void:
	var bg := ColorRect.new(); bg.color = Color8(14, 18, 26); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new(); m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]: m.add_theme_constant_override("margin_" + s, 18)
	add_child(m)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 10); m.add_child(col)

	var title := Label.new(); title.text = "🏕 局部生存"; title.add_theme_font_size_override("font_size", 20); col.add_child(title)
	loc_label = Label.new(); loc_label.add_theme_font_size_override("font_size", 15); col.add_child(loc_label)
	time_label = Label.new(); time_label.add_theme_color_override("font_color", Color8(150, 165, 195)); col.add_child(time_label)

	col.add_child(_card("身体", _build_body()))
	env_label = Label.new(); env_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_card("环境 / 资源", env_label))

	var acts := HBoxContainer.new(); acts.add_theme_constant_override("separation", 8)
	acts.add_child(_btn("🍖 觅食 1时", func(): _do_forage()))
	acts.add_child(_btn("💧 喝水 1时", func(): _do_drink()))
	acts.add_child(_btn("😴 休息 1时", func(): _advance(60)))
	acts.add_child(_btn("🌙 过一夜", func(): _do_night()))
	col.add_child(acts)

	var trow := VBoxContainer.new()
	var tl := Label.new(); tl.text = "🧭 旅行去:"; tl.add_theme_color_override("font_color", Color8(150, 165, 195)); trow.add_child(tl)
	travel_box = HBoxContainer.new(); travel_box.add_theme_constant_override("separation", 8); trow.add_child(travel_box)
	col.add_child(trow)

	status_label = Label.new(); status_label.add_theme_font_size_override("font_size", 15); col.add_child(status_label)
	log_label = Label.new(); log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_color_override("font_color", Color8(170, 180, 200)); col.add_child(_card("日志", log_label))

func _build_body() -> Control:
	body_box = VBoxContainer.new(); body_box.add_theme_constant_override("separation", 4)
	for item in [["water", "体水"], ["gly", "糖原"], ["fat", "脂肪"], ["core", "体温"], ["na", "血钠"]]:
		var row := HBoxContainer.new()
		var lab := Label.new(); lab.text = item[1]; lab.custom_minimum_size = Vector2(48, 0); row.add_child(lab)
		var bar := ProgressBar.new(); bar.custom_minimum_size = Vector2(220, 16); bar.show_percentage = false
		row.add_child(bar)
		var val := Label.new(); val.custom_minimum_size = Vector2(120, 0); row.add_child(val)
		_bars[item[0]] = [bar, val]
		body_box.add_child(row)
	return body_box

func _card(t: String, body: Control) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color8(22, 28, 42); sb.set_corner_radius_all(8); sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var b := VBoxContainer.new(); b.add_theme_constant_override("separation", 6)
	var h := Label.new(); h.text = t; h.add_theme_color_override("font_color", Color8(150, 165, 195)); h.add_theme_font_size_override("font_size", 13)
	b.add_child(h); b.add_child(body); p.add_child(b)
	return p

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = t; b.pressed.connect(cb); return b

# ====================== 动作 ======================
func _do_forage() -> void:
	local.auto_forage = true; _advance(60); local.auto_forage = false
func _do_drink() -> void:
	local.forage(1); _advance(60)            # forage 已含喝水(到解渴)
func _do_night() -> void:
	local.auto_forage = true; _advance(480); local.auto_forage = false   # 睡 8 小时
func _nb_name(k: int) -> String:                   # 邻格显示名(cell_mode:全球格;否则:locs 索引)
	return local.peek_cell_name(k) if local.cell_mode else String(local.locs[k]["name"])
func _do_travel(k: int) -> void:
	var nm: String = _nb_name(k)
	if local.travel_to(k):
		var mins: int = int(local.traveling["tot"]) + 1
		local.auto_forage = true; _advance(mins); local.auto_forage = false
		_log_add("你跋涉到了 %s。" % nm)

# ====================== 刷新 ======================
func _setbar(key: String, v: float, vmax: float, txt: String, col: Color) -> void:
	var bar: ProgressBar = _bars[key][0]
	bar.max_value = vmax; bar.value = clampf(v, 0.0, vmax)
	var sb := StyleBoxFlat.new(); sb.bg_color = col; sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", sb)
	(_bars[key][1] as Label).text = txt

func refresh() -> void:
	var L = local.cur_loc()
	var b = local.body
	loc_label.text = "📍 %s（%s · 岩%s · 海拔%dm）" % [L["name"], L["kind"], L["lith"], int(L["elev"])]
	var mn := int(local.total) % 1440
	time_label.text = "第 %d 天  %02d:%02d  ·  环境 %.1f℃  ·  %s" % [int(local.total / 1440), mn / 60, mn % 60, float(L["envTemp"]), _daypart(mn)]
	_setbar("water", 100.0 - b.dehydrationPct(), 100.0, "%.0f%%" % (100.0 - b.dehydrationPct()), Color8(70, 150, 220))
	_setbar("gly", b.glyKcal, 1800.0, "%.0f kcal" % b.glyKcal, Color8(220, 180, 60))
	_setbar("fat", b.fatG, 12000.0, "%.0f g" % b.fatG, Color8(210, 140, 70))
	_setbar("core", b.coreT, 42.0, "%.1f℃" % b.coreT, Color8(220, 90, 90) if (b.coreT < 35.0 or b.coreT > 38.5) else Color8(90, 200, 120))
	var naC: float = b.naBody / max(1.0, b.waterMl / 1000.0)
	_setbar("na", naC, 160.0, "%.0f mmol/L" % naC, Color8(160, 120, 220))
	var feels: float = local.feels_like(float(L["envTemp"]), float(L["wind"]))   # 风寒体感气温
	var aur := "   🌌极光" if local.aurora_now() > 0.05 else ""
	env_label.text = "🍖 食物 %.0f kcal   💧 水 %.0f mL   🌡 体感 %.1f℃\n❄ 雪 %.1f   🌊 潮位 %+.2f   ☢ 辐射 %.2f   💨 风 %.1f   ⚡闪电 %d%s" % [
		float(L["food"]), float(L["water"]), feels, float(L["snow"]), local.tide, float(L["radiation"]), float(L["wind"]), int(L["lightning"]), aur]
	# 旅行按钮
	for c in travel_box.get_children(): c.queue_free()
	for nb in local.neighbors(local.player):
		var k: int = nb[0]; var hrs: float = float(nb[1]) / 60.0
		travel_box.add_child(_btn("→ %s (%.0fh)" % [_nb_name(k), hrs], _do_travel.bind(k)))
	if b.dead:
		status_label.text = "⚰ 已死亡:%s（存活 %d 天 %d 小时)" % [b.deathCause, b.hoursAlive / 24, b.hoursAlive % 24]
		status_label.add_theme_color_override("font_color", Color8(220, 90, 90))
	else:
		status_label.text = "存活中 · 第 %d 天" % int(local.total / 1440)
		status_label.add_theme_color_override("font_color", Color8(120, 200, 120))
	log_label.text = "\n".join(_log)

func _daypart(mn: int) -> String:
	if mn < 300: return "深夜"
	if mn < 420: return "黎明"
	if mn < 720: return "上午"
	if mn < 1020: return "下午"
	if mn < 1200: return "黄昏"
	return "夜晚"
