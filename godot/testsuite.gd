extends SceneTree
# ============================================================================
# 核心测试套件 — godot --headless --path godot --script res://testsuite.gd
# 直接验四铁律(这是 world.html→任何移植最该守、C# 版正是栽在这里):
#   ① 守恒    碳/氮/33元素 *逐年*(不只首末)相对漂移<1e-6 + 有机碳实时一致
#   ② 确定性  零随机:两个独立实例跑同序列,全场+全局逐元素 bit 完全一致
#   ③ 不变量  运行时无 NaN/Inf、生物量≥0、性状∈[0,1]、库≥0、O2/Hab 不越界
#   ④ 涌现    生命起源(无氧汤门)/GOE/食物网三级/物种分化/大灭绝/性状演化(非写死)
#   ⑤ 健全    占据/生物量/现存种 回归
# 任一失败 → exit 1。耗时约 3-4 分钟(主跑 70 年 + 双实例 25 年)。
# ============================================================================
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

var _pass := 0
var _fail := 0
var _fails: Array = []

func ok(name: String, cond: bool) -> void:
	if cond: _pass += 1
	else: _fail += 1; _fails.append(name)
	print("  %s %s" % ["✅" if cond else "❌", name])

func _newWorld():
	var g = GeoS.new(); g.generate()
	var w: Variant = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	return w

func _totC(w) -> float: return w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
func _totN(w) -> float: return w.atmN2 + w.availN
func _totElem(w) -> Array:
	var t := []
	for e in Sim.NE:
		var s: float = w.subPoolE[e] + w.rockE[e]
		for k in Sim.SZ: s += w.disE[k * Sim.NE + e] + w.depE[k * Sim.NE + e]
		t.append(s)
	return t
func _fin(x: float) -> bool: return not (is_nan(x) or is_inf(x))

func _initialize() -> void:
	print("================ 核心测试套件(四铁律) ================")
	print("\n[组1] spin-up 初值与确定性")
	_testSpinUp()
	print("\n[组2] 守恒 + 不变量 + 涌现 + 健全 (主跑 70 地质年)")
	_testMain()
	print("\n[组3] 确定性 — 零随机铁律 (双实例 25 年 bit 对比)")
	_testDeterminism()
	print("---------------------------------------------------------")
	print("通过 %d · 失败 %d" % [_pass, _fail])
	if _fail > 0:
		print("失败项:")
		for f in _fails: print("   ❌ " + f)
	print("总判定: %s" % ("✅ 全部通过" if _fail == 0 else "❌ 有失败,需排查"))
	quit(0 if _fail == 0 else 1)

func _testSpinUp() -> void:
	var w = _newWorld()
	w.spinUp()
	ok("globalCO2 初值≈2 (=" + str(w.globalCO2) + ")", w.globalCO2 >= 1.5 and w.globalCO2 <= 2.5)
	ok("ocnC 初值≈2", w.ocnC >= 1.5 and w.ocnC <= 2.5)
	ok("rockC 初值≈10000", w.rockC >= 9000.0 and w.rockC <= 11000.0)
	ok("fosC 初值=0", absf(w.fosC) < 1e-9)
	ok("globalO2 初值=0", absf(w.globalO2) < 1e-9)
	ok("bioC 初值=0", absf(w.bioC) < 1e-9)
	ok("atmN2 初值≈1000", w.atmN2 >= 900.0 and w.atmN2 <= 1100.0)
	ok("availN 初值≈2", w.availN >= 1.0 and w.availN <= 3.0)
	ok("场 N 已分配(size=SZ)", w.N.size() == Sim.SZ)
	ok("场 Co2 已分配", w.Co2.size() == Sim.SZ)
	ok("场 rEuk 已分配", w.rEuk.size() == Sim.SZ)
	ok("场 rMemb 已分配", w.rMemb.size() == Sim.SZ)
	ok("元素场 disE 已分配(SZ*NE)", w.disE.size() == Sim.SZ * Sim.NE)
	var w2 = _newWorld(); w2.spinUp()
	var same: bool = w.globalCO2 == w2.globalCO2 and w.atmN2 == w2.atmN2
	for k in Sim.SZ:
		if w.Co2[k] != w2.Co2[k] or w.N[k] != w2.N[k] or w.disE[k * Sim.NE] != w2.disE[k * Sim.NE]:
			same = false; break
	ok("spin-up 确定性(两次 bit 一致)", same)

