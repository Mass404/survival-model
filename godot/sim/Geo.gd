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

# 降采样成 sim 的粗海陆 mask:每个粗格 3×3 子样多数表决
func coarse_land(nlat: int, nlon: int) -> Array:
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
					if is_land(la, lo): cnt += 1
			row.append(cnt >= 5)
		mask.append(row)
	return mask
