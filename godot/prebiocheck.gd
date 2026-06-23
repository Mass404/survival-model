extends SceneTree
# 史前有机化学 headless 验证: godot --headless --path godot --script res://prebiocheck.gd
# 验证 生命起源从'有机汤门'涌现(非第1年直接点燃) + 无氧早期才点燃 + 有机物守恒(总碳含 organicC)
const Sim = preload("res://sim/World.gd")

func _initialize() -> void:
	var w = Sim.new()
	w.spinUp()
	var c0: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC
	var sz: int = w.N.size()
	var day := 0
	var igniteY := -1
	var igniteO2 := -1.0
	var igniteOrg := 0.0
	var orgPeak := 0.0
	var goeY := -1
	var orgAtGOE := -1.0
	for step in 120 * Sim.YEAR:
		w.stepDay(day % Sim.YEAR)
		if day % 10 == 0: w.stepLife(10.0)
		if day % Sim.YEAR == 0:
			w.stepGeo()
			var so := 0.0
			for k in sz: so += w.Org[k]
			orgPeak = maxf(orgPeak, so)
			if igniteY < 0:
				var alive := false
				for k in sz:
					if w.N[k] > Sim.SEED: alive = true; break
				if alive: igniteY = w.geoT; igniteO2 = w.globalO2; igniteOrg = so
			if goeY < 0 and w.globalO2 > 1.0: goeY = w.geoT; orgAtGOE = so
		day += 1
	var c1: float = w.globalCO2 + w.ocnC + w.fosC + w.rockC + w.organicC
	var cdrift: float = absf(c1 - c0)
	print("=== 史前有机化学(生命起源)验证 ===")
	print("生命起源 @ 第 %d 年  (起源时 O2=%.2f, ΣOrg=%.1f)" % [igniteY, igniteO2, igniteOrg])
	print("ΣOrg 峰值 = %.1f,  有机碳库 organicC = %.4f" % [orgPeak, w.organicC])
	if goeY > 0: print("GOE @ 第 %d 年, 当时 ΣOrg=%.1f" % [goeY, orgAtGOE])
	print("总碳(含 organicC): 初 %.5f → 末 %.5f, 漂移 " % [c0, c1], cdrift)
	var delayOK: bool = igniteY > 1
	var anoxOK: bool = igniteY > 0 and igniteO2 < 2.0
	var consOK: bool = cdrift < 1e-3
	print("有机汤门(延迟起源): %s (第%d年,不再第1年直接点燃)" % ["✅" if delayOK else "❌", igniteY])
	print("无氧早期点燃: %s (起源 O2=%.2f < 2)" % ["✅" if anoxOK else "❌", igniteO2])
	print("有机物守恒: %s (漂移 < 1e-3)" % ("✅ 一克不差" if consOK else "❌ 漂了"))
	quit(0 if (delayOK and anoxOK and consOK) else 1)
