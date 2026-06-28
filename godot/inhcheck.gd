extends SceneTree
# IH1 继承层(基因随生物量迁移)headless 验证:godot --headless --path godot --script res://inhcheck.gd
# 验:① 基因流——在高生物量格植入基因标记,它随生物量优先流向邻格(对照远处格隔离梯度共性)
#     ② 确定性(同种子可复现)。这是"真遗传/基因流"的核心:基因被生物量携带、高适应度格扩散其基因。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _establish():
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g; w.mutSeed = 1
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in 30 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	return w

func _neighbors(k: int) -> Array:
	var j: int = k / Sim.NLon; var i: int = k % Sim.NLon
	var out := []
	out.append(j * Sim.NLon + (i + 1) % Sim.NLon)
	out.append(j * Sim.NLon + (i - 1 + Sim.NLon) % Sim.NLon)
	if j > 0: out.append((j - 1) * Sim.NLon + i)
	if j < Sim.NLat - 1: out.append((j + 1) * Sim.NLon + i)
	return out

func _run_marker() -> float:
	var w = _establish()
	var GK: int = w.GENE_K
	# 选最高生物量陆格 k0
	var k0 := -1; var bn := -1.0
	for k in Sim.SZ:
		if w.Land[k] != 0 and w.N[k] > bn: bn = w.N[k]; k0 = k
	var nb := _neighbors(k0)
	# 对照:远处一批活格(与 k0 不相邻)
	var ctrl := []
	for k in Sim.SZ:
		if w.N[k] > Sim.SEED and k != k0 and not (k in nb) and ctrl.size() < 40 and absi(k - k0) > Sim.NLon * 2:
			ctrl.append(k)
	# 记录前(基因0=体型基因)
	var preNb := _mean0(w, nb, GK); var preCt := _mean0(w, ctrl, GK)
	w.geneE[k0 * GK + 0] = 8.0                      # 植入显著标记
	for s in 8: w.stepLife(10.0)                    # 仅 stepLife(迁移+梯度,无年度突变),让标记随生物量流
	var dNb: float = _mean0(w, nb, GK) - preNb
	var dCt: float = _mean0(w, ctrl, GK) - preCt
	print("   邻格Δ基因0 %.3f  vs  对照远格Δ %.3f" % [dNb, dCt])
	return dNb - dCt

func _mean0(w, ks: Array, GK: int) -> float:
	if ks.is_empty(): return 0.0
	var s := 0.0
	for k in ks: s += w.geneE[k * GK + 0]
	return s / ks.size()

func _initialize() -> void:
	print("================ IH1 继承层(基因随生物量迁移)验证 ================")
	var d1 := _run_marker()
	var d2 := _run_marker()
	var flow_ok: bool = d1 > 0.02                  # 标记优先流向邻格(邻格涨幅 > 对照,排除梯度共性)
	var repro: bool = is_equal_approx(d1, d2)
	print("① 基因流(邻格涨幅−对照 = %.3f > 0): %s" % [d1, _t(flow_ok)])
	print("② 确定性(双跑一致 %.3f==%.3f): %s" % [d1, d2, _t(repro)])
	var all_ok: bool = flow_ok and repro
	print("------------------------------------------------")
	print("IH1 继承层: %s" % ("✅ 全过(基因随生物量遗传/扩散)" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