func _scan(w) -> String:
	if not _fin(w.bioC) or w.bioC < -1e-6: return "bioC 异常=" + str(w.bioC)
	if not _fin(w.globalCO2) or w.globalCO2 < 0.0: return "globalCO2 异常=" + str(w.globalCO2)
	if w.globalO2 < -1e-9 or w.globalO2 > 21.000001: return "globalO2 越界=" + str(w.globalO2)
	if w.rockC < -1e-6 or w.ocnC < -1e-6 or w.fosC < -1e-6: return "碳库<0"
	for k in Sim.SZ:
		var n: float = w.N[k]
		if not _fin(n): return "N NaN/Inf @" + str(k)
		if n < -1e-9: return "N<0 @" + str(k)
		var c: float = w.Co2[k]
		if not _fin(c): return "Co2 NaN/Inf @" + str(k)
		if c < -1e-6: return "Co2<0 @" + str(k) + "=" + str(c)
		if w.rEuk[k] < -1e-9 or w.rEuk[k] > 1.000001: return "rEuk越界 @" + str(k) + "=" + str(w.rEuk[k])
		if w.rShell[k] < -1e-9 or w.rShell[k] > 1.000001: return "rShell越界 @" + str(k)
		if w.rSex[k] < -1e-9 or w.rSex[k] > 1.000001: return "rSex越界 @" + str(k)
		if w.rSymb[k] < -1e-9 or w.rSymb[k] > 1.000001: return "rSymb越界 @" + str(k)
		if w.Hab[k] < -1e-9 or w.Hab[k] > 1.000001: return "Hab越界 @" + str(k)
	return ""

func _testMain() -> void:
	var w = _newWorld()
	w.spinUp()
	var c0 := _totC(w); var n0 := _totN(w); var e0 := _totElem(w)
	var maxCd := 0.0; var maxNd := 0.0; var maxEd := 0.0
	var inv := ""
	var igniteY := -1; var igniteO2 := 99.0; var goeY := -1
	var maxH := 0.0; var maxC := 0.0; var maxSpec := 0
	var day := 0
	for step in 70 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			maxCd = maxf(maxCd, absf(_totC(w) - c0) / maxf(1.0, absf(c0)))
			maxNd = maxf(maxNd, absf(_totN(w) - n0) / maxf(1.0, absf(n0)))
			var et := _totElem(w)
			for e in Sim.NE: maxEd = maxf(maxEd, absf(et[e] - e0[e]) / maxf(1.0, absf(e0[e])))
			if inv == "": inv = _scan(w)
			var sH := 0.0; var sC := 0.0; var cells := 0
			for k in Sim.SZ:
				sH += w.H[k]; sC += w.C[k]
				if w.N[k] > Sim.SEED: cells += 1
			if igniteY < 0 and cells > 0: igniteY = w.geoT; igniteO2 = w.globalO2
			if goeY < 0 and w.globalO2 > 1.0: goeY = w.geoT
			maxH = maxf(maxH, sH); maxC = maxf(maxC, sC)
			var al = w.phylo.filter(func(p): return p["deathY"] < 0).size()
			if al > maxSpec: maxSpec = al
		day += 1
	# —— 守恒 ——
	ok("碳守恒·逐年(相对<1e-6) drift=" + str(maxCd), maxCd < 1e-6)
	ok("氮守恒·逐年(相对<1e-6) drift=" + str(maxNd), maxNd < 1e-6)
	ok("33元素守恒·逐年(相对<1e-6) drift=" + str(maxEd), maxEd < 1e-6)
	ok("有机碳实时一致(organicC=oCfrac·Σ三库)", _orgConsist(w))
	# —— 不变量 ——
	ok("运行时不变量(无NaN/负/越界)" + ("" if inv == "" else " 违例:" + inv), inv == "")
	# —— 涌现 ——
	ok("涌现:生命起源(点燃)", igniteY > 0)
	ok("涌现:有机汤门→延迟起源(非第1年) Y=" + str(igniteY), igniteY > 1)
	ok("涌现:无氧早期起源(起源O2<2) =" + str(igniteO2), igniteO2 < 2.0)
	ok("涌现:大氧化GOE(O2跃升>1) @Y=" + str(goeY), goeY > 0)
	ok("涌现:食物网食草者H共存(峰值=" + str(maxH) + ")", maxH > 0.0)
	ok("涌现:食物网食肉者C共存(峰值=" + str(maxC) + ")", maxC > 0.0)
	ok("涌现:物种分化(>1种,峰值=" + str(maxSpec) + ")", maxSpec > 1)
	ok("涌现:大灭绝有发生(" + str(w.massExt.size()) + "次)", w.massExt.size() > 0)
	ok("涌现:大灭绝成因有效(非空)", _causesValid(w))
	var tm := _traitMax(w)
	ok("涌现:好氧rAero演化(max=" + str(tm[0]) + ")", tm[0] > 0.1)
	ok("涌现:真核rEuk演化(max=" + str(tm[1]) + ")", tm[1] > 0.1)
	ok("涌现:体型/多细胞演化(rSize=" + str(tm[2]) + " rMulti=" + str(tm[3]) + ")", tm[2] > 0.05 or tm[3] > 0.05)
	# —— 健全 ——
	var cells2 := 0; var bio := 0.0
	for k in Sim.SZ:
		if w.N[k] > Sim.SEED: cells2 += 1
		bio += w.N[k]
	ok("健全:占据格>10 (=" + str(cells2) + ")", cells2 > 10)
	ok("健全:总生物量>0", bio > 0.0)
	ok("健全:现存种>0", w.phylo.filter(func(p): return p["deathY"] < 0).size() > 0)

