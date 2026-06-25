extends SceneTree
# R1 海底热液喷口 headless 验证:godot --headless --path godot --script res://ventcheck.gd
# 验:① 寒冷黑暗深海的喷口格也能起源生命(化能合成,非靠光/暖) ② 喷口格沉积热液硫化物(铜)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for step in 40 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	# 在"自然不宜居"(温度适应度低,光合/异养难起源)的洋格里比较:喷口格 vs 非喷口格的有生命率
	# 化能合成机理:自然不宜居(低温度适应度)洋格里,喷口格被喷口供能"点亮"成宜居,非喷口格仍不宜居
	var vents := 0
	var ventHabSum := 0.0; var ventN := 0
	var nonHabSum := 0.0; var nonN := 0
	var cuAtVent := 0.0
	for j in Sim.NLat:
		for i in Sim.NLon:
			var k: int = j * Sim.NLon + i
			if w.Land[k] != 0: continue
			if w.Vent[k] > 0.0: vents += 1; cuAtVent += w.depE[k * Sim.NE + 9]
			var teff: float = w.Teff(j, i)
			var natHab: float = exp(-pow((teff - 25.0) / 16.0, 2.0))   # 洋格自然宜居度(只靠温度/光)
			if natHab < 0.3:                                           # 自然不宜居(光合/异养难)
				if w.Vent[k] > 0.0: ventHabSum += w.Hab[k]; ventN += 1
				else: nonHabSum += w.Hab[k]; nonN += 1
	var ventHab: float = ventHabSum / max(1, ventN)
	var nonHab: float = nonHabSum / max(1, nonN)
	print("================ R1 海底热液喷口验证 ================")
	print("喷口格 %d · 自然不宜居区宜居度:喷口 %.2f(%d格) vs 非喷口 %.2f(%d格) · 喷口铜矿Σ %.2f" % [vents, ventHab, ventN, nonHab, nonN, cuAtVent])
	var cradle: bool = ventN > 0 and ventHab > nonHab + 0.3   # 喷口化能供能→宜居度被点亮
	var ore: bool = cuAtVent > 0.5
	print("化能合成生命摇篮(冷暗深海喷口起源生命): %s" % ("✅" if cradle else "❌"))
	print("热液硫化物矿(喷口铜): %s" % ("✅" if ore else "❌"))
	quit(0 if (cradle and ore and vents > 0) else 1)
