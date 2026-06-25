extends SceneTree
# 局部生存层 headless 验证:godot --headless --path godot --script res://localcheck.gd
# 验:① PushBoundary——各地点从全球行星拿到不同气候(赤道暖/极地冷/高山更冷) ②身体在局部气候下推进、断供致死
# ③玩家能沿路线旅行到目标地点。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")
const BodyS = preload("res://sim/Body.gd")

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
	loc.player = 1   # 温带林(失温归 L9 验,这里验局部气候下断供脱水)
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
	var fora = LocalS.new(); fora.setup(w, g); fora.player = 0; fora.auto_forage = true
	for m in 30 * 24 * 60:
		fora.step(1)
		if fora.body.dead: break
	var forager_lives: bool = not fora.body.dead
	var idle = LocalS.new(); idle.setup(w, g); idle.player = 0; idle.auto_forage = false
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
	print("觅食生存闭环(觅食者 %s @%dh / 断供者死@%dh): %s" % [("存活" if not fora.body.dead else ("死于" + fora.body.deathCause)), fora.body.hoursAlive, idle.body.hoursAlive, "✅" if loop_works else "❌"])

	# ⑥ L2 每地点全态:岩性多样 + 高程多样 + 地下水基流泉运转 + 土壤水有界
	var liths := {}; var elevs := {}
	var hasSpring := false; var bounded := true
	for L in fora.locs:
		liths[L["lith"]] = true; elevs[L["elev"]] = true
		if float(L["spring"]) > 0.0: hasSpring = true
		var s: float = float(L["Soil"])
		if s < -0.001 or s > float(L["soilCap"]) + 0.001: bounded = false
	var l2ok: bool = liths.size() >= 4 and elevs.size() >= 4 and hasSpring and bounded
	print("L2 全态(岩性%d种 · 高程%d档 · 地下水基流泉%s · 土壤水有界%s): %s" % [liths.size(), elevs.size(), str(hasSpring), str(bounded), "✅" if l2ok else "❌"])

	# ⑦ L3 逐地点元素化学:逐元素守恒 + 岩性成矿签名(花岗岩→U/Th,玄武岩→Ni)
	var ch = LocalS.new(); ch.setup(w, g)
	var tot0 := []
	for e in Sim.NE:
		var s: float = ch.rockE3[e]
		for L in ch.locs: s += float(L["dis"][e]) + float(L["dep"][e])
		tot0.append(s)
	for d in 120: ch.step(1440)
	var drift := 0.0
	for e in Sim.NE:
		var s: float = ch.rockE3[e]
		for L in ch.locs: s += float(L["dis"][e]) + float(L["dep"][e])
		drift = max(drift, abs(s - tot0[e]) / max(1.0, abs(tot0[e])))
	var mtn = ch.locs[2]["dep"]   # 高山=花岗岩
	var tun = ch.locs[3]["dep"]   # 苔原=玄武岩
	var mtnUTh: float = float(mtn[23]) + float(mtn[24])
	var tunUTh: float = float(tun[23]) + float(tun[24])
	var mtnTi: float = float(mtn[27])   # 钛:基性岩富、极难溶→就地沉积(不被河流带走)
	var tunTi: float = float(tun[27])
	var conserved: bool = drift < 1e-6
	var signature: bool = mtnUTh > tunUTh and tunTi > mtnTi and mtnUTh > 0.0 and tunTi > 0.0
	print("L3 元素化学(漂移 %s · 花岗岩U+Th %.2f>%.2f · 玄武岩Ti %.2f>%.2f): 守恒%s 签名%s" % [str(drift), mtnUTh, tunUTh, tunTi, mtnTi, "✅" if conserved else "❌", "✅" if signature else "❌"])
	var l3ok: bool = conserved and signature
	print("L3 元素化学守恒+签名: %s" % ("✅" if l3ok else "❌"))

	# ⑧ L4 河流下游搬运:海岸(砂岩,自身不产Ni/U)富集上游(玄武岩Ni、花岗岩U/Th)经河流带来的元素
	var coast = ch.locs[0]   # 海岸=下游终点(砂岩)
	var coastNi: float = float(coast["dis"][28]) + float(coast["dep"][28])
	var coastU: float = float(coast["dis"][23]) + float(coast["dep"][23])
	var l4ok: bool = coastNi > 0.0 and coastU > 0.0
	print("L4 河流搬运(海岸富集上游 Ni %.3f · U %.3f,自身岩性不产): %s" % [coastNi, coastU, "✅" if l4ok else "❌"])

	# ⑨ L5 水文气象:冷地积雪(暖地无)、暖湿地闪电(确定性张弛)
	var wx = LocalS.new(); wx.setup(w, g)
	for d in 60: wx.step(1440)
	var snowMtn: float = wx.locs[2]["snow"]; var snowTun: float = wx.locs[3]["snow"]; var snowCoast: float = wx.locs[0]["snow"]
	var coldSnow: float = max(snowMtn, snowTun)
	var warmLight: int = int(wx.locs[1]["lightning"]) + int(wx.locs[0]["lightning"])
	var l5ok: bool = coldSnow > 0.5 and coldSnow > snowCoast + 0.5 and warmLight > 0
	print("L5 水文气象(雪 山%.1f/苔%.1f/岸%.1f · 暖湿闪电%d次): %s" % [snowMtn, snowTun, snowCoast, warmLight, "✅" if l5ok else "❌"])

	# ⑩ L6 天文:潮汐(日内摆动)+ 月相(新月→满月)+ 辐射(极区>赤道,磁层漏斗)
	var ast = LocalS.new(); ast.setup(w, g)
	var tMin := 9.0; var tMax := -9.0
	for h in 24:
		ast.step(60)
		tMin = min(tMin, ast.tide); tMax = max(tMax, ast.tide)
	var mMin := 9.0; var mMax := -9.0
	for d in 28:
		ast.step(1440)
		mMin = min(mMin, ast.moonIllum); mMax = max(mMax, ast.moonIllum)
	var radPolar: float = ast.locs[3]["radiation"]
	var radEq: float = ast.locs[0]["radiation"]
	var l6ok: bool = (tMax - tMin) > 0.1 and (mMax - mMin) > 0.5 and radPolar > radEq
	print("L6 天文(潮差%.2f · 月相%.2f→%.2f · 辐射极%.2f>赤%.2f): %s" % [tMax - tMin, mMin, mMax, radPolar, radEq, "✅" if l6ok else "❌"])

	# ⑪ L7 成矿:砂矿(重矿 Ti 固体随河富集于下游终点海岸 > 上游)+ 红土残积(暖湿:不溶 Al 残留 ≫ 可溶 Na 淋失)
	var coastTi: float = float(ch.locs[0]["dep"][27]); var tunTiP: float = float(ch.locs[3]["dep"][27])
	var forestAl: float = float(ch.locs[1]["dep"][25]); var forestNa: float = float(ch.locs[1]["dep"][0])
	var placer: bool = coastTi > tunTiP and coastTi > 0.0
	var laterite: bool = forestAl > forestNa * 3.0 and forestAl > 0.0
	var l7ok: bool = placer and laterite
	print("L7 成矿(砂矿:海岸Ti%.2f>苔原%.2f · 红土:林Al%.2f≫Na%.2f): 砂矿%s 红土%s" % [coastTi, tunTiP, forestAl, forestNa, "✅" if placer else "❌", "✅" if laterite else "❌"])

	# ⑫ L8 局部地质:地震发生 + 沉积固结成沉积岩(成分分类)。守恒已在 L3 验
	var quakes := 0
	var lithified := 0
	var sedLith := ""
	for L in ch.locs:
		quakes += int(L["quakes"])
		if L["lithified"]: lithified += 1; sedLith = L["lith"]
	var l8ok: bool = quakes > 0 and lithified > 0
	print("L8 局部地质(地震%d次 · 固结成岩%d处 例[%s]): %s" % [quakes, lithified, sedLith, "✅" if l8ok else "❌"])

	# ⑬ L9 人体深化:严寒失温冻死 / 温和维持体温 / 出汗丢钠(低钠风险)
	var bc = BodyS.new()
	for h in 72:
		bc.drink(70)                        # 只补失水(≈不感蒸发+尿),不过量→排除脱水/低钠,只剩失温
		bc.step(1, -45.0, 1.0)              # 极寒:颤抖最大产热也补不回散热→核心温跌破→冻死
		if bc.dead: break
	var froze: bool = bc.dead and bc.deathCause.contains("失温")
	var bw = BodyS.new()
	for h in 72: bw.drink(70); bw.step(1, 24.0, 1.0)
	var warmOk: bool = (not bw.dead) and bw.coreT > 34.0
	var na0: float = bw.naBody
	var bh = BodyS.new()
	for h in 24: bh.drink(300); bh.step(1, 38.0, 1.3)   # 高温重汗
	var naLoss: bool = bh.naBody < na0
	var l9ok: bool = froze and warmOk and naLoss
	print("L9 人体(严寒%dh→%s · 温和体温%.1f℃ · 重汗丢钠%s): %s" % [bc.hoursAlive, bc.deathCause, bw.coreT, str(naLoss), "✅" if l9ok else "❌"])
	quit(0 if (distinct and bodyworks and traveled and loop_works and daynight and l2ok and l3ok and l4ok and l5ok and l6ok and l7ok and l8ok and l9ok) else 1)
