extends SceneTree
# 真 GRN 概念验证(隔离,落地前先跑通):godot --headless --path godot --script res://grncheck.gd
# 真 GRN 区别于 A/B 的一次性 sigmoid(Wg):表型=可演化调控矩阵 R 迭代发育到稳态的输出。
# 验:① 发育程序可演化(种子化突变+选择 hill-climb→命中目标表型)
#     ② 涌现多稳态/细胞分化(同一 R、不同初值→不同稳态吸引子=同基因组多"细胞类型")
#     ③ 吸引子数由拓扑涌现(多稳 R→≥2,收缩 R→1)④ 确定性(种子→可复现)。
const K := 6
const T := 12           # 发育迭代步数

var mseed := 1
func _noise(a: int, b: int, c: int) -> float:   # 确定性哈希→[-1,1](种子 PRNG)
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (mseed * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0xFFFFFF) * 2.0 - 1.0

# 迭代发育:a(t+1)=sigmoid(R·a(t)+b),T 步到稳态
func _dev(R: Array, bias: Array, a0: Array) -> Array:
	var a := a0.duplicate()
	for _t in T:
		var na := []
		for i in K:
			var s: float = float(bias[i])
			for j in K: s += float(R[i][j]) * float(a[j])
			na.append(1.0 / (1.0 + exp(-s)))
		a = na
	return a

func _err(p: Array, target: Array) -> float:
	var e := 0.0
	for i in K: e += abs(float(p[i]) - float(target[i]))
	return e

func _zeroR() -> Array:
	var R := []
	for i in K:
		var row := []
		for j in K: row.append(0.0)
		R.append(row)
	return R

func _initialize() -> void:
	print("================ 真 GRN 概念验证 ================")
	var bias := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var a0 := [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]

	# ① 演化发育程序:hill-climb(每步种子化突变 R,误差降则保留)逼近目标表型
	var target := [0.95, 0.1, 0.8, 0.2, 0.6, 0.4]
	var R := _zeroR()
	var bestErr: float = _err(_dev(R, bias, a0), target)
	var err0 := bestErr
	for step in 4000:
		var Rp := []
		for i in K:
			var row := []
			for j in K: row.append(float(R[i][j]) + 0.25 * _noise(step, i * K + j, 1))
			Rp.append(row)
		var e: float = _err(_dev(Rp, bias, a0), target)
		if e < bestErr: bestErr = e; R = Rp
	print("① 演化发育程序: 初始误差 %.2f → 末误差 %.3f(命中目标表型) %s" % [err0, bestErr, _t(bestErr < 0.3)])
	var evolv_ok: bool = bestErr < 0.3

	# ② 涌现多稳态/分化:双稳开关 R(0↔1 互抑+自激),同 R 不同初值→不同稳态(= 同基因组多细胞类型)
	var Rs := _zeroR()
	Rs[0][0] = 6.0; Rs[1][1] = 6.0; Rs[0][1] = -6.0; Rs[1][0] = -6.0   # toggle switch
	var bs := [-1.0, -1.0, 0.0, 0.0, 0.0, 0.0]
	var sA := _dev(Rs, bs, [0.9, 0.1, 0.5, 0.5, 0.5, 0.5])
	var sB := _dev(Rs, bs, [0.1, 0.9, 0.5, 0.5, 0.5, 0.5])
	var differ: bool = abs(float(sA[0]) - float(sB[0])) > 0.5 and abs(float(sA[1]) - float(sB[1])) > 0.5
	print("② 多稳态/分化: 同R 初值A→(%.2f,%.2f) 初值B→(%.2f,%.2f)=两种稳态(细胞分化) %s" % [sA[0], sA[1], sB[0], sB[1], _t(differ)])

	# ③ 吸引子数由拓扑涌现:多稳 R 扫多初值→≥2 个不同稳态;收缩 R(弱自激)→1 个
	var multi := _countAttr(Rs, bs)
	var Rc := _zeroR()
	for i in K: Rc[i][i] = 0.5   # 弱、收缩→单吸引子
	var single := _countAttr(Rc, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	print("③ 吸引子数由拓扑定: 多稳R=%d个 · 收缩R=%d个 %s" % [multi, single, _t(multi >= 2 and single == 1)])
	var topo_ok: bool = multi >= 2 and single == 1

	# ④ 确定性:同 seed 重跑 ① → R 一致
	mseed = 1
	var R2 := _zeroR(); var be2: float = _err(_dev(R2, bias, a0), target)
	for step in 4000:
		var Rp := []
		for i in K:
			var row := []
			for j in K: row.append(float(R2[i][j]) + 0.25 * _noise(step, i * K + j, 1))
			Rp.append(row)
		var e: float = _err(_dev(Rp, bias, a0), target)
		if e < be2: be2 = e; R2 = Rp
	var det_ok: bool = is_equal_approx(be2, bestErr)
	print("④ 确定性(同seed 末误差一致 %.3f==%.3f): %s" % [be2, bestErr, _t(det_ok)])

	var all_ok: bool = evolv_ok and differ and topo_ok and det_ok
	print("------------------------------------------------")
	print("① 程序可演化%s ② 多稳态分化%s ③ 吸引子拓扑涌现%s ④ 确定性%s" % [_t(evolv_ok), _t(differ), _t(topo_ok), _t(det_ok)])
	print("真 GRN 概念: %s" % ("✅ 全过(机制成立,可落地)" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

# 扫多个种子初值,数稳态吸引子的不同种类(按 round 到 0.1 的指纹去重)
func _countAttr(R: Array, bias: Array) -> int:
	var seen := {}
	for s in 24:
		var a0 := []
		for i in K: a0.append(0.5 + 0.5 * _noise(s, i, 9))
		var p := _dev(R, bias, a0)
		var key := ""
		for i in K: key += str(int(round(float(p[i]) * 4.0)))   # 粗指纹
		seen[key] = true
	return seen.size()

func _t(b: bool) -> String: return "✅" if b else "❌"
