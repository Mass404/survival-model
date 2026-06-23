extends SceneTree
# #9 生存层最小耦合证明: godot --headless --path godot --script res://survivecheck.gd
# 把人体模型接到全球行星的气候边界(PushBoundary 最小版):从 World 某格取真实 Teff 当环境温度,
# 看同样断水时热带 vs 高纬的生存难度差异——证明"地点气候决定求生难度"(生存层地基)。
const Sim = preload("res://sim/World.gd")
const Body = preload("res://sim/Body.gd")

func _initialize() -> void:
	var w = Sim.new()
	w.spinUp()
	for d in Sim.YEAR: w.stepDay(d % Sim.YEAR)   # 跑一年让气候铺开
	for d in 180: w.stepDay(d % Sim.YEAR)         # 推到年中暖季
	var jTrop: int = Sim.NLat / 2
	var jPolar := 2
	var tTrop := -100.0
	var tPolar := 100.0
	for i in Sim.NLon:
		tTrop = maxf(tTrop, w.Teff(jTrop, i))     # 热带最热格(赤道暖季热点)
		tPolar = minf(tPolar, w.Teff(jPolar, i))  # 高纬最冷格
	var trop = Body.new()
	var polar = Body.new()
	while not trop.dead and trop.hoursAlive < 24 * 20: trop.step(1, tTrop, 1.0)
	while not polar.dead and polar.hoursAlive < 24 * 20: polar.step(1, tPolar, 1.0)
	var dTrop: float = trop.hoursAlive / 24.0
	var dPolar: float = polar.hoursAlive / 24.0
	print("=== #9 生存层:身体接全球气候边界(最小耦合证明)===")
	print("热带地点(纬带%d): 气候 %.1f°C → 断水致命 第 %.1f 天 (%s)" % [jTrop, tTrop, dTrop, trop.deathCause])
	print("高纬地点(纬带%d): 气候 %.1f°C → 断水致命 第 %.1f 天 (%s)" % [jPolar, tPolar, dPolar, polar.deathCause])
	var coupled: bool = absf(tTrop - tPolar) > 1.0
	var harder: bool = dTrop <= dPolar
	print("行星喂边界(地点气候不同): %s" % ("✅" if coupled else "❌"))
	print("气候决定求生难度(热地断水更快死): %s" % ("✅" if harder else "❌"))
	quit(0 if (coupled and harder) else 1)
