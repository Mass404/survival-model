class_name Chem
extends RefCounted
# ====================================================================
# 真实物理化学引擎(P1 地基)· 纯数据 + 纯函数,headless 可验
# 一切建立在:① 元素原子量 ② 化合物(组成/相/熔点/密度)③ 配平的化学反应(原子守恒+ΔH+点燃温)
# 玩家侧冶炼/取火/烧制、模拟侧热力学、材料物性 都读这一层。确定性、守恒。
# 铁律:每个反应必须原子配平,react() 应用后每种元素的总原子数守恒。
# ====================================================================

# 原子量 g/mol
const AW := {
	"H": 1.008, "C": 12.011, "N": 14.007, "O": 15.999, "Na": 22.990, "Mg": 24.305,
	"Al": 26.982, "Si": 28.085, "S": 32.06, "Cl": 35.45, "K": 39.098, "Ca": 40.078,
	"Ti": 47.867, "Cr": 51.996, "Mn": 54.938, "Fe": 55.845, "Ni": 58.693, "Cu": 63.546,
	"Zn": 65.38, "Sn": 118.71, "Ag": 107.868, "Au": 196.967, "Pb": 207.2, "Hg": 200.59,
	"U": 238.029, "Th": 232.038,
	"I": 126.904, "P": 30.974, "B": 10.81, "F": 18.998, "Mo": 95.95, "Se": 78.971, "Co": 58.933,
}

# ===== #2 桥:World 的 33 元素槽(World.MN 顺序)↔ 原子组成 =====
# 多数槽=单元素;含氧阴离子组按真实组成(硫酸盐SO₄/碳酸盐CO₃/硝NO₃/硅以SiO₂计)。
# 让全局逐格化学(disE/depE/rockE)能按原子记账 + 在格上跑配平反应。顺序必须与 World.MN 严格一致。
const E2COMP := [
	{"Na": 1},          # 0 钠
	{"Ca": 1},          # 1 钙
	{"Mg": 1},          # 2 镁
	{"K": 1},           # 3 钾
	{"Fe": 1},          # 4 铁
	{"Cl": 1},          # 5 氯
	{"S": 1, "O": 4},   # 6 硫酸盐 SO₄
	{"C": 1, "O": 3},   # 7 碳酸盐 CO₃
	{"Si": 1, "O": 2},  # 8 硅(溶解硅以 SiO₂ 计)
	{"Cu": 1},          # 9 铜
	{"I": 1},           # 10 碘
	{"Zn": 1},          # 11 锌
	{"Sn": 1},          # 12 锡
	{"Pb": 1},          # 13 铅
	{"Ag": 1},          # 14 银
	{"Au": 1},          # 15 金
	{"S": 1},           # 16 硫(单质/还原态)
	{"C": 1},           # 17 碳(有机/还原态)
	{"N": 1, "O": 3},   # 18 硝 NO₃
	{"P": 1},           # 19 磷
	{"Hg": 1},          # 20 汞
	{"B": 1},           # 21 硼
	{"F": 1},           # 22 氟
	{"U": 1},           # 23 铀
	{"Th": 1},          # 24 钍
	{"Al": 1},          # 25 铝
	{"Mn": 1},          # 26 锰
	{"Ti": 1},          # 27 钛
	{"Ni": 1},          # 28 镍
	{"Cr": 1},          # 29 铬
	{"Mo": 1},          # 30 钼
	{"Co": 1},          # 31 钴
	{"Se": 1},          # 32 硒
]

# 第 i 个元素槽的式量 g/mol(按其原子组成)
static func slot_molar_mass(i: int) -> float:
	var m := 0.0
	var comp = E2COMP[i]
	for el in comp: m += float(AW[el]) * float(comp[el])
	return m

# 把一份 33 元素槽量向量(摩尔)按原子组成累加成基础元素原子总数 {元素:原子数};供守恒记账/反应桥
static func slots_to_atoms(vec: Array) -> Dictionary:
	var atoms := {}
	for i in E2COMP.size():
		if i >= vec.size(): break
		var amt: float = float(vec[i])
		if amt == 0.0: continue
		var comp = E2COMP[i]
		for el in comp: atoms[el] = float(atoms.get(el, 0.0)) + amt * float(comp[el])
	return atoms

