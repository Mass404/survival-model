extends SceneTree
# 板块构造 headless 验证:godot --headless --path godot --script res://platecheck.gd
# 验:① 板块划分完整(全格分到 NPLATE 个板块)② 汇聚边界造山(抬升)≫ 离散边界裂谷(沉降)
# ③ 地质活动集中在板块边界(边界高程变化 ≫ 板块内部)④ 确定性(双实例 elev 一致)。
const GeoS = preload("res://sim/Geo.gd")

# 某格的边界汇聚度(>0 汇聚造山,<0 离散裂谷,0 非边界/平衡):复用 Geo 的板块与速度
func _conv(g, gy: int, gx: int) -> float:
	var idx: int = gy * g.COLS + gx
	var pa: int = g.plate[idx]; var va = g.plateV[pa]
	var up := 0.0; var isB := false
	for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
		var ny: int = gy + d[0]
		if ny < 0 or ny >= g.ROWS: continue
		var nx: int = (gx + d[1] + g.COLS) % g.COLS
		var pb: int = g.plate[ny * g.COLS + nx]
		if pb == pa: continue
		isB = true
		var vb = g.plateV[pb]
		up += (float(va[0]) - float(vb[0])) * float(d[1]) + (float(va[1]) - float(vb[1])) * float(d[0])
	return up if isB else 1e9   # 1e9 = 板块内部(非边界)标记

func _initialize() -> void:
	print("================ 板块构造 验证 ================")
	var g = GeoS.new(); g.generate()
	g.tectonics()   # 触发 _init_plates

	# ① 划分完整:全格 id ∈[0,NPLATE),且 NPLATE 个都用到
	var used := {}; var ok_range := true
	for idx in g.COLS * g.ROWS:
		var p: int = g.plate[idx]
		if p < 0 or p >= g.NPLATE: ok_range = false
		used[p] = true
	var part_ok: bool = ok_range and used.size() == g.NPLATE
	print("① 划分: %d 板块全用到 %s · id 全合法 %s" % [used.size(), str(used.size() == g.NPLATE), str(ok_range)])

	# 快照 elev,跑 80 地质年
	var e0 := PackedFloat32Array(); e0.resize(g.COLS * g.ROWS)
	for i in g.COLS * g.ROWS: e0[i] = g.elev[i]
	for t in 80: g.tectonics()

	# ②③ 分类:汇聚边界 / 离散边界 / 板块内部,比各自平均高程变化
	var dConv := 0.0; var nConv := 0; var dDiv := 0.0; var nDiv := 0; var dInt := 0.0; var nInt := 0
	for gy in g.ROWS:
		for gx in g.COLS:
			var idx: int = gy * g.COLS + gx
			var c: float = _conv(g, gy, gx)
			var de: float = g.elev[idx] - e0[idx]
			if c > 8e8: dInt += absf(de); nInt += 1            # 内部
			elif c > 0.05: dConv += de; nConv += 1            # 汇聚
			elif c < -0.05: dDiv += de; nDiv += 1             # 离散
	var mConv: float = dConv / max(1, nConv)
	var mDiv: float = dDiv / max(1, nDiv)
	var mInt: float = dInt / max(1, nInt)
	var mBound: float = (absf(dConv) + absf(dDiv)) / max(1, nConv + nDiv)
	print("② 汇聚边界Δ高程 %+.4f(造山) ≫ 离散边界 %+.4f(裂谷)" % [mConv, mDiv])
	print("③ 边界|Δ高程| %.4f ≫ 板块内部 %.4f(地质集中在边界)" % [mBound, mInt])
	var orogeny_ok: bool = mConv > mDiv + 0.02 and mConv > 0.0 and mDiv < 0.0
	var concentr_ok: bool = mBound > mInt * 2.0

	# ④ 确定性:另一实例同样跑 → elev bit 一致
	var g2 = GeoS.new(); g2.generate(); g2.tectonics()
	for t in 80: g2.tectonics()
	var det_ok := true
	for i in g.COLS * g.ROWS:
		if g.elev[i] != g2.elev[i]: det_ok = false; break

	var all_ok: bool = part_ok and orogeny_ok and concentr_ok and det_ok
	print("------------------------------------------------")
	print("① 划分完整%s ② 汇聚造山>离散裂谷%s ③ 地质集中在边界%s ④ 确定性%s" % [_t(part_ok), _t(orogeny_ok), _t(concentr_ok), _t(det_ok)])
	print("板块构造: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
