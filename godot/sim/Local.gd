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
# 33元素逐地点化学(全保真:本地岩性 LITHO 驱动风化→溶解→沉淀成矿)。元素名用 Sim.MN
const ELITHO := {
	"花岗岩": [0.4, [0.02,0.05,0.02,0.15,0.02,0.01,0.02,0.05,0.40,0.005,0.0,0.02,0.20,0.01,0.005,0.02,0.01,0.0,0.0,0.02,0.0,0.0,0.15,0.15,0.20,0.40,0.05,0.05,0.0,0.0,0.02,0.0,0.0]],
	"石灰岩": [1.0, [0.03,0.80,0.15,0.02,0.01,0.02,0.10,0.90,0.05,0.005,0.0,0.02,0.0,0.25,0.10,0.0,0.05,0.02,0.02,0.20,0.05,0.0,0.02,0.05,0.02,0.05,0.10,0.0,0.0,0.0,0.05,0.0,0.02]],
	"玄武岩": [0.8, [0.05,0.30,0.40,0.05,0.35,0.02,0.08,0.15,0.20,0.30,0.0,0.15,0.01,0.02,0.01,0.005,0.30,0.0,0.0,0.15,0.08,0.0,0.03,0.01,0.02,0.20,0.20,0.30,0.25,0.30,0.0,0.20,0.02]],
	"砂岩": [0.5, [0.05,0.05,0.03,0.03,0.03,0.03,0.03,0.04,0.50,0.01,0.0,0.02,0.0,0.0,0.0,0.005,0.02,0.15,0.02,0.02,0.0,0.0,0.01,0.10,0.02,0.05,0.02,0.10,0.0,0.0,0.05,0.0,0.10]],
	"蒸发岩": [1.5, [1.50,0.50,0.20,0.10,0.00,1.40,0.80,0.10,0.02,0.0,0.0,0.05,0.0,0.0,0.0,0.0,0.40,0.0,0.30,0.0,0.0,0.40,0.02,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.10,0.0,0.20]],
	"黏土": [0.7, [0.10,0.20,0.20,0.15,0.10,0.08,0.10,0.20,0.15,0.05,0.0,0.20,0.0,0.03,0.01,0.0,0.05,0.30,0.15,0.10,0.01,0.02,0.02,0.05,0.10,0.40,0.15,0.10,0.10,0.10,0.05,0.10,0.05]],
}
const ESOL3 := [8.0,0.4,2.0,3.0,0.05,9.0,1.2,0.6,0.08,0.03,12.0,0.2,0.002,0.004,0.003,0.0005,0.5,0.1,10.0,0.05,0.001,1.5,0.8,0.01,0.0002,0.001,0.3,0.0005,0.05,0.02,0.4,0.05,0.3]
const WK3 := 0.0006
const CHEM_SCALE := 1500.0   # world.html 逐分钟率折算到逐日步(数值验证调)
const RIVER_K := 0.4         # 径流带走溶解元素的比例系数
var rockE3 := PackedFloat64Array()    # 局部层岩石源(NE,守恒)
var subPoolE3 := PackedFloat64Array() # 俯冲池(供 L7/海洋汇)

func setup(w, g) -> void:
	world = w
	geo = g
	body = BodyS.new()
	_build()

func _build() -> void:
	# 每地点全态:岩性(LITHO 6种)/高程/土壤容量/土壤水/湖/地下水。岩性按地形配(洞穴=石灰岩)
	locs = [
		_mkloc("赤道海岸", 2.0, 150.0, "coast", "砂岩", 5.0, 0.8),
		_mkloc("温带林", 40.0, 150.0, "forest", "黏土", 200.0, 1.6),
		_mkloc("高山", 42.0, 156.0, "mountain", "花岗岩", 3500.0, 0.4),
		_mkloc("极地苔原", 76.0, 150.0, "tundra", "玄武岩", 100.0, 0.6),
		_mkloc("洞穴", 40.0, 150.0, "cave", "石灰岩", 150.0, 0.0),
	]
	routes = [[0, 1, 600], [1, 2, 400], [1, 4, 120], [1, 3, 1200]]
	# 下游:高→低(高山→林→海岸),供 L4 河流搬运
	locs[2]["down"] = 1; locs[1]["down"] = 0; locs[3]["down"] = 1
	rockE3 = PackedFloat64Array(); rockE3.resize(Sim.NE); rockE3.fill(1.0e6)
	subPoolE3 = PackedFloat64Array(); subPoolE3.resize(Sim.NE)
	for L in locs: L["dis"] = _z33(); L["dep"] = _z33()
	_push_boundary()
	_update_temps()
	for L in locs: _soil_step(L)

