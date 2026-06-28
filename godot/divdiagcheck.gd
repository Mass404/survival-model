extends SceneTree
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
func _stat(w):
	var mc := 0; var dp := 0; var rmmax := 0.0; var dmax := 0.0; var dsum := 0.0
	for k in Sim.SZ:
		if w.N[k] <= Sim.SEED: continue
		rmmax = maxf(rmmax, w.rMulti[k])
		if w.rMulti[k] >= 0.25:
			mc += 1
			var d: float = w._divPotential(k)
			dmax = maxf(dmax, d); dsum += d
			if d > 0.01: dp += 1
	var dmean: float = dsum / maxf(1.0, float(mc))
	return "rMultiMax=%.2f multicell=%d divPot>0.01=%d dMax=%.3f dMean=%.3f" % [rmmax, mc, dp, dmax, dmean]
func _initialize():
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g; w.mutSeed = 1
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for s in 150 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			if w.geoT % 25 == 0: print("Y%d %s" % [w.geoT, _stat(w)])
		day += 1
	quit(0)