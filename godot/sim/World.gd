class_name World
extends RefCounted
# ====================================================================
# 全球演化 · 纯模拟内核(从 evolve.html 逐句移植)
# 不碰渲染 / 不依赖场景 —— 可被 validate.gd headless 单独跑、对数。
# 网格 [j][i]:j=纬度(0=南),i=经度。
# ====================================================================

# ---------- 气候底座(planet.html 的验证过模型) ----------
const NLat := 18
const NLon := 24
const YEAR := 365
const TILT := 23.44
const EQX := 80
const LandInertia := 0.20
const SeaCouple := 0.15
const Adv := 0.18
const OceanInertia := 0.012
const OceanHeatMix := 0.05
const SalRate := 0.004
const SalMix := 0.008
const GyreCool := 0.08
const MOCgain := 0.8
const MOCheat := 0.12
const ROT_H := 24.0
const OMEGA := 2.0 * PI / (ROT_H * 3600.0)
const FRIC := 8e-5
const LMIN := 120.0
const LMAX := 240.0

var MOC := 1.0
var FRESH := 0.0
var UMAX := 1.0
var WATERWORLD := false
var land_mask = null   # 由 Geo 注入的粗海陆 mask(真大陆);为 null 时退回经度矩形带

var Land := []
var T := []
var S := []
var SAL := []
var P := []
var U := []
var PR := []
var FR := []

# ---------- 生命层 ----------
var N := []
var Hab := []
var Topt := []
var Salt := []
var Dry := []
var spId := []
var Sym := []
var Seg := []
var Limb := []
var Axis := []
const morphK := 0.04
const morphCost := 0.02
const MGATE := 0.35
const MGW := 0.25

var phylo := []          # 谱系档案:每项 {id,parent,bornY,deathY,Topt,land}
var nextSp := 1
var extEMA := 1.0
var massExt := []        # 大灭绝事件:{ky,lost,cause}

const SEED := 0.05
const IGNITE := 0.45
const Kmax := 40.0
const rb := 0.9
const rd := 0.12
const MOVE := 0.12
const FITW := 14.0
const SALTW := 2.5
const DRYW := 0.4
const BARRIER := 0.04
const TBUCKET := 9.0

var climCool := 0.0
const ICE_AMP := 22.0
const ICE_PERIOD := 14

var globalCO2 := 2.0
const CO2ref := 2.0
const cGhouse := 2.2
const volcOut := 0.3
const weatherK := 0.2
const bioK := 0.1
const VPULSE_T := 40
const VPULSE_A := 3.0

var geoT := 0

func _init() -> void:
	UMAX = 1.0
	for j in NLat:
		UMAX = max(UMAX, abs(uband(latof(j))))

# ---------- 几何 / 物理小函数 ----------
func latof(j: int) -> float: return -90.0 + (j + 0.5) * 180.0 / NLat
func lonof(i: int) -> float: return (i + 0.5) * 360.0 / NLon
func isLand(i: int) -> bool:
	if WATERWORLD: return false
	var lo := lonof(i)
	return lo >= LMIN and lo <= LMAX
func decl(d: int) -> float: return TILT * sin(2.0 * PI * (d - EQX) / YEAR)
func eqT(lat: float, dc: float) -> float: return 30.0 - 65.0 * (1.0 - cos((lat - dc) * 0.9 * PI / 180.0))
func cellV(lat: float) -> float:
	var a: float = abs(lat)
	var s := 1.0 if lat >= 0.0 else -1.0
	var v := -2.0 if a < 30.0 else (2.0 if a < 60.0 else -1.5)
	return v * s
func uband(lat: float) -> float: return 2.0 * OMEGA * sin(lat * PI / 180.0) * cellV(lat) / FRIC
func precipBand(lat: float, dc: float) -> float:
	var d: float = abs(lat - dc * 0.5)
	var a: float = abs(lat)
	if d < 12.0: return 1.0
	if a > 22.0 and a < 38.0: return 0.1
	if a >= 45.0 and a < 68.0: return 0.7
	if a >= 78.0: return 0.1
	return 0.4