func _z33() -> Array:
	var a := []; a.resize(Sim.NE); a.fill(0.0); return a

const SNOW_T := 2.0   # 雪线温度(≤此值降水成雪,>此值消融)
# 水文气象(逐小时):雪/冰川积累与消融(融雪补水)、海浪(风²)、风暴对流电荷→闪电(确定性张弛)
func _weather_step(L: Dictionary) -> void:
	if L["kind"] == "cave": return
	var k: int = _cell(L["lat"], L["lon"])
	var precip: float = world.P[k]
	var temp: float = float(L["envTemp"])
	if temp <= SNOW_T:
		L["snow"] = float(L["snow"]) + precip * 0.5            # 降水成雪
	else:
		var melt: float = min(float(L["snow"]), (temp - SNOW_T) * 0.03)
		L["snow"] = float(L["snow"]) - melt
		L["Soil"] = min(float(L["soilCap"]), float(L["Soil"]) + melt * 0.5)  # 融雪补土壤水
	if float(L["snow"]) > 40.0: L["glacier"] = float(L["glacier"]) + 0.01    # 久雪成冰川
	# 风(昼夜温差/对流驱动)+ 海岸海浪(风²弛豫)
	var wind: float = clampf(abs(temp - float(L["meanTemp"])) * 0.3 + 0.2, 0.0, 2.0)
	L["wind"] = wind
	if L["kind"] == "coast": L["wave"] = float(L["wave"]) * 0.9 + wind * wind * 0.1
	# 风暴电荷(暖湿对流)→ 跨阈放电(确定性张弛)
	var conv: float = clampf((temp - 15.0) / 15.0, 0.0, 1.0) * clampf(precip, 0.0, 1.2)
	L["charge"] = float(L["charge"]) + conv * 0.1
	if float(L["charge"]) > 1.0:
		L["charge"] = 0.0
		L["lightning"] = int(L["lightning"]) + 1

# 逐地点元素化学(逐日):本地岩性 LITHO 驱动碳酸风化(岩→溶)→溶解度沉淀(溶→沉成矿)。逐元素守恒(rockE3→dis→dep)
func _chem_step(L: Dictionary) -> void:
	if L["kind"] == "cave": return
	var lith = ELITHO[L["lith"]]
	var rate: float = lith[0]
	var vec = lith[1]
	var k: int = _cell(L["lat"], L["lon"])
	var act: float = rate * clampf(world.P[k], 0.0, 1.5) * clampf((float(L["envTemp"]) + 5.0) / 25.0, 0.1, 1.5) * max(0.1, world.globalCO2 / 2.0)
	var dis: Array = L["dis"]
	var dep: Array = L["dep"]
	var water: float = max(0.1, float(L["Soil"]) / max(0.01, float(L["soilCap"])))
	for e in Sim.NE:
		var rel: float = min(WK3 * float(vec[e]) * act * CHEM_SCALE, rockE3[e])
		rockE3[e] -= rel
		dis[e] += rel
		var cap: float = float(ESOL3[e]) * water
		if dis[e] > cap:
			var pp: float = (dis[e] - cap) * 0.3
			dis[e] -= pp; dep[e] += pp

# 河流(逐日):径流把溶解元素顺流带向下游(高→低),下游富集上游风化产物。守恒(loc→loc)
func _river_step() -> void:
	for L in locs:
		var dn: int = L["down"]
		if dn < 0: continue
		var frac: float = clampf(float(L["runoffAcc"]) * RIVER_K, 0.0, 0.3)
		L["runoffAcc"] = 0.0
		if frac <= 0.0: continue
		var dis: Array = L["dis"]
		var ddn: Array = locs[dn]["dis"]
		for e in Sim.NE:
			var mv: float = dis[e] * frac
			dis[e] -= mv; ddn[e] += mv

func _mkloc(nm: String, lat: float, lon: float, kind: String, lith: String, elev: float, soilCap: float) -> Dictionary:
	return {"name": nm, "lat": lat, "lon": lon, "kind": kind, "lith": lith, "elev": elev,
		"soilCap": soilCap, "Soil": soilCap * 0.5, "Lake": 0.0, "GW": 2.0,
		"runoff": 0.0, "runoffAcc": 0.0, "spring": 0.0, "down": -1, "envTemp": 15.0, "meanTemp": 15.0,
		"snow": 0.0, "glacier": 0.0, "charge": 0.0, "lightning": 0, "wind": 0.0, "wave": 0.0,
		"food": 0.0, "water": 0.0, "foodCap": 0.0, "waterCap": 0.0}

