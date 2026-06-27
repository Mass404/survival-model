extends SceneTree
# B层 种子化突变 headless 验证:godot --headless --path godot --script res://mutcheck.gd
# 验:① 同种子→基因 bit 完全一致(可复现,testsuite 判据仍成立)② 不同种子→基因发散(突变在真探索)
# ③ 基因有空间多样性(非全格收敛到同一点)。确定性(种子化)PRNG。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _run(seed: int, years: int) -> PackedFloat64Array:
	var g = GeoS.new(); g.generate()   # 每 run 用独立新 geo(generate 确定性→起点相同;否则 tectonics 改 elev 污染下一 run)
	var w = Sim.new(); w.geo = g
	w.mutSeed = seed
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in years * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	return w.geneE.duplicate()

func _initialize() -> void:
	print("================ B层 种子化突变 验证 ================")
	var gA := _run(1, 40)
	var gB := _run(1, 40)
	var gC := _run(7, 40)

	# ① 同种子 bit 一致
	var repro: bool = gA == gB
	# ② 不同种子发散(基因有差异 = 突变在真探索)
	var diffs := 0; var maxd := 0.0
	for i in gA.size():
		var d: float = absf(gA[i] - gC[i])
		if d > 1e-9: diffs += 1
		maxd = max(maxd, d)
	var explore: bool = diffs > 0
	# ③ 基因空间多样性(种子1:逐基因位看全格方差是否>0)
	var meanv := 0.0; var cnt := 0
	for i in gA.size(): meanv += gA[i]; cnt += 1
	meanv /= max(1, cnt)
	var varsum := 0.0
	for i in gA.size(): varsum += (gA[i] - meanv) * (gA[i] - meanv)
	var diversity: bool = varsum / max(1, cnt) > 1e-4

	print("① 同种子可复现(基因 bit 一致): %s" % _t(repro))
	print("② 不同种子发散(差异基因数 %d/%d · 最大差 %.3f): %s" % [diffs, gA.size(), maxd, _t(explore)])
	print("③ 基因空间多样性(方差 %.4f > 0): %s" % [varsum / max(1, cnt), _t(diversity)])
	var all_ok: bool = repro and explore and diversity
	print("------------------------------------------------")
	print("B层 种子化突变: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