# ---------- 网格工具 ----------
func grid(v) -> Array:
	var g := []
	for j in NLat:
		var row := []
		for i in NLon: row.append(v)
		g.append(row)
	return g
func copy2(a: Array) -> Array:
	var g := []
	for r in a: g.append((r as Array).duplicate())
	return g
func nearSea(j: int, i: int, dc: float) -> float:
	for d in range(1, NLon / 2 + 1):
		var il := posmod(i - d, NLon)
		var ir := (i + d) % NLon
		if not Land[j][il]: return S[j][il]
		if not Land[j][ir]: return S[j][ir]
	return max(-2.0, eqT(latof(j), dc))

# ---------- 气候一日 ----------
func stepDay(d: int) -> void:
	var dc := decl(d)
	var s0 := copy2(S)
	var sl0 := copy2(SAL)
	for j in NLat:
		var jl: int = max(0, j - 1)
		var jr: int = min(NLat - 1, j + 1)
		var eqO: float = max(-2.0, eqT(latof(j), dc))
		for i in NLon:
			if Land[j][i]: continue
			S[j][i] += OceanInertia * (eqO - s0[j][i]) + OceanHeatMix * ((s0[jl][i] + s0[jr][i]) / 2.0 - s0[j][i])
			var ev: float = max(0.0, s0[j][i]) / 30.0
			SAL[j][i] += SalRate * (ev - 1.6 * precipBand(latof(j), dc)) + SalMix * ((sl0[jl][i] + sl0[jr][i]) / 2.0 - sl0[j][i])
	# 大洋经向翻转环流(MOC)
	var dens := 0.0
	var n := 0
	for j in NLat:
		if abs(latof(j)) < 50.0: continue
		for i in NLon:
			if Land[j][i]: continue
			dens += 0.8 * (SAL[j][i] - 34.5) - 0.12 * (S[j][i] - 10.0) - FRESH
			n += 1
	var tgt: float = max(0.0, (dens / n) * MOCgain if n > 0 else 0.0)
	MOC += 0.05 * (tgt - MOC)
	for j in NLat:
		var a: float = abs(latof(j))
		for i in NLon:
			if Land[j][i]: continue
			if a >= 50.0: S[j][i] += MOCheat * MOC
			elif a < 35.0: S[j][i] -= MOCheat * MOC * 0.5
	# 大气温度
	for j in NLat:
		var eqA := eqT(latof(j), dc)
		for i in NLon:
			if Land[j][i]: T[j][i] += LandInertia * (eqA - T[j][i])
			else: T[j][i] += SeaCouple * (S[j][i] - T[j][i])
	# 纬向平流
	var t1 := copy2(T)
	for j in NLat:
		var u := uband(latof(j))
		var w: float = min(1.0, abs(u) / UMAX)
		var up := -1 if u > 0.0 else 1
		for i in NLon:
			var iu := posmod(i + up, NLon)
			T[j][i] += Adv * w * (t1[j][iu] - t1[j][i])
			U[j][i] = u
	# 降水
	for j in NLat:
		var base := precipBand(latof(j), dc)
		for i in NLon:
			var p := base
			if Land[j][i]:
				var dT: float = T[j][i] - nearSea(j, i, dc)
				p *= 1.0 + 0.5 * max(0.0, min(1.0, dT / 8.0)) - 0.4 * max(0.0, min(1.0, -dT / 8.0))
			P[j][i] = max(0.0, min(1.2, p))
	# 西边界流增冷
	for j in NLat:
		var a: float = abs(latof(j))
		if a < 18.0 or a > 42.0: continue
		for i in NLon:
			if Land[j][i]: continue
			if Land[j][(i + 1) % NLon]: S[j][i] -= GyreCool
	# 气压带 + 锋面
	var PBELT := 20.0
	var PKT := 2.0
	for j in NLat:
		var belt := -PBELT * cos(2.0 * PI * abs(latof(j)) / 60.0)
		var m := 0.0
		for i in NLon: m += T[j][i]
		m /= NLon
		for i in NLon: PR[j][i] = 1013.0 + belt - PKT * (T[j][i] - m)
	for j in NLat:
		var jl: int = max(0, j - 1)
		var jr: int = min(NLat - 1, j + 1)
		for i in NLon: FR[j][i] = abs(T[jr][i] - T[jl][i]) / 2.0