# 物种表:comp=原子组成 · phase=相(s固/l液/g气) · mp=熔点K · rho=密度g/cm³ · name=中文
const SP := {
	"C":       {"comp": {"C": 1}, "phase": "s", "mp": 3823.0, "rho": 2.27, "name": "碳(炭)"},
	"O2":      {"comp": {"O": 2}, "phase": "g", "name": "氧气"},
	"N2":      {"comp": {"N": 2}, "phase": "g", "name": "氮气"},
	"H2":      {"comp": {"H": 2}, "phase": "g", "name": "氢气"},
	"CO2":     {"comp": {"C": 1, "O": 2}, "phase": "g", "name": "二氧化碳"},
	"CO":      {"comp": {"C": 1, "O": 1}, "phase": "g", "name": "一氧化碳"},
	"H2O":     {"comp": {"H": 2, "O": 1}, "phase": "l", "mp": 273.15, "rho": 1.0, "name": "水"},
	"CH4":     {"comp": {"C": 1, "H": 4}, "phase": "g", "name": "甲烷"},
	"SO2":     {"comp": {"S": 1, "O": 2}, "phase": "g", "name": "二氧化硫"},
	"SiO2":    {"comp": {"Si": 1, "O": 2}, "phase": "s", "mp": 1986.0, "rho": 2.65, "name": "石英"},
	"Fe":      {"comp": {"Fe": 1}, "phase": "s", "mp": 1811.0, "rho": 7.87, "name": "铁"},
	"Fe2O3":   {"comp": {"Fe": 2, "O": 3}, "phase": "s", "mp": 1838.0, "rho": 5.24, "name": "赤铁矿"},
	"FeS2":    {"comp": {"Fe": 1, "S": 2}, "phase": "s", "mp": 1444.0, "rho": 5.01, "name": "黄铁矿"},
	"Cu":      {"comp": {"Cu": 1}, "phase": "s", "mp": 1358.0, "rho": 8.96, "name": "铜"},
	"Cu2S":    {"comp": {"Cu": 2, "S": 1}, "phase": "s", "mp": 1403.0, "rho": 5.6, "name": "辉铜矿"},
	"CuFeS2":  {"comp": {"Cu": 1, "Fe": 1, "S": 2}, "phase": "s", "mp": 1223.0, "rho": 4.2, "name": "黄铜矿"},
	"CaCO3":   {"comp": {"Ca": 1, "C": 1, "O": 3}, "phase": "s", "mp": 1612.0, "rho": 2.71, "name": "方解石"},
	"CaO":     {"comp": {"Ca": 1, "O": 1}, "phase": "s", "mp": 2886.0, "rho": 3.34, "name": "生石灰"},
	"Ca(OH)2": {"comp": {"Ca": 1, "O": 2, "H": 2}, "phase": "s", "mp": 853.0, "rho": 2.21, "name": "熟石灰"},
	"NaCl":    {"comp": {"Na": 1, "Cl": 1}, "phase": "s", "mp": 1074.0, "rho": 2.17, "name": "盐"},
}

# 配平反应表:r=反应物{物种:系数} · p=产物{物种:系数} · dH=反应焓 kJ/mol反应(负=放热) · Tign=点燃/活化温度 K
const RX := [
	{"id": "carbon_combust", "name": "碳完全燃烧", "r": {"C": 1, "O2": 1}, "p": {"CO2": 1}, "dH": -393.5, "Tign": 700.0},
	{"id": "carbon_partial", "name": "碳不完全燃烧", "r": {"C": 2, "O2": 1}, "p": {"CO": 2}, "dH": -221.0, "Tign": 700.0},
	{"id": "boudouard", "name": "Boudouard平衡", "r": {"C": 1, "CO2": 1}, "p": {"CO": 2}, "dH": 172.5, "Tign": 973.0},
	{"id": "h2_combust", "name": "氢气燃烧", "r": {"H2": 2, "O2": 1}, "p": {"H2O": 2}, "dH": -571.6, "Tign": 773.0},
	{"id": "methane_combust", "name": "甲烷燃烧", "r": {"CH4": 1, "O2": 2}, "p": {"CO2": 1, "H2O": 2}, "dH": -890.0, "Tign": 873.0},
	{"id": "iron_blast", "name": "铁矿高炉还原(CO)", "r": {"Fe2O3": 1, "CO": 3}, "p": {"Fe": 2, "CO2": 3}, "dH": -24.8, "Tign": 1100.0},
	{"id": "iron_carbothermal", "name": "铁矿碳热还原", "r": {"Fe2O3": 2, "C": 3}, "p": {"Fe": 4, "CO2": 3}, "dH": 467.9, "Tign": 1473.0},
	{"id": "calcination", "name": "石灰石煅烧", "r": {"CaCO3": 1}, "p": {"CaO": 1, "CO2": 1}, "dH": 178.3, "Tign": 1100.0},
	{"id": "slaking", "name": "生石灰消化", "r": {"CaO": 1, "H2O": 1}, "p": {"Ca(OH)2": 1}, "dH": -65.2, "Tign": 0.0},
	{"id": "pyrite_roast", "name": "黄铁矿焙烧", "r": {"FeS2": 4, "O2": 11}, "p": {"Fe2O3": 2, "SO2": 8}, "dH": -3310.0, "Tign": 700.0},
	{"id": "copper_smelt", "name": "辉铜矿吹炼", "r": {"Cu2S": 1, "O2": 1}, "p": {"Cu": 2, "SO2": 1}, "dH": -217.0, "Tign": 1473.0},
]

