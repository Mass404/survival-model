extends SceneTree
# 气候强迫 headless 验证: godot --headless --path godot --script res://climcheck.gd
# 验证 撞击(周期脉冲→撞击冬天骤冷+注碳,守恒) + 米兰科维奇(冰期峰值被轨道慢周期调制)
const Sim = preload("res://sim/World.gd")

func _initialize() -> void:
	var w = Sim.new()
	w.spinUp()
	var c0: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
	var day := 0
	var cool := []          # 每年 climCool(纯冰期,不含撞击)
	var impacts := []       # 撞击年记录
	for step in 80 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			cool.append(w.climCool)
			if w.geoT % Sim.IMPACT_T == 0:
				impacts.append({"y": w.geoT, "iw": w.impactWinter, "co2": w.globalCO2})
		day += 1
	var c1: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC + w.bioC
	print("=== 气候强迫(撞击 + 米兰科维奇)验证 ===")
	print("撞击事件(每 %d 年一次):" % Sim.IMPACT_T)
	for im in impacts:
		print("  第%3d年: 撞击冬天降温 %.1f°,  注碳后大气CO2 %.2f" % [im["y"], im["iw"], im["co2"]])
	var impactOK: bool = impacts.size() > 0 and impacts.all(func(im): return im["iw"] > 6.0)
	# 米兰:冰期峰值序列(climCool 局部极大),看幅度是否被慢周期调制
	var peaks := []
	for t in range(1, cool.size() - 1):
		if cool[t] > cool[t-1] and cool[t] >= cool[t+1] and cool[t] > 6.0:
			peaks.append(cool[t])
	var pstr := ""
	for p in peaks: pstr += "%.1f " % p
	print("冰期峰值序列(climCool 局部极大): ", pstr)
	var pmin: float = peaks.min() if peaks.size() > 0 else 0.0
	var pmax: float = peaks.max() if peaks.size() > 0 else 0.0
	var milankOK: bool = peaks.size() >= 2 and (pmax - pmin) > 2.0
	var impactExt := 0
	for e in w.massExt:
		if str(e["cause"]).find("撞击") >= 0: impactExt += 1
	var cdrift: float = absf(c1 - c0)
	var cok: bool = cdrift / maxf(absf(c0), 1.0) < 1e-6                            # 相对守恒(浮点级)
	print("撞击成因大灭绝: %d 次" % impactExt)
	print("碳守恒(撞击注碳来自岩石库): 漂移 ", cdrift, "  ", "✅" if cok else "❌")
	print("撞击脉冲: %s" % ("✅ 每次都触发撞击冬天" if impactOK else "❌ 有撞击没触发"))
	print("米兰调制: %s (峰值 %.1f ~ %.1f)" % ["✅ 冰期强弱有节律" if milankOK else "❌ 峰值无变化", pmin, pmax])
	quit(0 if (impactOK and milankOK and cok) else 1)