func initClimate() -> void:
	Land = grid(false); T = grid(0.0); S = grid(0.0); SAL = grid(34.5)
	P = grid(0.0); U = grid(0.0); PR = grid(1013.0); FR = grid(0.0)
	for j in NLat:
		var lat := latof(j)
		for i in NLon:
			Land[j][i] = false if WATERWORLD else (land_mask[j][i] if land_mask != null else isLand(i))
			T[j][i] = eqT(lat, 0.0)
			S[j][i] = max(-2.0, eqT(lat, 0.0))

# ---------- 生命层 ----------
func Teff(j: int, i: int) -> float:
	return T[j][i] + cGhouse * (globalCO2 - CO2ref) - climCool * pow(abs(latof(j)) / 90.0, 1.3) * 2.0
func updateHab() -> void:
	for j in NLat:
		for i in NLon:
			var tFit := exp(-pow((Teff(j, i) - 25.0) / 16.0, 2.0))
			var water: float = P[j][i] if Land[j][i] else 1.0
			Hab[j][i] = clampf(tFit * sqrt(max(0.0, water)), 0.0, 1.0)
func envSalt(j: int, i: int) -> float: return 0.0 if Land[j][i] else SAL[j][i]
func envDry(j: int, i: int) -> float: return (1.0 - P[j][i]) if Land[j][i] else 0.0

func stepLife(dt: float) -> void:
	updateHab()
	var aT := 1.0 - exp(-0.05 * dt)
	var aS := 1.0 - exp(-0.04 * dt)
	var aD := 1.0 - exp(-0.05 * dt)
	# 起源:性状=当地环境
	for j in NLat:
		for i in NLon:
			if Hab[j][i] > IGNITE and N[j][i] < SEED:
				N[j][i] = SEED; Topt[j][i] = Teff(j, i); Salt[j][i] = envSalt(j, i); Dry[j][i] = envDry(j, i)
	# 增长 + 本地适应 + 形态发育
	for j in NLat:
		for i in NLon:
			if N[j][i] <= 0.0: continue
			var fT := exp(-pow((Topt[j][i] - Teff(j, i)) / FITW, 2.0))
			var fS := exp(-pow((Salt[j][i] - envSalt(j, i)) / SALTW, 2.0))
			var fD := exp(-pow((Dry[j][i] - envDry(j, i)) / DRYW, 2.0))
			var fit := fT * fS * fD
			var K: float = max(1e-3, Kmax * Hab[j][i])
			var r0 = rb * Hab[j][i] * fit - rd
			var nn = N[j][i]
			if r0 > 1e-6: N[j][i] = K / (1.0 + (K / nn - 1.0) * exp(-r0 * dt))
			else: N[j][i] = max(0.0, nn * exp(r0 * dt))
			Topt[j][i] += aT * (Teff(j, i) - Topt[j][i])
			Salt[j][i] += aS * (envSalt(j, i) - Salt[j][i])
			Dry[j][i] += aD * (envDry(j, i) - Dry[j][i])
			var sizeP := clampf(N[j][i] / Kmax, 0.0, 1.0)
			var moveP := clampf(0.3 + 0.45 * abs(latof(j)) / 90.0 + 0.3 * climCool / ICE_AMP, 0.0, 1.0)
			var gS := clampf((Sym[j][i] - MGATE) / MGW, 0.0, 1.0)
			var gG := clampf((Seg[j][i] - MGATE) / MGW, 0.0, 1.0)
			Sym[j][i] = clampf(Sym[j][i] + morphK * (moveP - Sym[j][i] - morphCost), 0.0, 1.0)
			Seg[j][i] = clampf(Seg[j][i] + morphK * (gS * moveP - Seg[j][i] - morphCost), 0.0, 1.0)
			Limb[j][i] = clampf(Limb[j][i] + morphK * (gG * moveP - Limb[j][i] - morphCost), 0.0, 1.0)
			Axis[j][i] = clampf(Axis[j][i] + morphK * (gS * sizeP - Axis[j][i] - morphCost), 0.0, 1.0)
	# 四邻扩散 + 带性状迁移(守恒)
	var flow := grid(0.0); var fTo := grid(0.0); var fSa := grid(0.0); var fDr := grid(0.0)
	var f := clampf(MOVE * dt / 10.0, 0.0, 0.24)
	for j in NLat:
		for i in NLon:
			var nv = N[j][i]
			if nv <= 0.0: continue
			var nb := [[j, (i + 1) % NLon], [j, posmod(i - 1, NLon)]]
			if j > 0: nb.append([j - 1, i])
			if j < NLat - 1: nb.append([j + 1, i])
			for ji in nb:
				var bj: int = ji[0]; var bi: int = ji[1]
				var bar := BARRIER if Land[j][i] != Land[bj][bi] else 1.0
				var mv: float = f * bar * max(0.0, (nv - N[bj][bi]) * 0.5) * Hab[bj][bi]
				flow[j][i] -= mv; flow[bj][bi] += mv
				fTo[bj][bi] += mv * Topt[j][i]; fSa[bj][bi] += mv * Salt[j][i]; fDr[bj][bi] += mv * Dry[j][i]
	for j in NLat:
		for i in NLon:
			if flow[j][i] > 0.0:
				var tot = N[j][i] + flow[j][i]
				if tot > 0.0:
					Topt[j][i] = (Topt[j][i] * N[j][i] + fTo[j][i]) / tot
					Salt[j][i] = (Salt[j][i] * N[j][i] + fSa[j][i]) / tot
					Dry[j][i] = (Dry[j][i] * N[j][i] + fDr[j][i]) / tot
			N[j][i] = max(0.0, N[j][i] + flow[j][i])

