extends SceneTree
# R4 多世界配置 headless 验证:godot --headless --path godot --script res://worldcheck.gd
# 对照:地球(metallicity=1)vs 贫金属第一代星(metallicity=0.1)。验:贫金属星重元素矿(Cu/Au/U)远少,
# 非重元素(钙)不受影响 → 配置真的产出不同世界(贫金属→无矿无核燃料)。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

func _heavy_dep(w) -> Array:
	var cu := 0.0; var au := 0.0; var u := 0.0; var ca := 0.0
	for k in Sim.SZ:
		var b: int = k * Sim.NE
		cu += w.depE[b + 9]; au += w.depE[b + 15]; u += w.depE[b + 23]; ca += w.depE[b + 1]
	return [cu, au, u, ca]

func _run(g, metal: float) -> Array:
	var w = Sim.new(); w.geo = g
	w.metallicity = metal
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0
	for step in 40 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0: w.stepGeo()
		day += 1
	return _heavy_dep(w)

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var earth = _run(g, 1.0)
	var poor = _run(g, 0.1)
	print("================ R4 多世界配置验证 ================")
	print("地球(metal 1.0):  铜 %.1f  金 %.3f  铀 %.2f  钙 %.1f" % [earth[0], earth[1], earth[2], earth[3]])
	print("贫金属(metal 0.1): 铜 %.1f  金 %.3f  铀 %.2f  钙 %.1f" % [poor[0], poor[1], poor[2], poor[3]])
	var heavyScales: bool = poor[0] < earth[0] * 0.3 and poor[1] < earth[1] * 0.3   # 重元素(铜/金)随金属丰度大减
	var caUnchanged: bool = abs(poor[3] - earth[3]) < earth[3] * 0.1 + 1.0          # 钙(非重)基本不变
	print("贫金属星重元素矿大减(Cu/Au): %s" % ("✅" if heavyScales else "❌"))
	print("非重元素(钙)不受金属丰度影响: %s" % ("✅" if caUnchanged else "❌"))
	quit(0 if (heavyScales and caUnchanged) else 1)
