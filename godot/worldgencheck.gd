extends SceneTree
# 开局世界生成 headless 验证:godot --headless --path godot --script res://worldgencheck.gd
# 验 LocalMain 新开局序列(深时间演化→find_spawn→enter_cell):玩家空降到一颗"演化好的活星球"而非死星。
# ① 星球已演化(生命占据+大氧化GOE+成矿) ② 空降格在演化态(有食物+有矿) ③ 确定性。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")
const WGY := 20   # = LocalMain.WORLDGEN_YEARS

func _gen(seed: int):
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g; w.mutSeed = seed
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in WGY * Sim.YEAR:                      # LocalMain 同款世界生成
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var loc = LocalS.new(); loc.setup(w, g)
	var sp: Array = loc.find_spawn(); loc.enter_cell(sp[0], sp[1])
	return [w, loc, sp]

func _initialize() -> void:
	print("================ 开局世界生成(空降演化好的星球)验证 ================")
	var r = _gen(1)
	var w = r[0]; var loc = r[1]; var sp = r[2]
	# ① 星球已演化:生命占据多格 + GOE + 成矿
	var occ := 0; var depSum := 0.0
	for k in Sim.SZ:
		if w.N[k] > Sim.SEED: occ += 1
		for e in Sim.NE: depSum += w.depE[k * Sim.NE + e]
	var evolved_ok: bool = occ > 100 and w.globalO2 > 1.0 and depSum > 10.0
	print("① 星球演化: 生命占据 %d 格 · 大气O₂ %.1f(GOE) · 全球成矿Σ %.0f → %s" % [occ, w.globalO2, depSum, _t(evolved_ok)])

	# ② 空降格在演化态:有食物(来自全局生物量)+ 有矿(来自全局格化学)
	var L = loc.cur_loc()
	var depLoc := 0.0
	for e in Sim.NE: depLoc += float(L["dep"][e])
	var spawn_ok: bool = float(L["foodCap"]) > 50.0 and depLoc > 0.0
	print("② 空降格[%s]: 食容 %.0f · 本地矿Σ %.2f → %s" % [L["name"], float(L["foodCap"]), depLoc, _t(spawn_ok)])

	# ③ 确定性:同种子→同空降点 + 同星球态
	var r2 = _gen(1)
	var sp2 = r2[2]
	var det_ok: bool = is_equal_approx(sp[0], sp2[0]) and is_equal_approx(sp[1], sp2[1]) and is_equal_approx(w.globalO2, r2[0].globalO2)
	print("③ 确定性(同种子同空降同星球): %s" % _t(det_ok))

	var all_ok: bool = evolved_ok and spawn_ok and det_ok
	print("------------------------------------------------")
	print("① 星球已演化%s ② 空降格演化态%s ③ 确定性%s" % [_t(evolved_ok), _t(spawn_ok), _t(det_ok)])
	print("开局世界生成: %s" % ("✅ 全过(空降到演化好的活星球)" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
