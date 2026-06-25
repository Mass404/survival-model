extends SceneTree
# 磁层-辐射-极地簇 headless 验证:godot --headless --path godot --script res://magcheck.gd
# 补 world.html 4 处遗漏:① 动态磁场(B∝核活动×自转,贫金属→场塌缩) ② 辐射(磁漏斗极区高 + U/Th本底 + 氡)
# ③ 氡(低通风/洞穴积聚,自身快衰变) ④ 风寒体感 ⑤ 极光(高磁纬+有场→可见;无场→灭)。确定性零随机。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")
const LocalS = preload("res://sim/Local.gd")

func _z() -> Array:
	var a := []; a.resize(Sim.NE); a.fill(0.0); return a

func _initialize() -> void:
	var g = GeoS.new(); g.generate()
	var w = Sim.new()
	w.geo = g
	w.land_mask = g.coarse_land(Sim.NLat, Sim.NLon)
	w.spinUp()
	var loc = LocalS.new(); loc.setup(w, g)
	print("================ 磁层·辐射·极地 验证 ================")

	# ① 动态磁场:地球态 vs 贫金属第一代(metallicity↓→核燃料↓→核活动↓→场塌缩)
	w.metallicity = 1.0
	var fieldE := w.mag_field(); var shieldE := w.mag_shield()
	w.metallicity = 0.05
	var fieldP := w.mag_field(); var shieldP := w.mag_shield()
	w.metallicity = 1.0   # 复位
	print("① 磁场: 地球 B=%.1fμT 屏蔽=%.2f  |  贫金属 B=%.2fμT 屏蔽=%.2f" % [fieldE, shieldE, fieldP, shieldP])
	var mag_ok: bool = fieldE > 40.0 and shieldE >= 0.99 and fieldP < fieldE * 0.2 and shieldP < 0.2

	# ② 辐射:磁漏斗——同地两极>赤道;贫金属屏蔽塌→赤道辐射飙升
	var eqL := {"lat": 0.0, "elev": 0.0, "dis": _z(), "dep": _z(), "radon": 0.0}
	var poL := {"lat": 80.0, "elev": 0.0, "dis": _z(), "dep": _z(), "radon": 0.0}
	var radEq := loc._radiation(eqL); var radPo := loc._radiation(poL)
	w.metallicity = 0.05
	var radEqPoor := loc._radiation(eqL)
	w.metallicity = 1.0
	print("② 辐射: 赤道%.3f < 极区%.3f(磁漏斗) | 贫金属赤道%.3f(屏蔽塌→飙升)" % [radEq, radPo, radEqPoor])
	var rad_ok: bool = radPo > radEq + 0.3 and radEqPoor > radEq + 0.5

	# ②b 地质本底:U/Th 岩石 + 氡 抬升辐射(无生命的暗洞也危险)
	var uL := {"lat": 0.0, "elev": 0.0, "dis": _z(), "dep": _z(), "radon": 0.0}
	uL["dis"][23] = 3.0; uL["dis"][24] = 2.0                    # U+Th 溶解本底
	var radU := loc._radiation(uL)
	uL["radon"] = 0.5                                            # 再叠氡气
	var radURn := loc._radiation(uL)
	print("②b U/Th本底: 净宇宙%.3f → +U/Th%.3f → +氡%.3f" % [radEq, radU, radURn])
	var geo_ok: bool = radU > radEq + 0.5 and radURn > radU + 0.5

	# ③ 氡:同等U,低通风(洞穴vent=0.0004)≫高通风(地表vent=0.3)积聚;平衡=0.0005U/(0.02+vent)
	var cave = null; var surf = null
	for L in loc.locs:
		if L["kind"] == "cave": cave = L
		elif surf == null and L["kind"] != "coast": surf = L
	cave["dis"][23] = 4.0; surf["dis"][23] = 4.0                # 给同等U源
	for h in 480: loc.step(60)                                  # 跑20天逼近平衡(每小时更新氡)
	print("③ 氡积聚: 洞穴(低通风)%.4f ≫ 地表(高通风)%.4f  比≈%.0f×" % [float(cave["radon"]), float(surf["radon"]), float(cave["radon"]) / max(1e-6, float(surf["radon"]))])
	var radon_ok: bool = float(cave["radon"]) > 0.05 and float(cave["radon"]) > 8.0 * float(surf["radon"])

	# ④ 风寒体感:有风→比气温冷;气温>33℃→无风寒(封顶)
	var f_cold := loc.feels_like(0.0, 9.0); var f_calm := loc.feels_like(10.0, 0.0); var f_hot := loc.feels_like(35.0, 9.0)
	print("④ 体感: 0℃风9→%.1f℃(更冷) | 10℃无风→%.1f℃ | 35℃风9→%.1f℃(>33无寒)" % [f_cold, f_calm, f_hot])
	var feels_ok: bool = f_cold < -3.0 and is_equal_approx(f_calm, 10.0) and is_equal_approx(f_hot, 35.0)

	# ⑤ 极光:高磁纬(70°)有场→可见;赤道→0;贫金属(场灭)→高纬也灭
	var auHi := loc.aurora_strength(70.0); var auEq := loc.aurora_strength(0.0)
	w.metallicity = 0.05
	var auPoor := loc.aurora_strength(70.0)
	w.metallicity = 1.0
	print("⑤ 极光: 高纬70°=%.3f(可见) | 赤道=%.3f | 贫金属高纬=%.3f(场灭→无极光)" % [auHi, auEq, auPoor])
	var aurora_ok: bool = auHi > 0.05 and auEq < 1e-6 and auPoor < 0.05

	var all_ok: bool = mag_ok and rad_ok and geo_ok and radon_ok and feels_ok and aurora_ok
	print("------------------------------------------------")
	print("① 动态磁场%s ② 辐射漏斗%s ②b 地质本底%s ③ 氡积聚%s ④ 体感%s ⑤ 极光%s" % [
		_t(mag_ok), _t(rad_ok), _t(geo_ok), _t(radon_ok), _t(feels_ok), _t(aurora_ok)])
	print("磁层-辐射-极地簇: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