# ===== #3 真热力学:Arrhenius 温度依赖 =====
const R_GAS := 8.314             # 气体常数 J/(mol·K)
const EA_SILICATE := 60000.0     # 硅酸盐风化表观活化能 J/mol(实测 50–80 kJ/mol;定地质碳循环恒温器的温度敏感)
# Arrhenius 速率因子 exp(-Ea/R·(1/T−1/T0)),归一到参考温 refC(℃)处=1。tempC/refC 单位℃。
# Ea=60kJ/mol 时 +10℃≈2.3×(真实风化 Q10),冷→指数变慢、暖→指数变快。
static func arrhenius(tempC: float, Ea: float, refC: float) -> float:
	var T: float = max(1.0, tempC + 273.15)
	var T0: float = refC + 273.15
	return exp(-Ea / R_GAS * (1.0 / T - 1.0 / T0))

# 摩尔质量 g/mol(由组成算)
static func molar_mass(sp: String) -> float:
	var m := 0.0
	var comp = SP[sp]["comp"]
	for el in comp: m += float(AW[el]) * float(comp[el])
	return m

# 反应的逐元素原子差(反应物−产物);全 0 = 配平
static func element_balance(rx: Dictionary) -> Dictionary:
	var bal := {}
	for sp in rx["r"]:
		var comp = SP[sp]["comp"]
		for el in comp: bal[el] = float(bal.get(el, 0.0)) + float(rx["r"][sp]) * float(comp[el])
	for sp in rx["p"]:
		var comp = SP[sp]["comp"]
		for el in comp: bal[el] = float(bal.get(el, 0.0)) - float(rx["p"][sp]) * float(comp[el])
	return bal

static func is_balanced(rx: Dictionary) -> bool:
	var bal := element_balance(rx)
	for el in bal:
		if absf(float(bal[el])) > 1e-9: return false
	return true

# 质量差 g/mol反应(反应物−产物);配平的反应应 ≈0(质量守恒)
static func mass_delta(rx: Dictionary) -> float:
	var m := 0.0
	for sp in rx["r"]: m += float(rx["r"][sp]) * molar_mass(sp)
	for sp in rx["p"]: m -= float(rx["p"][sp]) * molar_mass(sp)
	return m

static func find_rx(id: String) -> Dictionary:
	for rx in RX:
		if rx["id"] == id: return rx
	return {}

# 在温度 T(K)下按反应推进:消耗反应物/产生产物(原子守恒),返回放热 kJ(>0 放热,<0 吸热需供能)。
# amounts 为 mol 字典(按引用修改);受限于最少反应物 + max_extent;T<Tign 则不反应。
static func react(amounts: Dictionary, rx: Dictionary, T: float, max_extent: float) -> float:
	if T < float(rx["Tign"]): return 0.0
	var ext := max_extent
	for sp in rx["r"]:
		ext = min(ext, float(amounts.get(sp, 0.0)) / float(rx["r"][sp]))
	if ext <= 0.0: return 0.0
	for sp in rx["r"]: amounts[sp] = float(amounts.get(sp, 0.0)) - ext * float(rx["r"][sp])
	for sp in rx["p"]: amounts[sp] = float(amounts.get(sp, 0.0)) + ext * float(rx["p"][sp])
	return -float(rx["dH"]) * ext

# 一份 mol 字典里某元素的总原子数(守恒检验用)
static func total_atoms(amounts: Dictionary, el: String) -> float:
	var n := 0.0
	for sp in amounts:
		if SP.has(sp) and SP[sp]["comp"].has(el): n += float(amounts[sp]) * float(SP[sp]["comp"][el])
	return n
