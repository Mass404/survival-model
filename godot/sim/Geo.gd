class_name Geo
extends RefCounted
# v9 像素星球(移植自 evolve-game/planet.gd):大陆核心 CORES + fbm 噪声 → 高程场,
# SEA=0.82 定海陆(数值扫描过,约三成陆)。同一套确定性生成 = 同一颗设计过的星球。
# 一张地理同时喂:显示层(256×128 细像素的高程/纹理)+ 模拟层(18×24 粗海陆 mask)。

const COLS := 256
const ROWS := 128
const RXf := 44.0       # 地形参考网格宽(归一化基准:改 COLS 只变精细度,不变大陆布局)
const RYf := 22.0
const SEA := 0.82       # 海平面阈值

# 大陆核心(高斯隆起):i/j 在参考网格空间,a 振幅,s 展度
const CORES := [
	{"i": 11.0, "j": 8.0,  "a": 1.05, "s": 60.0},
	{"i": 28.0, "j": 14.0, "a": 0.95, "s": 80.0},
	{"i": 36.0, "j": 7.0,  "a": 0.7,  "s": 42.0},
	{"i": 19.0, "j": 18.0, "a": 0.62, "s": 48.0},
	{"i": 6.0,  "j": 16.0, "a": 0.5,  "s": 30.0},
]

var elev := PackedFloat32Array()    # 高程,idx = j*COLS + i(j=0 在北/顶)
var shade := PackedFloat32Array()   # 地表纹理明暗(静态 fbm)
var mnoise := PackedFloat32Array()  # 湿度噪声分量(静态 fbm,叠到活降水上)
var sealevel := SEA
var emin := 0.0
var emax := 1.0

func _hash(i: float, j: float) -> float:
	var s := sin(i * 127.1 + j * 311.7) * 43758.5453
	return s - floor(s)
func _vnoise(px: float, py: float) -> float:
	var xi := floorf(px)
	var yi := floorf(py)
	var xf := px - xi
	var yf := py - yi
	var tl := _hash(xi, yi)
	var tr := _hash(xi + 1.0, yi)
	var bl := _hash(xi, yi + 1.0)
	var br := _hash(xi + 1.0, yi + 1.0)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	return lerpf(lerpf(tl, tr, u), lerpf(bl, br, u), v)
func _fbm(px: float, py: float) -> float:
	var s := 0.0
	var a := 0.5
	var f := 1.0
	for o in 4:
		s += a * _vnoise(px * f, py * f)
		f *= 2.0
		a *= 0.5
	return s
func _field_fij(fi: float, fj: float) -> float:
	var v := 0.0
	for c in CORES:
		var d: float = (fi - c.i) * (fi - c.i) + (fj - c.j) * (fj - c.j)
		v += c.a * exp(-d / c.s)
	return v + 0.9 * (_fbm(fi * 0.28, fj * 0.28) - 0.5)

func generate() -> void:
	var sz := COLS * ROWS
	elev.resize(sz); shade.resize(sz); mnoise.resize(sz)
	emin = 1e9; emax = -1e9
	for j in ROWS:
		var fj := float(j) / float(ROWS - 1) * (RYf - 1.0)
		for i in COLS:
			var fi := float(i) / float(COLS - 1) * (RXf - 1.0)
			var idx := j * COLS + i
			var e := _field_fij(fi, fj)
			elev[idx] = e
			shade[idx] = 0.88 + 0.24 * (_fbm(fi * 0.7, fj * 0.7) - 0.5)
			mnoise[idx] = _fbm(fi * 0.35 + 20.0, fj * 0.35)
			emin = minf(emin, e); emax = maxf(emax, e)

# 双线性采样高程(平面图,边缘夹紧不环绕)
func elev_at(lat: float, lon: float) -> float:
	var fj := (90.0 - lat) / 180.0 * (ROWS - 1)
	var fi := lon / 360.0 * (COLS - 1)
	var j0 := clampi(int(floor(fj)), 0, ROWS - 1)
	var i0 := clampi(int(floor(fi)), 0, COLS - 1)
	var j1 := clampi(j0 + 1, 0, ROWS - 1)
	var i1 := clampi(i0 + 1, 0, COLS - 1)
	var tj := clampf(fj - j0, 0.0, 1.0)
	var ti := clampf(fi - i0, 0.0, 1.0)
	var a := lerpf(elev[j0 * COLS + i0], elev[j0 * COLS + i1], ti)
	var b := lerpf(elev[j1 * COLS + i0], elev[j1 * COLS + i1], ti)
	return lerpf(a, b, tj)

func is_land(lat: float, lon: float) -> bool:
	return elev_at(lat, lon) > SEA

# 降采样成 sim 的粗海陆 mask(在给定海平面阈值 sea 下):每个粗格 3×3 子样多数表决
func coarse_land_at(nlat: int, nlon: int, sea: float) -> Array:
	var mask := []
	for j in nlat:
		var row := []
		var clat := -90.0 + (j + 0.5) * 180.0 / nlat
		for i in nlon:
			var clon := (i + 0.5) * 360.0 / nlon
			var cnt := 0
			for sj in [-0.3, 0.0, 0.3]:
				for si in [-0.3, 0.0, 0.3]:
					var la: float = clampf(clat + sj * 180.0 / nlat, -89.9, 89.9)
					var lo: float = clampf(clon + si * 360.0 / nlon, 0.0, 359.9)
					if elev_at(la, lo) > sea: cnt += 1
			row.append(cnt >= 5)
		mask.append(row)
	return mask

