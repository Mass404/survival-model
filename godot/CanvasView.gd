class_name CanvasView
extends Control
# 正版 v9 像素星球皮 + 活模拟:Geo 给静态高程/纹理(256×128),逐像素直接索引(显示=地理同分辨率);
# 温度/湿度/冰盖改由 18×24 的活气候双线性采样驱动 → 同一颗星球,会随冰期/温室/生命变。
const Sim = preload("res://sim/World.gd")
const GeoS = preload("res://sim/Geo.gd")

var world
var geo
var view := "terrain"
var show_wind := false
var show_belt := false

var _img: Image
var _tex: ImageTexture
var _plat := PackedFloat32Array()
var _plon := PackedFloat32Array()
var _W := GeoS.COLS
var _H := GeoS.ROWS
var selected := Vector2i(-1, -1)   # 选中的粗格 (j,i)
var on_pick: Callable              # Main 注入:点击回调(j,i)

# 分析视图色带
const TEMP := [Color8(20,40,120), Color8(40,120,200), Color8(90,190,220), Color8(120,200,150), Color8(235,220,120), Color8(235,150,60), Color8(200,50,40)]
const PREC := [Color8(150,110,70), Color8(180,160,90), Color8(120,190,110), Color8(70,170,170), Color8(40,110,200)]
const LIFEC := [Color8(10,18,30), Color8(20,70,50), Color8(40,140,70), Color8(120,210,90), Color8(210,245,150)]
# v9 地表调色板
const DEEP := Color8(18,40,72)
const SHALLOW := Color8(92,178,190)
const SURF := Color8(156,223,221)
const BEACH := Color8(212,197,150)
const COLD_OCEAN := Color8(16,30,58)
const SNOW := Color8(234,239,246)
const TAIGA := Color8(46,84,60)
const TEMPER := Color8(88,142,72)
const GRASS := Color8(156,172,98)
const DESERT := Color8(206,186,120)
const RAIN := Color8(38,108,52)
const MTN := Color8(122,112,102)
const MTNSNOW := Color8(208,214,222)
const ICE := Color8(223,234,245)

func setup(w, g) -> void:
	geo = g
	_img = Image.create(_W, _H, false, Image.FORMAT_RGB8)
	_tex = ImageTexture.create_from_image(_img)
	var sz := _W * _H
	_plat.resize(sz); _plon.resize(sz)
	for gy in _H:
		var lat := 90.0 - (gy + 0.5) * 180.0 / _H
		for gx in _W:
			var idx := gy * _W + gx
			_plat[idx] = lat
			_plon[idx] = (gx + 0.5) * 360.0 / _W
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	world = w   # 最后设 → refresh/_draw 的 "world==null" 守卫真正兜住未就绪状态

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var lon := clampf(ev.position.x / size.x, 0.0, 0.999) * 360.0
		var lat := 90.0 - clampf(ev.position.y / size.y, 0.0, 0.999) * 180.0
		var j := clampi(int((lat + 90.0) / 180.0 * Sim.NLat), 0, Sim.NLat - 1)
		var i := ((int(lon / 360.0 * Sim.NLon)) % Sim.NLon + Sim.NLon) % Sim.NLon
		selected = Vector2i(j, i)
		if on_pick.is_valid(): on_pick.call(j, i)
		queue_redraw()

# ---------- 采样 / 工具 ----------
func _sample(field, lat: float, lon: float) -> float:
	var xj := (lat + 90.0) / 180.0 * Sim.NLat - 0.5
	var j0 := int(floor(xj))
	var tj := xj - j0
	j0 = clampi(j0, 0, Sim.NLat - 1)
	var j1 := clampi(j0 + 1, 0, Sim.NLat - 1)
	var xi := lon / 360.0 * Sim.NLon - 0.5
	var i0 := int(floor(xi))
	var ti := xi - i0
	i0 = ((i0 % Sim.NLon) + Sim.NLon) % Sim.NLon
	var i1 := (i0 + 1) % Sim.NLon
	var a := lerpf(field[j0 * Sim.NLon + i0], field[j0 * Sim.NLon + i1], ti)
	var b := lerpf(field[j1 * Sim.NLon + i0], field[j1 * Sim.NLon + i1], ti)
	return lerpf(a, b, tj)

