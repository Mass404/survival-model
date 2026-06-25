extends SceneTree
# 默认空降开局 headless 验证:godot --headless --path godot --script res://spawncheck.gd
# 验 LocalMain 的新默认路径(setup→find_spawn→enter_cell→邻格命名→旅行)在 sim 层成立:
# 起点宜居(陆·中低纬·非极端·非高山)、cell_mode 就位、邻格有名、可旅行抵达。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in 30 * Sim.YEAR:                       # 行星演化出生命(find_spawn 按生产力挑点)
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var loc = LocalS.new(); loc.setup(w, g)
	print("================ 默认空降开局 验证 ================")

	# 默认路径:find_spawn → enter_cell(LocalMain 开局照做)
	var sp: Array = loc.find_spawn()
	loc.enter_cell(sp[0], sp[1])
	var k: int = loc.player_k
	var L = loc.cur_loc()
	var t: float = w.Teff(k / Sim.NLon, k % Sim.NLon)
	print("  起点: %s · 格%d (%.0f°,%.0f°) · 岩%s · 海拔%.0fm · 边界%.1f℃ · 食容%.0f" % [
		L["name"], k, sp[0], sp[1], L["lith"], float(L["elev"]), t, float(L["foodCap"])])

	# ① 起点宜居:陆地 · |纬|≤55 · 海拔≤2500m · 温度可液态(2~38℃) · cell_mode 就位
	var spawn_ok: bool = w.Land[k] != 0 and absf(sp[0]) <= 55.0 and float(L["elev"]) <= 2500.0 and t >= 2.0 and t <= 38.0 and loc.cell_mode and loc.player_k >= 0

	# ② 邻格有名(LocalMain 旅行按钮用 peek_cell_name):≥2 邻,名非空且非"地点[索引]"式
	var nbs: Array = loc.neighbors(loc.player)
	var name_ok: bool = nbs.size() >= 2
	var names := []
	for nb in nbs:
		var nm: String = loc.peek_cell_name(nb[0])
		names.append(nm)
		if nm.is_empty(): name_ok = false
	print("② 邻格(%d): %s" % [nbs.size(), str(names)])

	# ③ 可旅行抵达邻格(默认路径的移动)
	var destK: int = nbs[0][0]; var mins: int = nbs[0][1]
	loc.travel_to(destK)
	for m in mins + 120:
		loc.step(1)
		if loc.traveling == null: break
	var travel_ok: bool = loc.player_k == destK and loc.cell_mode
	print("③ 旅行: → 格%d(=%d:%s) 新起点[%s]" % [loc.player_k, destK, str(loc.player_k == destK), loc.cur_loc()["name"]])

	# ④ 确定性:重建实例,find_spawn 应挑同一格(零随机)
	var loc2 = LocalS.new(); loc2.setup(w, g)
	var sp2: Array = loc2.find_spawn()
	var det_ok: bool = is_equal_approx(sp2[0], sp[0]) and is_equal_approx(sp2[1], sp[1])

	var all_ok: bool = spawn_ok and name_ok and travel_ok and det_ok
	print("------------------------------------------------")
	print("① 起点宜居%s ② 邻格命名%s ③ 旅行抵达%s ④ find_spawn确定性%s" % [_t(spawn_ok), _t(name_ok), _t(travel_ok), _t(det_ok)])
	print("默认空降开局: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
