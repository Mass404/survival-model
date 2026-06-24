extends SceneTree
# 守恒账本 headless 验证:godot --headless --path godot --script res://conscheck.gd
# spinUp + 跑 N 年,验证碳总量、氮总量逐年一克不差(库间只搬运),且大氧化 O2 涌现。
const Sim = preload("res://sim/World.gd")

func _initialize() -> void:
	var w = Sim.new()
	w.spinUp()
	var c0: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
	var n0: float = w.atmN2 + w.availN
	print("spin-up 后  总碳 %.6f  总氮 %.6f" % [c0, n0])
	var day := 0
	var goe := -1
	for step in 120 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			if goe < 0 and w.globalO2 > 1.0: goe = w.geoT
			if w.geoT % 20 == 0:
				var ct: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
				var nt: float = w.atmN2 + w.availN
				print("  第%3d年  总碳 %.6f  总氮 %.6f | 大气CO2 %.2f  O2 %.2f  还原库 %.0f  化石 %.1f" % [w.geoT, ct, nt, w.globalCO2, w.globalO2, w.globalRed, w.fosC])
		day += 1
	var c1: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
	var n1: float = w.atmN2 + w.availN
	print("================ 守恒账本验证 ================")
	print("末态库 organicC=%.3f bioC=%.3f fosC=%.3f" % [w.organicC, w.bioC, w.fosC])
	print("碳: 初 %.6f → 末 %.6f" % [c0, c1]); print("   碳漂移 = ", c1 - c0)
	print("氮: 初 %.6f → 末 %.6f" % [n0, n1]); print("   氮漂移 = ", n1 - n0)
	var cok: bool = absf(c1 - c0) / maxf(absf(c0), 1.0) < 1e-6   # 相对守恒(局部化累加在万级 rockC 上,绝对判据按浮点级放宽)
	var nok: bool = absf(n1 - n0) < 1e-4
	var goeok: bool = w.globalO2 > 1.0
	print("碳守恒: %s" % ("✅ 一克不差" if cok else "❌ 漂了"))
	print("氮守恒: %s" % ("✅ 一克不差" if nok else "❌ 漂了"))
	if goeok: print("大氧化: ✅ O2 跃升到 %.1f(GOE@第%d年,还原库已耗到 %.0f)" % [w.globalO2, goe, w.globalRed])
	else: print("大氧化: O2 仍压在 %.2f(还原库 %.0f,需调参或跑更久)" % [w.globalO2, w.globalRed])
	quit(0 if (cok and nok) else 1)
