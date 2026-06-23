extends SceneTree
# 人体生理模型 headless 验证: godot --headless --path godot --script res://bodycheck.gd
# 复现 design_food_water.md 三条基准:断水~5天致命、断食~40天致命、牛肉干比椰肉更脱水(食物-水耦合)
const Body = preload("res://sim/Body.gd")

func _initialize() -> void:
	# 基准1:断水 22°C 静息 → 致命天数
	var b1 = Body.new()
	while not b1.dead and b1.hoursAlive < 24 * 15:
		b1.step(1, 22.0, 1.0)
	var days1: float = b1.hoursAlive / 24.0

	# 基准2:断食但喝够水 → 致命天数
	var b2 = Body.new()
	var hrs := 0
	while not b2.dead and hrs < 24 * 60:
		if hrs % 6 == 0: b2.drink(500)
		b2.step(1, 22.0, 1.0); hrs += 1
	var days2: float = b2.hoursAlive / 24.0

	# 基准3:同样每天 400mL 水,牛肉干(高蛋白高盐少水) vs 椰肉(低蛋白多水)
	var dry = Body.new()   # 牛肉干 200g/天:~820kcal,水46mL,蛋白66g,盐4g
	var wet = Body.new()   # 椰肉   200g/天:~708kcal,水94mL,蛋白6.6g,盐0.1g
	var dryDeath := -1.0
	var wetDeath := -1.0
	var dryDeh6 := 0.0
	var wetDeh6 := 0.0
	for h in 24 * 9:
		if h % 24 == 8:
			if not dry.dead: dry.eat(820, 46, 66, 4.0)
			if not wet.dead: wet.eat(708, 94, 6.6, 0.1)
		if h % 6 == 0:
			if not dry.dead: dry.drink(100)
			if not wet.dead: wet.drink(100)
		dry.step(1, 22.0, 1.0); wet.step(1, 22.0, 1.0)
		if h == 24 * 6 - 1: dryDeh6 = dry.dehydrationPct(); wetDeh6 = wet.dehydrationPct()
		if dry.dead and dryDeath < 0: dryDeath = dry.hoursAlive / 24.0
		if wet.dead and wetDeath < 0: wetDeath = wet.hoursAlive / 24.0

	print("=== 人体生理模型验证(复现 design 基准)===")
	print("基准1 断水22°C静息: 第 %.1f 天致命 (%s)  [design≈5天]" % [days1, b1.deathCause])
	print("基准2 断食喝够水:   第 %.1f 天致命 (%s)  [design≈40天]" % [days2, b2.deathCause])
	print("基准3 食物-水耦合(同400mL/天):")
	print("   牛肉干: 第6天脱水 %.1f%%, 死亡 %s  [design 18.2%%/第5天]" % [dryDeh6, ("第%.1f天" % dryDeath) if dryDeath > 0 else "存活"])
	print("   椰肉:   第6天脱水 %.1f%%, 死亡 %s  [design 15.2%%/第6天]" % [wetDeh6, ("第%.1f天" % wetDeath) if wetDeath > 0 else "存活"])
	var b1ok: bool = days1 >= 3.5 and days1 <= 7.0
	var b2ok: bool = days2 >= 30.0 and days2 <= 50.0
	var b3ok: bool = dryDeh6 > wetDeh6 and dryDeath > 0 and dryDeath < wetDeath
	print("断水致命天数合理: %s" % ("✅" if b1ok else "❌"))
	print("断食致命天数合理: %s" % ("✅" if b2ok else "❌"))
	print("牛肉干比椰肉更脱水(食物-水耦合涌现): %s" % ("✅" if b3ok else "❌"))
	quit(0 if (b1ok and b2ok and b3ok) else 1)