func coarse_land(nlat: int, nlon: int) -> Array:
	return coarse_land_at(nlat, nlon, SEA)

# ---------- 构造动力(逐地质年):火山热点喷发抬升(张弛)+ 侵蚀回落,确定性 ----------
var magmaP := 0.0
var hotspots := PackedInt32Array()
var _eros := PackedFloat32Array()
const ERUPT_THR := 6.0     # 岩浆压阈值(每 ~6 地质年喷一次)
const MAGMA_RATE := 1.0
const LAVA := 0.02         # 喷发抬升量(热点)
const EROS_K := 0.006      # 侵蚀率(陆地高程向邻均回落)

func _init_tect() -> void:
	hotspots = PackedInt32Array()
	for c in CORES:
		var gx: int = clampi(int(float(c.i) / RXf * COLS), 0, COLS - 1)
		var gy: int = clampi(int(float(c.j) / RYf * ROWS), 0, ROWS - 1)
		hotspots.append(gy * COLS + gx)
	_eros.resize(COLS * ROWS)
	_init_plates()

# ---------- 板块构造:网格划成 NPLATE 个板块(Voronoi),各有确定性漂移速度 ----------
# 板块构造的定义性特征=地质活动集中在板块边界:汇聚边界造山(喜马拉雅/安第斯)、离散边界裂谷成新洋(中脊)。
const NPLATE := 7
const BOUND_K := 0.005     # 边界构造强度(汇聚抬升/离散沉降,每地质年)
var plate := PackedInt32Array()    # 每格板块 id
var plateV := []                   # 每板块漂移速度向量 [vx,vy](确定性,黄金角散布)

func _init_plates() -> void:
	var seeds := []
	plateV = []
	for p in NPLATE:
		var sx: int = int((0.10 + 0.80 * fmod(p * 0.3714, 1.0)) * COLS)
		var sy: int = int((0.12 + 0.76 * fmod(p * 0.6180, 1.0)) * ROWS)
		seeds.append([sx, sy])
		var ang: float = float(p) * 2.399963229728653   # 黄金角→方向散布(确定性)
		plateV.append([cos(ang), sin(ang)])
	plate = PackedInt32Array(); plate.resize(COLS * ROWS)
	for gy in ROWS:
		for gx in COLS:
			var best := 0; var bd := 1.0e18
			for p in NPLATE:
				var dx: int = gx - int(seeds[p][0])
				if dx > COLS / 2: dx -= COLS
				elif dx < -COLS / 2: dx += COLS          # 经度环绕
				var dy: int = gy - int(seeds[p][1])
				var d: float = float(dx * dx + dy * dy)
				if d < bd: bd = d; best = p
			plate[gy * COLS + gx] = best

func tectonics() -> int:
	if hotspots.is_empty(): _init_tect()
	var erupted := 0
	magmaP += MAGMA_RATE
	if magmaP >= ERUPT_THR:
		magmaP = 0.0
		for h in hotspots:
			var hy := h / COLS
			var hx := h % COLS
			elev[h] += LAVA
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0: continue
					var ny := clampi(hy + dy, 0, ROWS - 1)
					var nx := clampi(hx + dx, 0, COLS - 1)
					elev[ny * COLS + nx] += LAVA * 0.35
			erupted += 1
	# 板块边界构造(每地质年):汇聚边界→造山抬升、离散边界→裂谷沉降成新洋。地质活动集中在边界=板块构造定义性特征。
	for gy in ROWS:
		for gx in COLS:
			var idx := gy * COLS + gx
			var pa: int = plate[idx]
			var va: Array = plateV[pa]
			var up := 0.0
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var ny: int = gy + d[0]
				if ny < 0 or ny >= ROWS: continue
				var nx: int = (gx + d[1] + COLS) % COLS
				var pb: int = plate[ny * COLS + nx]
				if pb == pa: continue
				var vb: Array = plateV[pb]
				# 相对运动沿边界法向(x=d[1],y=d[0]):>0 汇聚(造山)、<0 离散(裂谷)
				up += (float(va[0]) - float(vb[0])) * float(d[1]) + (float(va[1]) - float(vb[1])) * float(d[0])
			if up != 0.0: elev[idx] += BOUND_K * up
	# 侵蚀:陆地高程向四邻均值回落(降 relief,确定性扩散)
	for idx in COLS * ROWS: _eros[idx] = elev[idx]
	for gy in ROWS:
		for gx in COLS:
			var idx := gy * COLS + gx
			if _eros[idx] <= SEA: continue
			var s := 0.0
			var n := 0
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var ny: int = gy + d[0]
				var nx: int = gx + d[1]
				if ny < 0 or ny >= ROWS or nx < 0 or nx >= COLS: continue
				s += _eros[ny * COLS + nx]; n += 1
			if n > 0: elev[idx] += EROS_K * (s / n - _eros[idx])
	return erupted
