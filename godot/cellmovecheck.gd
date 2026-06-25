extends SceneTree
# U2 网格移动 + U3 化学读全局 headless 验证:godot --headless --path godot --script res://cellmovecheck.gd
# U2:邻接全球格移动(旅行时间∝大圆距离)、抵达后在新格重建 locale、确定性。
# U3:cell_mode 下局部化学/矿读全局(深时间推进→局部同步),非冻结私有副本。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _clat(j: int) -> float: return -90.0 + (j + 0.5) * 180.0 / Sim.NLat
func _clon(i: int) -> float: return (i + 0.5) * 360.0 / Sim.NLon

func _advance(w, years: int, day0: int) -> int:
	var day := day0
	for s in years * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	return day

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := _advance(w, 40, 0)
	var loc = LocalS.new(); loc.setup(w, g)
	print("================ U2 网格移动 + U3 化学读全局 验证 ================")

	# 选内陆起点格(非极点行,1<j<NLat-1)
	var startK := -1
	for j in range(1, Sim.NLat - 1):
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			if w.Land[k] != 0: startK = k; break
		if startK >= 0: break
	loc.enter_cell(_clat(startK / Sim.NLon), _clon(startK % Sim.NLon))

	# ① 邻接:内陆格应有 4 邻;各邻旅行分钟>0 且 == 大圆距离/步速(一致)
	var nbs: Array = loc.neighbor_cells(loc.player_k)
	var cnt_ok: bool = nbs.size() == 4
	var time_ok := true
	for nb in nbs:
		var expect: int = loc._travel_minutes(loc.player_k, nb[0])
		if nb[1] != expect or nb[1] <= 0: time_ok = false
	print("① 邻接: %d 邻 · 旅行分钟 %s · 例:大圆%.0fkm→%.1f天" % [
		nbs.size(), str(time_ok), loc._gc_km(loc.player_k, nbs[0][0]), float(nbs[0][1]) / 1440.0])
	var nb_ok: bool = cnt_ok and time_ok

	# ② 移动:travel_to 一个邻格,step 到抵达 → player_k 更新、locale 在新格重建(中心吻合)
	var destK: int = nbs[0][0]
	var mins: int = nbs[0][1]
	var ok_start: bool = loc.travel_to(destK)
	for m in mins + 120:
		loc.step(1)
		if loc.traveling == null: break
	var dctr: Array = loc._cell_center(destK)
	var arrived: bool = (loc.player_k == destK) and is_equal_approx(float(loc.cur_loc()["lat"]), dctr[0]) and is_equal_approx(float(loc.cur_loc()["lon"]), dctr[1])
	print("② 移动: 起程%s · 抵达格%d(=目标%d:%s) · 新地点[%s]" % [str(ok_start), loc.player_k, destK, str(loc.player_k == destK), loc.cur_loc()["name"]])
	var move_ok: bool = ok_start and arrived

	# ③ 确定性:另一实例同样空降+travel+step → player_k 与到达耗时 bit 一致
	var loc2 = LocalS.new(); loc2.setup(w, g)
	loc2.enter_cell(_clat(startK / Sim.NLon), _clon(startK % Sim.NLon))
	loc2.travel_to(destK)
	for m in mins + 120:
		loc2.step(1)
		if loc2.traveling == null: break
	var det_ok: bool = (loc2.player_k == loc.player_k) and (loc2.total == loc.total)
	print("③ 确定性: 双实例 player_k=%d/%d total=%d/%d → %s" % [loc.player_k, loc2.player_k, loc.total, loc2.total, str(det_ok)])

	# ④ U3 化学读全局:enter 后局部==全局;推进全局深时间→局部仍冻结(未同步);step 一天→同步到新全局
	var loc3 = LocalS.new(); loc3.setup(w, g)
	# 选化学/矿最活跃格(喷口优先,否则 dep 总量最大)→ 深时间推进后变化明显
	var actK := -1; var bestVent := 0.0; var bestDep := -1.0
	for k in Sim.SZ:
		if k < w.Vent.size() and float(w.Vent[k]) > bestVent: bestVent = float(w.Vent[k]); actK = k
	if actK < 0:
		for k in Sim.SZ:
			var s := 0.0
			for e in Sim.NE: s += float(w.depE[k * Sim.NE + e])
			if s > bestDep: bestDep = s; actK = k
	loc3.enter_cell(_clat(actK / Sim.NLon), _clon(actK % Sim.NLon))
	var d0: Array = (loc3.cur_loc()["dep"] as Array).duplicate()           # 进入时局部 dep(=全局t0)
	day = _advance(w, 20, day)                                             # 推进全局深时间 20 年
	var g1_diff_d0 := false                                               # 全局确实变了?
	for e in Sim.NE:
		if not is_equal_approx(float(w.depE[actK * Sim.NE + e]), float(d0[e])): g1_diff_d0 = true
	var frozen_ok := true                                                 # 同步前局部应仍==d0(冻结,不随全局漂)
	for e in Sim.NE:
		if not is_equal_approx(float(loc3.cur_loc()["dep"][e]), float(d0[e])): frozen_ok = false
	loc3.step(1440)                                                       # 走一天→日界触发 _sync_chem_from_global
	var synced_ok := true                                                 # 同步后局部应==全局现态(t1)
	for e in Sim.NE:
		if not is_equal_approx(float(loc3.cur_loc()["dep"][e]), float(w.depE[actK * Sim.NE + e])): synced_ok = false
	print("④ U3读全局: 格%d 全局20年有变化%s · 同步前冻结%s · 同步后==全局%s" % [actK, str(g1_diff_d0), str(frozen_ok), str(synced_ok)])
	var u3_ok: bool = g1_diff_d0 and frozen_ok and synced_ok

	var all_ok: bool = nb_ok and move_ok and det_ok and u3_ok
	print("------------------------------------------------")
	print("① 邻接%s ② 移动重建%s ③ 确定性%s ④ U3化学读全局%s" % [_t(nb_ok), _t(move_ok), _t(det_ok), _t(u3_ok)])
	print("U2 网格移动 + U3 化学读全局: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
