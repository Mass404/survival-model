extends SceneTree
# 真实物理化学引擎 headless 验证:godot --headless --path godot --script res://chemcheck.gd
# 铁律:① 每个反应原子配平+质量守恒 ② 摩尔质量对得上真实值 ③ react() 受点燃温门控
# ④ react() 应用后每种元素总原子数守恒(冶炼/燃烧都不凭空造原子) ⑤ 反应热方向对(燃烧放热/煅烧吸热)
const ChemS = preload("res://sim/Chem.gd")

func _initialize() -> void:
	print("================ 真实物理化学引擎 验证 ================")

	# ① 全部反应原子配平 + 质量守恒(|Δ质量|<1e-6 g/mol)
	var bal_ok := true; var mass_ok := true; var worst := 0.0
	for rx in ChemS.RX:
		if not ChemS.is_balanced(rx): bal_ok = false; print("  ✗ 未配平: %s" % rx["id"])
		var md: float = absf(ChemS.mass_delta(rx)); worst = max(worst, md)
		if md > 1e-6: mass_ok = false; print("  ✗ 质量不守恒 %.4g: %s" % [md, rx["id"]])
	print("① 配平: %d 个反应全配平%s · 最大质量差 %s g/mol(守恒%s)" % [ChemS.RX.size(), _t(bal_ok), str(worst), _t(mass_ok)])

	# ② 摩尔质量对真实值(CO2 44.01 · Fe2O3 159.69 · H2O 18.02 · CaCO3 100.09)
	var mm_ok: bool = (
		absf(ChemS.molar_mass("CO2") - 44.01) < 0.05 and
		absf(ChemS.molar_mass("Fe2O3") - 159.69) < 0.1 and
		absf(ChemS.molar_mass("H2O") - 18.015) < 0.02 and
		absf(ChemS.molar_mass("CaCO3") - 100.09) < 0.1)
	print("② 摩尔质量: CO₂%.2f · Fe₂O₃%.2f · H₂O%.3f · CaCO₃%.2f → %s" % [
		ChemS.molar_mass("CO2"), ChemS.molar_mass("Fe2O3"), ChemS.molar_mass("H2O"), ChemS.molar_mass("CaCO3"), _t(mm_ok)])

	# ③ 点燃温门控:碳燃烧在 400K 不烧、800K 才烧
	var rxC: Dictionary = ChemS.find_rx("carbon_combust")
	var cold := {"C": 10.0, "O2": 10.0}
	var qcold: float = ChemS.react(cold, rxC, 400.0, 5.0)     # <Tign 700 → 不反应
	var hot := {"C": 10.0, "O2": 10.0}
	var qhot: float = ChemS.react(hot, rxC, 800.0, 5.0)       # ≥Tign → 烧 5mol
	var gate_ok: bool = is_equal_approx(qcold, 0.0) and qhot > 0.0 and is_equal_approx(float(hot["CO2"]), 5.0)
	print("③ 点燃门控: 400K 放热%.0f(不烧) · 800K 放热%.0fkJ→CO₂ %.1fmol → %s" % [qcold, qhot, float(hot["CO2"]), _t(gate_ok)])

	# ④ 原子守恒:炼铁 Fe2O3+3CO→2Fe+3CO2,react 前后 Fe/C/O 总原子数不变
	var furnace := {"Fe2O3": 4.0, "CO": 15.0}
	var fe0: float = ChemS.total_atoms(furnace, "Fe"); var c0: float = ChemS.total_atoms(furnace, "C"); var o0: float = ChemS.total_atoms(furnace, "O")
	var q: float = ChemS.react(furnace, ChemS.find_rx("iron_blast"), 1500.0, 99.0)
	var fe1: float = ChemS.total_atoms(furnace, "Fe"); var c1: float = ChemS.total_atoms(furnace, "C"); var o1: float = ChemS.total_atoms(furnace, "O")
	var cons_ok: bool = absf(fe1 - fe0) < 1e-9 and absf(c1 - c0) < 1e-9 and absf(o1 - o0) < 1e-9 and float(furnace.get("Fe", 0.0)) > 0.0
	print("④ 炼铁原子守恒: Fe %.1f→%.1f · C %.1f→%.1f · O %.1f→%.1f · 出铁 %.1fmol → %s" % [
		fe0, fe1, c0, c1, o0, o1, float(furnace.get("Fe", 0.0)), _t(cons_ok)])

	# ⑤ 反应热方向:燃烧放热(dH<0→放热>0)、石灰煅烧吸热(dH>0→需供能,放热<0)
	var burn := {"CH4": 1.0, "O2": 5.0}
	var qburn: float = ChemS.react(burn, ChemS.find_rx("methane_combust"), 1000.0, 1.0)
	var kiln := {"CaCO3": 1.0}
	var qkiln: float = ChemS.react(kiln, ChemS.find_rx("calcination"), 1200.0, 1.0)
	var heat_ok: bool = qburn > 0.0 and qkiln < 0.0 and float(kiln.get("CaO", 0.0)) > 0.0
	print("⑤ 反应热: 甲烷燃烧 +%.0fkJ(放) · 石灰煅烧 %.0fkJ(吸)→生石灰%.1fmol → %s" % [qburn, qkiln, float(kiln.get("CaO", 0.0)), _t(heat_ok)])

	var all_ok: bool = bal_ok and mass_ok and mm_ok and gate_ok and cons_ok and heat_ok
	print("------------------------------------------------")
	print("① 配平守恒%s ② 摩尔质量%s ③ 点燃门控%s ④ 原子守恒%s ⑤ 反应热向%s" % [
		_t(bal_ok and mass_ok), _t(mm_ok), _t(gate_ok), _t(cons_ok), _t(heat_ok)])
	print("真实物理化学引擎: %s" % ("✅ 全过" if all_ok else "❌ 有失败"))
	quit(0 if all_ok else 1)

func _t(b: bool) -> String: return "✅" if b else "❌"