# 土壤水平衡(逐小时):降水补给→蒸发→满溢径流→深渗补地下水→地下水慢基流(旱季泉)
func _soil_step(L: Dictionary) -> void:
	if L["kind"] == "cave":
		L["waterCap"] = 60.0; L["water"] = 60.0; return   # 洞穴滴水:微量恒定
	var k: int = _cell(L["lat"], L["lon"])
	var precip: float = world.P[k]
	var temp: float = L["envTemp"]
	L["Soil"] = float(L["Soil"]) + precip * 0.6 - (max(0.0, temp) * 0.012 + 0.03)
	var runoff := 0.0
	if L["Soil"] > L["soilCap"]: runoff = float(L["Soil"]) - float(L["soilCap"]); L["Soil"] = L["soilCap"]
	if L["Soil"] < 0.0: L["Soil"] = 0.0
	var deep := 0.0
	if float(L["Soil"]) > 0.7 * float(L["soilCap"]):
		deep = 0.03 * (float(L["Soil"]) - 0.7 * float(L["soilCap"])); L["Soil"] = float(L["Soil"]) - deep; L["GW"] = float(L["GW"]) + deep
	var spring: float = 0.015 * float(L["GW"]); L["GW"] = float(L["GW"]) - spring
	L["runoff"] = runoff; L["spring"] = spring
	L["runoffAcc"] = float(L["runoffAcc"]) + runoff   # 累积径流,供河流逐日搬运
	# 可饮水(mL)= 土壤饱和度×蓄水 + 地下水基流泉(旱季缓冲) + 海岸取水
	var sat: float = float(L["Soil"]) / max(0.01, float(L["soilCap"]))
	var wcap: float = sat * 2000.0 + spring * 8000.0 + (500.0 if L["kind"] == "coast" else 0.0)
	L["waterCap"] = wcap
	L["water"] = min(float(L["water"]) + wcap * 0.12, wcap)

# PushBoundary:全球行星某(纬,经)的有效气温 → 地点日均环境温(地形调制)
func _mean_temp(L: Dictionary) -> float:
	var j: int = clampi(int((float(L["lat"]) + 90.0) / 180.0 * Sim.NLat), 0, Sim.NLat - 1)
	var i: int = ((int(float(L["lon"]) / 360.0 * Sim.NLon)) % Sim.NLon + Sim.NLon) % Sim.NLon
	var t: float = world.Teff(j, i) - float(L["elev"]) * 0.0065   # 高程递减(6.5℃/km,所有地点)
	match L["kind"]:
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
	var snowCool: float = clampf(float(L["snow"]) / 8.0, 0.0, 1.0) * 4.0   # 雪盖反照率致冷(正反馈)
	return float(L["meanTemp"]) + amp * (sf - 0.35) - snowCool

func _update_temps() -> void:
	for L in locs: L["envTemp"] = _inst_temp(L)

func _push_boundary() -> void:
	for L in locs:
		L["meanTemp"] = _mean_temp(L)
		# 资源:食物=当地植被(全球 N 生物量) + 海岸海产;水=降水(淡水)。按容量再生
		var k: int = _cell(L["lat"], L["lon"])
		var veg: float = world.N[k] + world.H[k] * 0.5     # 生产者+食草(可猎)
		if L["kind"] == "coast": veg += 8.0                # 海产
		L["foodCap"] = veg * 60.0                          # kcal 容量
		L["food"] = min(float(L["food"]) + L["foodCap"] * 0.04, L["foodCap"])  # 水由 _soil_step 算

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
			for L in locs: _soil_step(L)              # 土壤水/地下水平衡
			for L in locs: _weather_step(L)           # 雪冰/海浪/风暴闪电
			if auto_forage and traveling == null: forage(1)
			var env: float = cur_loc()["envTemp"]
			var act: float = 1.4 if traveling != null else 1.0   # 旅途更耗
			body.step(1, env, act)
		if total % 1440 == 0:                        # 每天:逐地点元素化学 + 河流下游搬运
			for L in locs: _chem_step(L)
			_river_step()
