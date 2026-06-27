extends SceneTree
const K := 6
const M := 6
var W := []
func _build_W() -> void:
	W = []
	for m in M:
		var row := []
		for k in K:
			if m==k: row.append(1.4)
			else: row.append(0.35*sin(float(m)*1.7 + float(k)*2.3))
		W.append(row)
func _develop(g: Array) -> Array:
	var P := []
	for m in M:
		var s := 0.0
		for k in K: s += W[m][k]*g[k]
		P.append(1.0/(1.0+exp(-s)))
	return P
func _grad(g: Array, Pstar: Array) -> Array:
	var P := _develop(g)
	var dg := []
	for k in K:
		var d := 0.0
		for m in M: d += 2.0*(Pstar[m]-P[m])*P[m]*(1.0-P[m])*W[m][k]
		dg.append(d)
	return dg
func _evolve(Pstar: Array) -> Array:
	var g := [0.0,0.0,0.0,0.0,0.0,0.0]
	for step in 6000:
		var dg := _grad(g, Pstar)
		for k in K: g[k] += 0.2*dg[k]
	return g
func _initialize() -> void:
	_build_W()
	var Pstar := [0.9,0.8,0.7,0.2,0.3,0.1]
	var g := _evolve(Pstar)
	var P := _develop(g)
	var err := 0.0
	for m in M: err += abs(P[m]-Pstar[m])
	var Pr := []
	for m in M: Pr.append(snappedf(P[m],0.01))
	print("EXP1 evolved_P=", Pr, " totalErr=", snappedf(err,0.01))
	var g2 := g.duplicate(); g2[0]+=0.5
	var P2 := _develop(g2)
	var delta := []
	for m in M: delta.append(snappedf(P2[m]-P[m],0.001))
	print("EXP2 perturb_gene0_dP=", delta)
	var g3 := _evolve(Pstar)
	print("EXP3 determinism_identical=", g==g3)
	quit(0)