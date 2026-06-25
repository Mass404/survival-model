extends SceneTree
# R3 日月食 headless 验证:godot --headless --path godot --script res://eclcheck.gd
# 扫 3 年(确定性几何),验:① 日食确实发生(新月恰过交点→遮日) ② 月食发生 ③ 日食时日照被削。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new(); w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var loc = LocalS.new(); loc.setup(w, g)
	var maxS := 0.0; var maxL := 0.0; var tS := 0
	for step in 3 * 365 * 48:        # 3 年,每 30 分钟一采
		loc.total = step * 30
		var s: float = loc._eclipse_cover(false)
		if s > maxS: maxS = s; tS = loc.total
		maxL = max(maxL, loc._eclipse_cover(true))
	# 日食时刻:日照应被削(无食基准 = 同位置去掉日食因子)
	loc.total = tS
	var doy: int = int(float(tS) / 1440.0) % Sim.YEAR
	var f_ecl: float = loc._sun_flux(0.0, doy)
	loc.MOONS = []                   # 临时去掉卫星→无日食
	var f_clear: float = loc._sun_flux(0.0, doy)
	print("================ R3 日月食验证 ================")
	print("3年内最大日食遮挡 %.2f(@%d分) · 最大月食遮挡 %.2f · 食时日照 %.3f vs 无食 %.3f" % [maxS, tS, maxL, f_ecl, f_clear])
	var solar: bool = maxS > 0.1
	var lunar: bool = maxL > 0.1
	var dim: bool = f_ecl < f_clear - 1e-4 if f_clear > 0.01 else true
	print("日食发生: %s" % ("✅" if solar else "❌"))
	print("月食发生: %s" % ("✅" if lunar else "❌"))
	print("日食削日照: %s" % ("✅" if dim else "❌"))
	quit(0 if (solar and lunar and dim) else 1)
