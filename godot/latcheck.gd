extends SceneTree
# B2 潜在维度开放式 headless 验证:godot --headless --path godot --script res://latcheck.gd
# 验:① 无预设含义的潜在维度,演化后表达与其环境信号正相关=功能从"环境×选择"涌现
# ② 不同区域主导不同潜在维度=涌现生态位分化(可变维度的雏形)③ 同种子可复现。确定性(种子化)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _run(seed: int, years: int):
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g; w.mutSeed = seed
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in years * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	return w

func _sig(l: float) -> float: return l

func _initialize() -> void:
	print("================ B2 潜在维度开放式 验证 ================")
	var w = _run(1, 50)
	var NL: int = w.N_LAT
	# 收集有生命格的 (latPhen[l], sig_l)
	var corr := []          # 每维 Pearson 相关
	var domCount := {}      # 各维做"主导维度"的格数
	for l in NL:
		var xs := []; var ys := []
		for j in Sim.NLat:
			for i in Sim.NLon:
				var k: int = j * Sim.NLon + i
				if w.N[k] <= Sim.SEED: continue
				var lp: float = 1.0 / (1.0 + exp(-w.latGene[k * NL + l]))
				xs.append(lp); ys.append(w._latsig(l, j))
		corr.append(_pearson(xs, ys))
	# 主导维度图:每个有生命格里表达最高的潜在维
	for j in Sim.NLat:
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			if w.N[k] <= Sim.SEED: continue
			var best := 0; var bv := -1.0
			for l in NL:
				var lp: float = 1.0 / (1.0 + exp(-w.latGene[k * NL + l]))
				if lp > bv: bv = lp; best = l
			domCount[best] = int(domCount.get(best, 0)) + 1
	var meanCorr := 0.0
	for c in corr: meanCorr += c
	meanCorr /= max(1, corr.size())
	print("① 各维 表达↔环境信号 相关: %s  均值 %.3f" % [str(corr.map(func(x): return snappedf(x, 0.01))), meanCorr])
	print("② 主导维度分布(格数): %s" % str(domCount))
	var emerge_ok: bool = meanCorr > 0.15                    # 表达整体顺环境=功能涌现
	var niche_ok: bool = domCount.size() >= 2                 # ≥2维在不同区域主导=生态位分化

	# ③ 同种子可复现
	var w2 = _run(1, 50)
	var repro: bool = w.latGene == w2.latGene
	print("③ 同种子可复现(潜在基因 bit 一致): %s" % _t(repro))

	var all_ok: bool = emerge_ok and niche_ok and repro
	print("------------------------------------------------")
	print("① 功能涌现(顺环境)%s ② 生态位分化%s ③ 可复现%s" % [_t(emerge_ok), _t(niche_ok), _t(repro)])
	print("B2 潜在维度开放式: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _pearson(xs: Array, ys: Array) -> float:
	var n: int = xs.size()
	if n < 3: return 0.0
	var mx := 0.0; var my := 0.0
	for v in xs: mx += v
	for v in ys: my += v
	mx /= n; my /= n
	var sxy := 0.0; var sxx := 0.0; var syy := 0.0
	for t in n:
		var dx: float = float(xs[t]) - mx; var dy: float = float(ys[t]) - my
		sxy += dx * dy; sxx += dx * dx; syy += dy * dy
	if sxx <= 1e-12 or syy <= 1e-12: return 0.0
	return sxy / sqrt(sxx * syy)

func _t(b: bool) -> String: return "✅" if b else "❌"
