extends SceneTree
# B3 可变维度数 headless 验证:godot --headless --path godot --script res://b3check.gd
# 验:① 有效表达维度数(门控开启数)因格而异=维度数从演化涌现(非固定)② 简约压力起效(均值<上限,非全开)
# ③ 同种子可复现。确定性(种子化)。
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

func _initialize() -> void:
	print("================ B3 可变维度数 验证 ================")
	var w = _run(1, 50)
	var NL: int = w.N_LAT
	var counts := {}        # 有效维度数 → 格数
	var cmin := 999; var cmax := -1; var csum := 0; var cells := 0
	for j in Sim.NLat:
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			if w.N[k] <= Sim.SEED: continue
			var c := 0
			for l in NL:
				if w.latGate[k * NL + l] > 0.0: c += 1   # gate>0 ↔ sigmoid>0.5 = 表达开启
			counts[c] = int(counts.get(c, 0)) + 1
			cmin = min(cmin, c); cmax = max(cmax, c); csum += c; cells += 1
	var mean: float = float(csum) / max(1, cells)
	print("① 有效维度数分布(维度数→格数): %s" % str(counts))
	print("   范围 %d~%d · 均值 %.2f(上限 %d)" % [cmin, cmax, mean, NL])
	var vary_ok: bool = cmax > cmin and counts.size() >= 2          # 因格而异=维度数涌现
	var parsimony_ok: bool = mean < float(NL) and cmax <= NL        # 简约压力:非全开

	# ③ 同种子可复现
	var w2 = _run(1, 50)
	var repro: bool = w.latGate == w2.latGate
	print("② 简约压力(均值<上限,非全开): %s" % _t(parsimony_ok))
	print("③ 同种子可复现(门控基因 bit 一致): %s" % _t(repro))

	var all_ok: bool = vary_ok and parsimony_ok and repro
	print("------------------------------------------------")
	print("① 维度数因格而异(涌现)%s ② 简约压力%s ③ 可复现%s" % [_t(vary_ok), _t(parsimony_ok), _t(repro)])
	print("B3 可变维度数: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
