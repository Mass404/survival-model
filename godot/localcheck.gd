extends SceneTree
# 局部生存层 headless 验证:godot --headless --path godot --script res://localcheck.gd
# 验:① PushBoundary——各地点从全球行星拿到不同气候(赤道暖/极地冷/高山更冷) ②身体在局部气候下推进、断供致死
# ③玩家能沿路线旅行到目标地点。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var day := 0                                   # 把全球气候推到夏季中段,边界更稳
	for d in 200:
		w.stepDay(day % Sim.YEAR); day += 1
	var loc = LocalS.new()
	loc.setup(w, g)
	# ① 各地点气候差异
	var temps := []
	for L in loc.locs: temps.append(L["envTemp"])
	var tmin := 999.0; var tmax := -999.0
	for t in temps: tmin = min(tmin, t); tmax = max(tmax, t)
	print("================ 局部生存层验证 ================")
	for L in loc.locs: print("  %s (%.0f°): %.1f℃" % [L["name"], L["lat"], L["envTemp"]])
	var distinct: bool = (tmax - tmin) > 10.0

	# ② 身体:断水断食,放在极地(高耗),应在合理天数内死亡
	loc.player = 3   # 极地苔原
	var survived_h := 0
	for m in 12 * 24 * 60:                          # 最多跑 12 天(分钟)
		loc.step(1)
		if loc.body.dead: break
	survived_h = loc.body.hoursAlive
	var bodyworks: bool = loc.body.dead and survived_h > 24 and survived_h < 12 * 24 * 2

	# ③ 旅行:新身体,从温带林(1)走到高山(2)
	var loc2 = LocalS.new(); loc2.setup(w, g); loc2.player = 1
	var ok_start := loc2.travel_to(2)
	loc2.step(500)                                  # 路线 400 分钟 < 500
	var traveled: bool = ok_start and loc2.player == 2 and loc2.traveling == null

	# ④ 觅食生存闭环:温带林里觅食者熬过 30 天,断供者饿死/渴死
	var fora = LocalS.new(); fora.setup(w, g); fora.player = 1; fora.auto_forage = true
	for m in 30 * 24 * 60:
		fora.step(1)
		if fora.body.dead: break
	var forager_lives: bool = not fora.body.dead
	var idle = LocalS.new(); idle.setup(w, g); idle.player = 1; idle.auto_forage = false
	for m in 30 * 24 * 60:
		idle.step(1)
		if idle.body.dead: break
	var loop_works: bool = forager_lives and idle.body.dead

	# ⑤ 昼夜循环:同纬度(40°)林 vs 洞穴 的 24h 温度摆动,验证太阳驱动 + 地形热惯量
	var dn = LocalS.new(); dn.setup(w, g)
	var fMin := 999.0; var fMax := -999.0; var vMin := 999.0; var vMax := -999.0
	for h in 24:
		dn.step(60)
		var ft: float = dn.locs[1]["envTemp"]   # 温带林(40°,昼夜幅大)
		var vt: float = dn.locs[4]["envTemp"]   # 洞穴(40°,热惯量→近恒温)
		fMin = min(fMin, ft); fMax = max(fMax, ft); vMin = min(vMin, vt); vMax = max(vMax, vt)
	var fSwing := fMax - fMin; var vSwing := vMax - vMin
	var daynight: bool = fSwing > 2.0 and fSwing > vSwing + 2.0

	print("地点气候差异(跨度 %.1f℃): %s" % [tmax - tmin, "✅" if distinct else "❌"])
	print("昼夜温差·同纬度(林 %.1f℃ vs 洞穴 %.1f℃): %s" % [fSwing, vSwing, "✅" if daynight else "❌"])
	print("身体在局部气候推进+断供致死(存活 %dh,因:%s): %s" % [survived_h, loc.body.deathCause, "✅" if bodyworks else "❌"])
	print("玩家旅行到目标地点: %s" % ("✅" if traveled else "❌"))
	print("觅食生存闭环(温带林觅食者活过30天 / 断供者死@%dh): %s" % [idle.body.hoursAlive, "✅" if loop_works else "❌"])
	quit(0 if (distinct and bodyworks and traveled and loop_works and daynight) else 1)