func _nearest(lat: float, lon: float) -> Vector2i:
	var j := clampi(int((lat + 90.0) / 180.0 * Sim.NLat), 0, Sim.NLat - 1)
	var i := ((int(lon / 360.0 * Sim.NLon)) % Sim.NLon + Sim.NLon) % Sim.NLon
	return Vector2i(j, i)

func _teff(t: float, lat: float) -> float:
	return t + Sim.cGhouse * (world.globalCO2 - Sim.CO2ref) - world.climCool * pow(abs(lat) / 90.0, 1.3) * 2.0

func _ramp(stops: Array, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var n := stops.size() - 1
	var x := t * n
	var i: int = min(n - 1, int(floor(x)))
	return (stops[i] as Color).lerp(stops[i + 1], x - i)
func _tcol(v: float) -> Color: return _ramp(TEMP, (v + 40.0) / 80.0)
func _sp_color(id: int) -> Color:
	var h := fmod(id * 137.508, 360.0) / 360.0
	var s := 0.62
	var l := 0.56
	var q := (l * (1.0 + s)) if l < 0.5 else (l + s - l * s)
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))
func _hue(p: float, q: float, x: float) -> float:
	x = fmod(fmod(x, 1.0) + 1.0, 1.0)
	if x < 1.0 / 6.0: return p + (q - p) * 6.0 * x
	if x < 1.0 / 2.0: return q
	if x < 2.0 / 3.0: return p + (q - p) * (2.0 / 3.0 - x) * 6.0
	return p

# ---------- 地表(v9 皮 + 活气候)----------
func _terrain_color(idx: int) -> Color:
	var e: float = geo.elev[idx]
	var lat: float = _plat[idx]
	var lon: float = _plon[idx]
	var tt := _teff(_sample(world.T, lat, lon), lat)
	if e < GeoS.SEA:                                        # 海洋:深浅 + 浪花 + 寒流 + 海冰
		var depth := clampf((GeoS.SEA - e) / 0.7, 0.0, 1.0)
		var col := SHALLOW.lerp(DEEP, depth)
		if depth < 0.06: col = SURF.lerp(col, depth / 0.06)
		col = col.lerp(COLD_OCEAN, clampf((12.0 - tt) / 40.0, 0.0, 0.45))
		var icef := clampf((-tt - 1.0) / 4.0, 0.0, 0.85)
		if icef > 0.0: col = col.lerp(ICE, icef)
		return col
	var h := e - GeoS.SEA
	if h < 0.04:                                            # 浪花→沙滩
		return SURF.lerp(BEACH, clampf(h / 0.04, 0.0, 1.0))
	var pp := _sample(world.P, lat, lon)
	var moist := clampf(0.4 + 0.55 * (pp - 0.4) + 0.35 * (geo.mnoise[idx] - 0.5), 0.0, 1.0)
	var bio: Color
	if e > GeoS.SEA + 0.6: bio = MTNSNOW if tt < 2.0 else MTN     # 高山裸岩/雪
	elif tt < 6.0: bio = TAIGA
	elif moist < 0.3: bio = DESERT
	elif tt > 22.0 and moist > 0.55: bio = RAIN
	else: bio = GRASS if moist < 0.5 else TEMPER
	var snowf := clampf((-tt - 2.0) / 6.0, 0.0, 1.0)        # 冷→渐白(替代硬冰带,冰期会扩张)
	bio = bio.lerp(SNOW, snowf)
	var sh: float = geo.shade[idx]                          # 静态地表纹理
	bio = Color(bio.r * sh, bio.g * sh, bio.b * sh)
	if h < 0.085: return BEACH.lerp(bio, clampf((h - 0.04) / 0.045, 0.0, 1.0))
	return bio

