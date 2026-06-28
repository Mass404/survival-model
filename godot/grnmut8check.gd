extends SceneTree
# 定位: 纯多稳态选择下, N_LAT=8 (64维R) 随机种子突变能否自举 -> 区分"维度" vs "World信噪比"
const NL := 8
func _h(a: int, b: int) -> float:
	var x: int = (a*73856093) ^ (b*19349663)
	x = (x ^ (x >> 13)) * 1274126177
	return float(x & 0x7fffffff) / 2147483647.0
func _dev(R, bias, a0, T):
	var a = a0.duplicate()
	for it in T:
		var na = []
		for l in NL:
			var s: float = bias[l]
			for m in NL: s += R[l*NL+m]*float(a[m])
			na.append(1.0/(1.0+exp(-s)))
		a = na
	return a
func _multi(R, bias) -> float:
	var inits = [[0.9,0.9,0.9,0.9,0.9,0.9,0.9,0.9],[0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1],[0.9,0.1,0.9,0.1,0.9,0.1,0.9,0.1],[0.1,0.9,0.1,0.9,0.1,0.9,0.1,0.9]]
	var fin = []
	for a0 in inits: fin.append(_dev(R, bias, a0, 12))
	var md := 0.0
	for i in fin.size():
		for j in range(i+1, fin.size()):
			var d := 0.0
			for l in NL: d += absf(float(fin[i][l]) - float(fin[j][l]))
			md = maxf(md, d)
	return md
func _evolve_mut(bias, sd: int, steps: int) -> float:
	var R = []
	for x in NL*NL: R.append(0.0)
	var best := _multi(R, bias)
	for step in steps:
		var idx: int = int(_h(sd*7+step, 1) * 99991) % (NL*NL)
		var dv: float = (0.3 if _h(sd+step, 2) > 0.5 else -0.3)
		var R2 = R.duplicate(); R2[idx] += dv
		var m2 := _multi(R2, bias)
		if m2 >= best: R = R2; best = m2
	return best
func _initialize():
	var bias = []
	for x in NL: bias.append(0.0)
	print("N_LAT=8 pure-multi selection, seeded mutation:")
	print("  6000 steps seed1=", snappedf(_evolve_mut(bias,1,6000),0.01), " seed2=", snappedf(_evolve_mut(bias,2,6000),0.01))
	print("  12000 steps seed1=", snappedf(_evolve_mut(bias,1,12000),0.01))
	quit(0)