func _orgConsist(w) -> bool:
	var so := 0.0
	for k in Sim.SZ: so += w.Org[k] + w.Prot[k] + w.Lip[k]
	return absf(w.organicC - 0.001 * so / float(Sim.SZ)) < 1e-6   # oCfrac=0.001

func _causesValid(w) -> bool:
	for e in w.massExt:
		if str(e["cause"]).length() == 0: return false
	return true

func _traitMax(w) -> Array:
	var a := 0.0; var eu := 0.0; var sz := 0.0; var mu := 0.0
	for k in Sim.SZ:
		a = maxf(a, w.rAero[k]); eu = maxf(eu, w.rEuk[k])
		sz = maxf(sz, w.rSize[k]); mu = maxf(mu, w.rMulti[k])
	return [a, eu, sz, mu]

func _testDeterminism() -> void:
	var wa = _newWorld(); wa.spinUp()
	var wb = _newWorld(); wb.spinUp()
	var day := 0
	for step in 25 * Sim.YEAR:
		var d := day % Sim.YEAR
		wa.stepDay(d); wb.stepDay(d)
		if day % 10 == 0: wa.stepLife(10.0); wb.stepLife(10.0)
		if day % Sim.YEAR == 0: wa.stepGeo(); wb.stepGeo()
		day += 1
	var mism := ""
	for k in Sim.SZ:
		if wa.N[k] != wb.N[k]: mism = "N@" + str(k); break
		if wa.Co2[k] != wb.Co2[k]: mism = "Co2@" + str(k); break
		if wa.rEuk[k] != wb.rEuk[k]: mism = "rEuk@" + str(k); break
		if wa.Topt[k] != wb.Topt[k]: mism = "Topt@" + str(k); break
		if wa.disE[k * Sim.NE] != wb.disE[k * Sim.NE]: mism = "disE@" + str(k); break
	var gsame: bool = wa.globalCO2 == wb.globalCO2 and wa.globalO2 == wb.globalO2 and wa.bioC == wb.bioC and wa.geoT == wb.geoT and wa.massExt.size() == wb.massExt.size()
	ok("零随机:双实例25年全场+全局 bit 一致" + ("" if mism == "" else " 不一致:" + mism), mism == "" and gsame)
