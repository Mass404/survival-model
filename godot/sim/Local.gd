class_name Local
extends RefCounted
# 局部生存层地基(#9,完全移植 world.html 局部模型的起点)。
# 地点图(locs+routes)+ 逐分钟引擎 + 玩家旅行 + 人体生理(Body)。
# 全球行星按 PushBoundary 每小时把某(纬,经)的有效气候喂进每个地点(气候/海温/冰期都体现在 Teff)。
# 深层每地点系统(逐格岩性/土壤/河流/潮汐/分钟级天气)留待后续按 HANDOFF_PORTING.md 接。确定性、零随机。
const Sim = preload("res://sim/World.gd")
const BodyS = preload("res://sim/Body.gd")

var world                     # 全球行星(边界源)
var geo
var locs := []                # {name,lat,lon,kind,envTemp}
var routes := []              # [a,b,分钟]
var player := 0
var body                      # Body 实例(玩家身体)
var traveling = null          # {to,left,tot}
var total := 0                # 分钟计数
var auto_forage := false      # 开则每小时自动觅食(供验证/简单 AI)
# 天体配置(支持多恒星;默认单日地球态)。flux 相对地球, dayLen 自转周期(分钟), phase 相位
var SUNS := [{"flux": 1.0, "dayLen": 1440.0, "phase": 0.0}]
const DIURNAL := {"coast": 4.0, "forest": 9.0, "mountain": 11.0, "tundra": 7.0, "cave": 1.0}  # 昼夜温差幅(海洋/洞穴小)

func setup(w, g) -> void:
	world = w
	geo = g
	body = BodyS.new()
	_build()

func _build() -> void:
	locs = [
		{"name": "赤道海岸", "lat": 2.0, "lon": 150.0, "kind": "coast"},
		{"name": "温带林", "lat": 40.0, "lon": 150.0, "kind": "forest"},
		{"name": "高山", "lat": 42.0, "lon": 156.0, "kind": "mountain"},
		{"name": "极地苔原", "lat": 76.0, "lon": 150.0, "kind": "tundra"},
		{"name": "洞穴", "lat": 40.0, "lon": 150.0, "kind": "cave"},
	]
	routes = [[0, 1, 600], [1, 2, 400], [1, 4, 120], [1, 3, 1200]]
	_push_boundary()
	_update_temps()

# PushBoundary:全球行星某(纬,经)的有效气温 → 地点日均环境温(地形调制)
func _mean_temp(lat: float, lon: float, kind: String) -> float:
	var j: int = clampi(int((lat + 90.0) / 180.0 * Sim.NLat), 0, Sim.NLat - 1)
	var i: int = ((int(lon / 360.0 * Sim.NLon)) % Sim.NLon + Sim.NLon) % Sim.NLon
	var t: float = world.Teff(j, i)
	match kind:
		"mountain": t -= 12.0                       # 高程递减
		"cave": t = 0.7 * t + 0.3 * 12.0            # 洞穴趋恒温
		"coast": t = 0.85 * t + 0.15 * 18.0         # 海洋调节
		"tundra": t -= 2.0
	return t

func _cell(lat: float, lon: float) -> int:
	var j: int = clampi(int((lat + 90.0) / 180.0 * Sim.NLat), 0, Sim.NLat - 1)
	var i: int = ((int(lon / 360.0 * Sim.NLon)) % Sim.NLon + Sim.NLon) % Sim.NLon
	return j * Sim.NLon + i

# 逐分钟太阳高度→日照(移植 world.html sunElev/sunF;多恒星求和)
func _sun_flux(lat: float, doy: int) -> float:
	var phi := lat * PI / 180.0
	var de: float = world.decl(doy) * PI / 180.0
	var s := 0.0
	for su in SUNS:
		var frac: float = fmod(float(total) / float(su["dayLen"]) + float(su["phase"]), 1.0)
		var hangle := 2.0 * PI * frac - PI
		var e := sin(phi) * sin(de) + cos(phi) * cos(de) * cos(hangle)
		if e > 0.0: s += float(su["flux"]) * e
	return s

# 瞬时温 = 日均(全球喂)+ 昼夜摆动(太阳几何驱动:正午暖/夜里冷)
func _inst_temp(L: Dictionary) -> float:
	var doy: int = int(float(total) / 1440.0) % Sim.YEAR
	var sf := _sun_flux(L["lat"], doy)
	var amp: float = DIURNAL.get(L["kind"], 8.0)
	return float(L["meanTemp"]) + amp * (sf - 0.35)

func _update_temps() -> void:
	for L in locs: L["envTemp"] = _inst_temp(L)

func _push_boundary() -> void:
	for L in locs:
		L["meanTemp"] = _mean_temp(L["lat"], L["lon"], L["kind"])
		# 资源:食物=当地植被(全球 N 生物量) + 海岸海产;水=降水(淡水)。按容量再生
		var k: int = _cell(L["lat"], L["lon"])
		var veg: float = world.N[k] + world.H[k] * 0.5     # 生产者+食草(可猎)
		if L["kind"] == "coast": veg += 8.0                # 海产
		var precip: float = world.P[k]
		L["foodCap"] = veg * 60.0                          # kcal 容量
		L["waterCap"] = precip * 2500.0 + (300.0 if L["kind"] == "coast" else 0.0)
		L["food"] = min(L.get("food", L["foodCap"] * 0.5) + L["foodCap"] * 0.03, L["foodCap"])
		L["water"] = min(L.get("water", L["waterCap"] * 0.5) + L["waterCap"] * 0.06, L["waterCap"])

# 觅食:从当前地点采集食物/水喂给身体(消耗地点存量,会再生)
func forage(hours: int) -> void:
	var L = cur_loc()
	var gotW: float = min(L.get("water", 0.0), 350.0 * hours)
	L["water"] = L.get("water", 0.0) - gotW; body.drink(gotW)
	var gotF: float = min(L.get("food", 0.0), 220.0 * hours)
	L["food"] = L.get("food", 0.0) - gotF
	if gotF > 0.0: body.eat(gotF, gotF * 0.6, gotF * 0.04, 0.08)   # 植物/猎物:带水、少量蛋白

func cur_loc() -> Dictionary:
	return locs[player]

func neighbors(k: int) -> Array:
	var out := []
	for r in routes:
		if r[0] == k: out.append([r[1], r[2]])
		elif r[1] == k: out.append([r[0], r[2]])
	return out

func travel_to(k: int) -> bool:
	if traveling != null: return false
	for nb in neighbors(player):
		if nb[0] == k:
			traveling = {"to": k, "left": nb[1], "tot": nb[1]}
			return true
	return false

func step(minutes: int) -> void:
	for _m in minutes:
		total += 1
		if traveling != null:
			traveling["left"] -= 1
			if traveling["left"] <= 0:
				player = traveling["to"]; traveling = null
		if total % 60 == 0:                          # 每小时:刷新边界(日均)+ 昼夜瞬时温 + 觅食 + 身体
			_push_boundary()
			_update_temps()
			if auto_forage and traveling == null: forage(1)
			var env: float = cur_loc()["envTemp"]
			var act: float = 1.4 if traveling != null else 1.0   # 旅途更耗
			body.step(1, env, act)
