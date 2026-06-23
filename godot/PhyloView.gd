class_name PhyloView
extends Control
# 谱系树:把 world.phylo 画成随深时间生长的世系。只画"活物种 + 其祖先链"(活着的世系骨架),
# 横轴=地质年,每个物种一条泳道:出生→(灭绝/现在);分裂处连到母种泳道,灭绝处打红叉。

var world
var _lc := 0   # 泳道分配计数器

func setup(w) -> void:
	world = w

func refresh() -> void:
	queue_redraw()

func _sp_color(id: int) -> Color:
	var h := fmod(id * 137.508, 360.0) / 360.0
	var s := 0.62
	var l := 0.58
	var q := (l * (1.0 + s)) if l < 0.5 else (l + s - l * s)
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))
func _hue(p: float, q: float, x: float) -> float:
	x = fmod(fmod(x, 1.0) + 1.0, 1.0)
	if x < 1.0 / 6.0: return p + (q - p) * 6.0 * x
	if x < 1.0 / 2.0: return q
	if x < 2.0 / 3.0: return p + (q - p) * (2.0 / 3.0 - x) * 6.0
	return p

func _dfs(id, kids: Dictionary, lane: Dictionary) -> void:
	lane[id] = _lc
	_lc += 1
	for c in kids[id]: _dfs(c, kids, lane)

func _draw() -> void:
	var W := size.x
	var H := size.y
	# 背板
	draw_rect(Rect2(Vector2.ZERO, size), Color8(10, 13, 19))
	if world == null or world.phylo.is_empty(): return
	var phylo = world.phylo
	var byid := {}
	for p in phylo: byid[p["id"]] = p
	# 相关集 = 活物种 + 其全部祖先
	var relevant := {}
	for p in phylo:
		if p["deathY"] < 0:
			var cur = p
			while cur != null and not relevant.has(cur["id"]):
				relevant[cur["id"]] = cur
				cur = byid.get(cur["parent"], null)
	if relevant.is_empty(): return
	# 子代表 + 根
	var kids := {}
	for id in relevant: kids[id] = []
	var roots := []
	for id in relevant:
		var par = relevant[id]["parent"]
		if relevant.has(par): kids[par].append(id)
		else: roots.append(id)
	var bornf := func(a, b): return int(relevant[a]["bornY"]) < int(relevant[b]["bornY"])
	roots.sort_custom(bornf)
	for id in kids: kids[id].sort_custom(bornf)
	# DFS 分配泳道
	_lc = 0
	var lane := {}
	for r in roots: _dfs(r, kids, lane)
	var nlanes := _lc
	if nlanes == 0: return
	# 时间范围
	var t0 := 1 << 30
	for id in relevant: t0 = min(t0, int(relevant[id]["bornY"]))
	var t1: int = max(world.geoT, t0 + 1)
	var padL := 8.0
	var padR := 8.0
	var padT := 18.0
	var padB := 16.0
	var plotW := W - padL - padR
	var laneH := (H - padT - padB) / float(nlanes)
	# 标题 + 时间轴
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(padL, 13), "🌳 谱系树 · 活世系 %d 支" % world.phylo.filter(func(p): return p["deathY"] < 0).size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.9, 1.0, 0.9))
	draw_string(font, Vector2(padL, H - 4), "%d 年" % t0, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
	draw_string(font, Vector2(W - 70, H - 4), "%d 年 · 今" % t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
	# 画世系
	for id in relevant:
		var p = relevant[id]
		var alive: bool = p["deathY"] < 0
		var ly := padT + (float(lane[id]) + 0.5) * laneH
		var bx := padL + float(int(p["bornY"]) - t0) / float(t1 - t0) * plotW
		var endY: int = world.geoT if alive else int(p["deathY"])
		var dx := padL + float(endY - t0) / float(t1 - t0) * plotW
		var col := _sp_color(int(id))
		if not alive: col = col.darkened(0.45)
		# 与母种的竖向分支连接
		var par = p["parent"]
		if relevant.has(par):
			var py := padT + (float(lane[par]) + 0.5) * laneH
			draw_line(Vector2(bx, py), Vector2(bx, ly), col.darkened(0.25), 1.0)
		draw_line(Vector2(bx, ly), Vector2(dx, ly), col, 2.0 if alive else 1.0)
		if not alive:
			draw_line(Vector2(dx, ly - 2.5), Vector2(dx, ly + 2.5), Color(1, 0.45, 0.45, 0.8), 1.5)