# ---------- 分析视图(活模拟采样)----------
func _cell_color(idx: int) -> Color:
	if view == "terrain": return _terrain_color(idx)
	var lat: float = _plat[idx]
	var lon: float = _plon[idx]
	var land: bool = geo.elev[idx] > GeoS.SEA
	if view == "life":
		var base: Color = Color8(26,34,24) if land else Color8(12,20,34)
		var v := clampf(_sample(world.N, lat, lon) / Sim.Kmax, 0.0, 1.0)
		return base if v < 0.02 else _ramp(LIFEC, v)
	if view == "trophic":
		var nn := clampf(_sample(world.N, lat, lon) / Sim.Kmax, 0.0, 1.0)
		if nn < 0.02: return Color8(14, 18, 26) if not land else Color8(20, 24, 18)
		var hh := clampf(_sample(world.H, lat, lon) / 12.0, 0.0, 1.0)
		var cc := clampf(_sample(world.C, lat, lon) / 3.0, 0.0, 1.0)
		return Color(0.12 + 0.88 * clampf(0.55 * hh + cc, 0.0, 1.0), 0.12 + 0.78 * nn, 0.12 + 0.6 * cc)
	if view == "adapt":
		if _sample(world.N, lat, lon) < Sim.SEED: return Color8(16,20,28)
		return _tcol(_sample(world.Topt, lat, lon))
	if view == "species":
		var c := _nearest(lat, lon)
		var ck: int = c.x * Sim.NLon + c.y
		if world.N[ck] < Sim.SEED or world.spId[ck] < 1: return Color8(16,20,28)
		return _sp_color(world.spId[ck])
	if view == "temp": return _tcol(_sample(world.T, lat, lon))
	if view == "prec": return _ramp(PREC, _sample(world.P, lat, lon) / 1.2)
	if view == "sst": return Color8(22,28,46) if land else _tcol(_sample(world.S, lat, lon))
	return Color.BLACK

func refresh() -> void:
	if world == null: return
	for gy in _H:
		var row := gy * _W
		for gx in _W:
			_img.set_pixel(gx, gy, _cell_color(row + gx))
	_tex.update(_img)
	queue_redraw()

func _draw() -> void:
	if world == null: return
	var W := size.x
	var H := size.y
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	if show_belt:
		for gy in range(0, _H, 3):
			var lat := 90.0 - (gy + 0.5) * 180.0 / _H
			for gx in range(0, _W, 3):
				var lon := (gx + 0.5) * 360.0 / _W
				var pv := _sample(world.P, lat, lon)
				if pv < 0.6: continue
				draw_rect(Rect2(gx * W / _W, gy * H / _H, W / _W * 3.0, H / _H * 3.0), Color(0.35, 0.63, 1.0, minf(0.35, (pv - 0.5) * 0.4)))
	if show_wind:
		for j in Sim.NLat:
			var lat: float = world.latof(j)
			var u: float = world.uband(lat)
			if abs(u) < 0.4: continue
			var y: float = (90.0 - lat) / 180.0 * H
			for i in range(2, Sim.NLon, 5):
				var x := (i + 0.5) / Sim.NLon * W
				var ln: float = minf(14.0, 6.0 + abs(u) * 1.5) * (1.0 if u > 0.0 else -1.0)
				_arrow(x - ln / 2.0, y, x + ln / 2.0, y)
	for L in [60, 30, 0, -30, -60]:
		var y: float = (90.0 - L) / 180.0 * H
		draw_line(Vector2(0, y), Vector2(W, y), Color(1,1,1,0.09), 1.0)
		var lbl: String = (str(L) + "°N") if L > 0 else ((str(-L) + "°S") if L < 0 else "赤道")
		draw_string(ThemeDB.fallback_font, Vector2(4, y - 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1,1,1,0.5))
	# 选中粗格高亮框
	if selected.x >= 0:
		var j := selected.x
		var i := selected.y
		var xl := float(i) / Sim.NLon * W
		var xr := float(i + 1) / Sim.NLon * W
		var yt := (90.0 - (-90.0 + (j + 1) * 180.0 / Sim.NLat)) / 180.0 * H
		var yb := (90.0 - (-90.0 + j * 180.0 / Sim.NLat)) / 180.0 * H
		draw_rect(Rect2(xl, yt, xr - xl, yb - yt), Color(1, 1, 0.4, 0.95), false, 2.0)

func _arrow(x1: float, y1: float, x2: float, y2: float) -> void:
	var c := Color(1,1,1,0.6)
	draw_line(Vector2(x1, y1), Vector2(x2, y2), c, 1.4)
	var dir := 1.0 if x2 > x1 else -1.0
	var pts := PackedVector2Array([Vector2(x2, y2), Vector2(x2 - 4 * dir, y2 - 2), Vector2(x2 - 4 * dir, y2 + 2)])
	draw_colored_polygon(pts, c)
