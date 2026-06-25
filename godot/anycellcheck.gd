extends SceneTree
# 两层统一·任意格求生 headless 验证:godot --headless --path godot --script res://anycellcheck.gd
# 验:局部生存层能从全球任意格实例化——派生地形/岩性/高程/气温/矿产全部来自该全局格(单一真相),且可求生。
# 扫全球格挑对比格(赤道陆/极地/海洋/最高山/铜最富),逐个 enter_cell 核对。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _clat(j: int) -> float: return -90.0 + (j + 0.5) * 180.0 / Sim.NLat
func _clon(i: int) -> float: return (i + 0.5) * 360.0 / Sim.NLon

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in 40 * Sim.YEAR:   # 行星先深时间演化:出气候/生命/成矿(stepGeo 逐年成矿,玩家再空降)
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	var loc = LocalS.new(); loc.setup(w, g)
	print("================ 两层统一·任意格求生 验证 ================")

	# —— 扫全球格挑对比代表格 ——
	var hiK := -1; var hiE := -1.0           # 最高陆格
	var eqK := -1                            # 赤道陆格(|lat|<15)
	var poK := -1                            # 极地陆格(|lat|>65)
	var seaK := -1                           # 海格
	var tempK := -1                          # 温带宜居陆格(25<|lat|<50,低海拔)
	var oreK := -1; var oreMax := -1.0       # 化学/矿产总量最富格(∑ dis+dep)
	for j in Sim.NLat:
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			var lat: float = _clat(j)
			var tot := 0.0
			for e in Sim.NE: tot += float(w.disE[k * Sim.NE + e]) + float(w.depE[k * Sim.NE + e])
			if tot > oreMax: oreMax = tot; oreK = k
			if w.Land[k] != 0:
				var em: float = max(0.0, float(w.Elev[k]) - g.SEA)
				if em > hiE: hiE = em; hiK = k
				if absf(lat) < 15.0 and eqK < 0: eqK = k
				if absf(lat) > 65.0: poK = k
				if tempK < 0 and absf(lat) > 25.0 and absf(lat) < 50.0 and em * LocalS.ELEV_M < 1200.0: tempK = k
			elif seaK < 0:
				seaK = k
	if tempK < 0: tempK = eqK   # 退路:没有合适温带陆格就用赤道陆

	# —— 逐格 enter_cell,打印派生态 ——
	var rows := {"赤道陆": eqK, "极地": poK, "海洋": seaK, "最高山": hiK, "矿最富": oreK}
	var derived := {}
	for label in rows:
		var k: int = rows[label]
		if k < 0: continue
		var lat: float = _clat(k / Sim.NLon); var lon: float = _clon(k % Sim.NLon)
		loc.enter_cell(lat, lon)
		var L = loc.cur_loc()
		# 整 33 元素逐一核对:局部 dis/dep 是否严格 == 全局格 disE/depE 切片(证矿产来自全局、非臆造)
		var match_all := true; var chemsum := 0.0
		for e in Sim.NE:
			var gd: float = float(w.disE[k * Sim.NE + e]); var gp: float = float(w.depE[k * Sim.NE + e])
			chemsum += gd + gp
			if not (is_equal_approx(float(L["dis"][e]), gd) and is_equal_approx(float(L["dep"][e]), gp)): match_all = false
		derived[label] = {"kind": L["kind"], "lith": L["lith"], "elev": float(L["elev"]),
			"temp": float(L["envTemp"]), "foodCap": float(L["foodCap"]), "match": match_all, "chemsum": chemsum, "k": k}
		print("  %-6s 格%d (%d°,%d°): %s · 岩%s · 海拔%.0fm · 环境%.1f℃ · 食容%.0f · 化学∑%.2f · 全局一致%s" % [
			label, k, int(round(lat)), int(round(lon)), L["kind"], L["lith"], float(L["elev"]), float(L["envTemp"]), float(L["foodCap"]), chemsum, str(match_all)])

	# ① 地形派生正确:海格→海岸、最高山→mountain且>2000m、极地更冷
	var sea_ok: bool = derived.has("海洋") and derived["海洋"]["kind"] == "coast"
	var mtn_ok: bool = derived.has("最高山") and derived["最高山"]["kind"] == "mountain" and derived["最高山"]["elev"] > 2000.0
	var kind_ok: bool = sea_ok and mtn_ok

	# ② 气候来自全局:赤道暖 > 极地冷
	var clim_ok: bool = derived.has("赤道陆") and derived.has("极地") and derived["赤道陆"]["temp"] > derived["极地"]["temp"] + 10.0

	# ③ 矿产/化学来自全局格(非局部臆造):整 33 元素逐一相等,且矿最富格确有可观化学量
	var min_ok: bool = derived.has("矿最富") and derived["矿最富"]["match"] and derived["矿最富"]["chemsum"] > 1.0

	# ④ 生产力梯度来自全局生物量:宜居格(赤道/海岸)食容 > 极地/高山
	var prod_ok: bool = derived.has("赤道陆") and derived.has("最高山") and derived["赤道陆"]["foodCap"] >= derived["最高山"]["foodCap"]

	# ⑤ 任意格可求生且由全局属性驱动:温带格自动觅食应能长期存活(≥3天);寒冷高山失温更快死
	loc.enter_cell(_clat(tempK / Sim.NLon), _clon(tempK % Sim.NLon)); loc.auto_forage = true
	for m in 10 * 24 * 60:
		loc.step(1)
		if loc.body.dead: break
	var tH: int = loc.body.hoursAlive

	var loc2 = LocalS.new(); loc2.setup(w, g)
	loc2.enter_cell(_clat(hiK / Sim.NLon), _clon(hiK % Sim.NLon)); loc2.auto_forage = true
	for m in 10 * 24 * 60:
		loc2.step(1)
		if loc2.body.dead: break
	var mH: int = loc2.body.hoursAlive
	print("⑤ 求生: 温带宜居 存活%dh(死因[%s]) | 寒冷高山 存活%dh(死因[%s])" % [tH, loc.body.deathCause, mH, loc2.body.deathCause])
	var surv_ok: bool = tH >= 72 and mH < tH   # 温带能撑≥3天;高山(冷)死得更快

	var all_ok: bool = kind_ok and clim_ok and min_ok and prod_ok and surv_ok
	print("------------------------------------------------")
	print("① 地形派生%s ② 气候来自全局%s ③ 矿产来自全局%s ④ 生产力梯度%s ⑤ 任意格求生%s" % [
		_t(kind_ok), _t(clim_ok), _t(min_ok), _t(prod_ok), _t(surv_ok)])
	print("两层统一·任意格求生: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