# ---------- 物种 / 谱系 / 大灭绝 ----------
func extinctionCause() -> String:
	if globalCO2 > CO2ref * 2.0: return "🌋暖室·海洋酸化"
	if climCool > 12.0: return "❄️大冰期"
	if climCool > 6.0: return "❄️冰期降温"
	return "环境胁迫"
func massExtinctionCheck(ext: int) -> void:
	var alive := phylo.filter(func(p): return p["deathY"] < 0).size()
	var thr: float = max(max(2.0, alive * 0.3), extEMA * 2.2)
	var last: float = massExt[-1]["ky"] if massExt.size() > 0 else -1e9
	if ext > thr and geoT > 1 and (geoT - last) >= ICE_PERIOD * 0.4:
		massExt.append({"ky": geoT, "lost": ext, "cause": extinctionCause()})
		if massExt.size() > 40: massExt.pop_front()
	extEMA += 0.12 * (ext - extEMA)

func updateSpecies() -> int:
	var comp := grid(-1)
	var nc := 0
	var members := []
	for j in NLat:
		for i in NLon:
			if comp[j][i] >= 0 or N[j][i] <= SEED: continue
			var st := [[j, i]]
			comp[j][i] = nc
			var mem := []
			while st.size() > 0:
				var c = st.pop_back()
				var cj: int = c[0]; var ci: int = c[1]
				mem.append(c)
				var nb := [[cj, (ci + 1) % NLon], [cj, posmod(ci - 1, NLon)]]
				if cj > 0: nb.append([cj - 1, ci])
				if cj < NLat - 1: nb.append([cj + 1, ci])
				for nn in nb:
					var nj: int = nn[0]; var ni: int = nn[1]
					if comp[nj][ni] < 0 and N[nj][ni] > SEED and Land[nj][ni] == Land[cj][ci] and floor(Topt[nj][ni] / TBUCKET) == floor(Topt[cj][ci] / TBUCKET):
						comp[nj][ni] = nc; st.append(nn)
			members.append(mem); nc += 1
	# 每个连通分量找它最大的旧物种(继承祖先)
	var compOld := []
	for c in nc:
		var cnt := {}
		for m in members[c]:
			var o: int = spId[m[0]][m[1]]
			if o > 0: cnt[o] = cnt.get(o, 0) + 1
		var best := 0; var bo := 0
		for k in cnt:
			if cnt[k] > best: best = cnt[k]; bo = k
		compOld.append(bo)
	# 大分量先处理(继承id),裂出的次要分量记为新种(异域分支)
	var order := []
	for c in nc: order.append(c)
	order.sort_custom(func(a, b): return members[a].size() > members[b].size())
	var seen := {}
	for c in order:
		var old: int = compOld[c]
		var s := 0.0; var w := 0.0
		for m in members[c]:
			s += Topt[m[0]][m[1]] * N[m[0]][m[1]]; w += N[m[0]][m[1]]
		var mean := s / w if w > 0.0 else 0.0
		var land = Land[members[c][0][0]][members[c][0][1]]
		var id: int
		if old == 0:
			id = nextSp; nextSp += 1
			phylo.append({"id": id, "parent": -1, "bornY": geoT, "deathY": -1, "Topt": snappedf(mean, 0.1), "land": land})
		elif not seen.has(old):
			id = old; seen[old] = true
		else:
			id = nextSp; nextSp += 1
			phylo.append({"id": id, "parent": old, "bornY": geoT, "deathY": -1, "Topt": snappedf(mean, 0.1), "land": land})
		for m in members[c]: spId[m[0]][m[1]] = id
	# 灭绝判定
	var live := {}
	for j in NLat:
		for i in NLon:
			if spId[j][i] > 0 and N[j][i] > SEED: live[spId[j][i]] = true
	var ext := 0
	for p in phylo:
		if p["deathY"] < 0 and not live.has(p["id"]): p["deathY"] = geoT; ext += 1
	for j in NLat:
		for i in NLon:
			if N[j][i] <= SEED: spId[j][i] = 0
	if phylo.size() > 2000: phylo = phylo.slice(phylo.size() - 2000)
	return ext

