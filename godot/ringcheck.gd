extends SceneTree
# R2 行星环 headless 验证:godot --headless --path godot --script res://ringcheck.gd
# 验:① 无环→环影/环光为0 ② 启用环→环影削冬半球日照、环光夏半球>0 ③ 启用环使日照实降。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	for d in 100: w.stepDay(d % Sim.YEAR)
	var loc = LocalS.new(); loc.setup(w, g)
	var de: float = w.decl(172) * PI / 180.0     # 北至点:北夏南冬,decl≈+23°
	var latS: float = -40.0 * PI / 180.0          # 南半球(冬)→环影落此
	var latN: float = 40.0 * PI / 180.0           # 北半球(夏)→环光

	loc.RING = null
	var sh0: float = loc._ring_shadow(latS, de)
	var shine0: float = loc._ring_shine(latN, de)
	loc.total = 720                               # 正午附近取日照
	var f_noring: float = loc._sun_flux(-40.0, 172)

	loc.RING = {"inner": 1.1, "outer": 2.3, "opacity": 0.6, "glow": 0.3}
	var sh1: float = loc._ring_shadow(latS, de)
	var shine1: float = loc._ring_shine(latN, de)
	var f_ring: float = loc._sun_flux(-40.0, 172)

	print("================ R2 行星环验证 ================")
	print("无环:环影 %.3f 环光 %.3f · 日照 %.3f" % [sh0, shine0, f_noring])
	print("有环:环影 %.3f 环光 %.3f · 日照 %.3f" % [sh1, shine1, f_ring])
	var noneZero: bool = sh0 == 0.0 and shine0 == 0.0
	var shadow: bool = sh1 > 0.0 and f_ring < f_noring
	var shine: bool = shine1 > 0.0
	print("无环时为0: %s" % ("✅" if noneZero else "❌"))
	print("环影削冬半球日照: %s" % ("✅" if shadow else "❌"))
	print("环光夏半球夜照: %s" % ("✅" if shine else "❌"))
	quit(0 if (noneZero and shadow and shine) else 1)