func carbonStep() -> void:
	var bio := 0.0
	for j in NLat:
		for i in NLon: bio += N[j][i]
	var ghouse := cGhouse * (globalCO2 - CO2ref)
	var warm := clampf(1.0 + 0.06 * ghouse, 0.4, 2.5)
	var src := volcOut + (VPULSE_A if (geoT > 0 and geoT % VPULSE_T == 0) else 0.0)
	var weather := weatherK * (globalCO2 / CO2ref) * warm
	var pump := bioK * clampf(bio / 5000.0, 0.0, 1.5)
	globalCO2 = max(0.1, globalCO2 + src - weather - pump)

func stepGeo() -> void:
	geoT += 1
	climCool = ICE_AMP * clampf(sin(2.0 * PI * geoT / ICE_PERIOD), 0.0, 1.0)
	carbonStep()
	massExtinctionCheck(updateSpecies())

# ---------- 体制(门级)从形态变量涌现 —— 供面板 ----------
func bodyPlan(j: int, i: int) -> String:
	var sym: float = Sym[j][i]; var seg: float = Seg[j][i]; var limb: float = Limb[j][i]; var axis: float = Axis[j][i]
	if sym < 0.4: return "刺胞"
	if axis > 0.5: return "脊索"
	if seg > 0.5 and limb > 0.4: return "节肢"
	if seg > 0.5: return "环节"
	return "蠕虫"

# ---------- 启动:气候预热 ----------
func spinUp() -> void:
	initClimate()
	N = grid(0.0); Hab = grid(0.0); Topt = grid(0.0); Salt = grid(0.0); Dry = grid(0.0)
	spId = grid(0); Sym = grid(0.0); Seg = grid(0.0); Limb = grid(0.0); Axis = grid(0.0)
	phylo = []; nextSp = 1; extEMA = 1.0; massExt = []
	MOC = 1.0; geoT = 0; climCool = 0.0; globalCO2 = 2.0
	for d in 3 * YEAR: stepDay(d % YEAR)
