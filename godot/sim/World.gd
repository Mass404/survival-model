class_name World
extends RefCounted
# ====================================================================
# 全球演化 · 纯模拟内核(从 evolve.html 移植)
# 不碰渲染 / 不依赖场景 —— 可被 validate.gd headless 单独跑、对数。
# 【性能】网格用扁平 PackedFloat64Array(连续、定型、保双精度),索引 k = j*NLon + i。
#         逐日/逐步的快照与累加器用预分配缓冲复用,零稳态分配。lat/uband 按纬度缓存。
# ====================================================================

const NLat := 18
const NLon := 24
const SZ := NLat * NLon
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
var parasitesOn := true   # 可关:用于红皇后对照实验
var land_mask = null   # Geo 注入的粗海陆 mask;null 时退回经度矩形带

# ---------- 场(扁平 k=j*NLon+i) ----------
var Land := PackedByteArray()
var T := PackedFloat64Array()
var S := PackedFloat64Array()
var SAL := PackedFloat64Array()
var P := PackedFloat64Array()
var U := PackedFloat64Array()
var PR := PackedFloat64Array()
var FR := PackedFloat64Array()
var N := PackedFloat64Array()      # 生产者生物量
var H := PackedFloat64Array()      # 食草者(一级消费者)
var C := PackedFloat64Array()      # 食肉者(二级消费者)
var Org := PackedFloat64Array()    # 史前有机汤 org(生命前底物)
var Prot := PackedFloat64Array()   # 蛋白质 prot(org 聚合而来;与 org 同为生命食物 food)
var Lip := PackedFloat64Array()    # 脂质 lip(合成副产物→过 CMC 自组装膜泡)
var Co2 := PackedFloat64Array()    # 每格大气 CO2(局部化学;ΣCo2=大气总碳,globalCO2=场均浓度)
var Hab := PackedFloat64Array()
var Topt := PackedFloat64Array()
var Salt := PackedFloat64Array()
var Dry := PackedFloat64Array()
var spId := PackedInt32Array()
var rSex := PackedFloat64Array()   # 有性生殖投资(0克隆..1全有性)
var rAuto := PackedFloat64Array()  # 代谢型(0异养..1自养:化能/光合)
var rPhoto := PackedFloat64Array() # 自养中光合占比(0化能..1光合)
var rAero := PackedFloat64Array()  # 好氧度(O₂从毒→资源:耐O₂毒 + 好氧呼吸产能)
var rEuk := PackedFloat64Array()   # 真核化(富氧+体型→内共生线粒体→能量暴涨)
var rSize := PackedFloat64Array()  # 体型(大→慢长 + 省维持 + 难被吃)
var rMulti := PackedFloat64Array() # 多细胞(真核×捕食压→大到吞不动,捕食免疫)
var rDiff := PackedFloat64Array()  # 细胞分化(多细胞×稳定竞争→germ-soma分工)
var rShell := PackedFloat64Array() # 矿化壳(多细胞×捕食×钙→建壳防御,寒武)
var rNeuro := PackedFloat64Array() # 感觉神经(多细胞×移动+捕食→觅食/避敌)
var rEndo := PackedFloat64Array()  # 温血(多细胞×冷胁迫→恒温,拓宽耐温但高耗能)
var rSymb := PackedFloat64Array()  # 互利共生(贫氮→固氮伙伴供养)
var rMemb := PackedFloat64Array()  # 膜泡(脂质过CMC→浓缩增殖+保护)
var Par := PackedFloat64Array()    # 寄生/病原载量
var Sym := PackedFloat64Array()
var Seg := PackedFloat64Array()
var Limb := PackedFloat64Array()
var Axis := PackedFloat64Array()

# ---------- 预分配缓冲 / 缓存 ----------
var _s0 := PackedFloat64Array()
var _sl0 := PackedFloat64Array()
var _t1 := PackedFloat64Array()
var _flow := PackedFloat64Array()
var _fTo := PackedFloat64Array()
var _fSa := PackedFloat64Array()
var _fDr := PackedFloat64Array()
var _comp := PackedInt32Array()
var _LAT := PackedFloat64Array()   # 每纬度 latof(j)
var _UB := PackedFloat64Array()    # 每纬度 uband(latof(j))

const morphK := 0.04
const morphCost := 0.02
const MGATE := 0.35
const MGW := 0.25

var phylo := []          # 谱系档案:{id,parent,bornY,deathY,Topt,land}
var nextSp := 1
var extEMA := 1.0
var massExt := []        # 大灭绝:{ky,lost,cause}

var events := []         # 演化事件流:{ky,icon,text}
var _seen_life := false
var _in_ice := false
var _in_warm := false

const SEED := 0.05
const IGNITE := 0.45
const Kmax := 40.0
# —— 史前有机化学(从 world.html 564-567;org/prot/lip 三库:合成→聚合↔水解→降解张弛)——
# K 值取自 world.html 权威常量(原配 CHEM=60 逐分钟步长);OCHEM 把它们重标定到 stepLife 的 dt 步长。
const OCHEM := 40.0      # 时间步标定系数(原版逐分钟×60;此处配 stepLife,prebiocheck 调准)
const oSynK := 5e-4      # 合成率 org(world.html 原值)
const oPolyK := 2e-3     # 聚合率 org²→prot
const oHydK := 8e-5      # 水解率 prot→org
const oDecK := 6e-7      # 降解率(org+prot)×O₂氧化
const lipFrac := 0.25    # 脂质=合成副产物比例
const lipDecay := 0.002  # 脂质降解率
const oCfrac := 0.001    # 有机↔无机碳转换(守恒;world.html 0.02,按 Godot org 量级重标到痕量,免抽干大气)
const ORG_IGNITE := 2.5  # 有机汤(org+prot)点燃阈值(world.html rIgnite=5,按 Godot org 量级重标)
# 食物网(Holling-II 捕食,饱和→稳定;系数按 stepLife dt=10 标定,validate 验金字塔/共存)
const FW_HALF := 8.0       # 半饱和猎物量
const FW_GRAZE := 0.5      # 单位捕食者最大摄食压
const FW_YIELD := 0.25     # 营养传递效率
const FW_MH := 0.08        # 食草者死亡率
const FW_MC := 0.05        # 食肉者死亡率
const FW_SEEDN := 5.0      # 生产者够多→点燃食草者
const FW_SEEDH := 2.0      # 食草者够多→点燃食肉者
const FW_DIFF := 0.15      # 消费者扩散率
# 有性生殖(红皇后)+ 寄生
const SEX_K := 0.05        # rSex 演化速率
const SEX_COST := 0.12     # 有性的双倍成本(无压力时拉回克隆)
const SEX_BOOST := 1.5     # 有性→适应加速倍率
const PAR_KILL := 0.25     # 寄生致死(∝宿主密度)
const PAR_GROW := 0.4      # 载量增长(∝宿主密度×(1-有性抗性))
const PAR_DECAY := 0.12    # 载量衰减
const PAR_SEEDN := 3.0     # 宿主够密→寄生点燃
const PAR_MAX := 20.0      # 载量上限(防数值爆炸)
const rb := 0.9
const rd := 0.12
# —— 三代谢能量预算(world.html 582-597;git 核对的权威值,按 Godot dt 步长用 dl=dt/10 标定)——
const rBirthK := 0.15       # 异养出生率
const rBirthAutoK := 0.11   # 化能自养出生率
const rBirthPhotoK := 0.32  # 光合出生率
const rKhalf := 4.0         # 异养底物 Monod 半饱和
const rYield := 0.6         # 异养产率(食物上限)
const rMaintK := 0.03       # 维持代谢率(活着就烧)
const rDeathK := 0.02       # 死亡基率
const extinctK := 3.0       # 失配致死放大(灾变→大规模死=灭绝)
const cFixK := 0.08         # 固碳率(化能/光合)
const o2YieldK := 0.03      # 光合产氧率
const o2half := 3.0         # 好氧半饱和 O₂
const aerBoost := 0.8       # 好氧呼吸产能增益
const rAutoAdaptK := 0.5    # 代谢型(异养↔自养)适应速率
const respCK := 0.06        # 呼吸返碳系数
const reminK := 0.02        # 生物量碳再矿化率(死亡氧化回 CO2)
# —— 性状层(world.html 600-649;复杂度演化,adaptive dynamics)——
const euGain := 1.0          # 真核能量增益基
const euCost := 0.1          # 真核维持成本
const euAdaptK := 0.05       # 真核适应速率
const euBoost := 1.2         # 真核线粒体产能增益(gB)
const rAeroAdaptK := 0.1     # 好氧度适应速率
const aerCostSel := 0.04     # 好氧成本(选择)
const sizeCost := 0.45       # 体型增殖减速
const sizeAdaptK := 0.04     # 体型适应速率
const multiDef := 1.0        # 多细胞防御(捕食免疫)
const multiCost := 0.15      # 多细胞成本
const multiAdaptK := 0.05    # 多细胞适应速率
const diffCost := 0.12       # 分化成本
const diffRepCost := 0.25    # 分化繁殖代价(gB)
const diffAdaptK := 0.05     # 分化适应速率
const shellDef := 0.85       # 矿化壳防御
const shellCost := 0.12      # 建壳成本
const shellGrowCost := 0.2   # 建壳繁殖代价(gB)
const shellAdaptK := 0.04    # 壳适应速率
const MOVE := 0.12
const FITW := 14.0
const SALTW := 2.5
const DRYW := 0.4
const BARRIER := 0.04
const TBUCKET := 9.0

var climCool := 0.0
const ICE_AMP := 22.0
const ICE_PERIOD := 14
# —— 天体撞击 + 米兰科维奇(从 world.html;确定性周期撞击骤冷+注碳;轨道慢周期调制冰期强弱)——
var impactWinter := 0.0      # 撞击冬天降温(尘埃遮日,全球均匀;脉冲后逐年衰减)
const IMPACT_T := 23         # 撞击周期(质数,与冰期14/暗色岩省40错相,避共振)
const IMPACT_WINTER := 15.0  # 单次撞击冬天降温幅度
const IMPACT_CO2 := 2.5      # 撞击气化注碳(岩石/地幔库→大气,守恒)
const impactDecay := 0.5     # 撞击冬天逐年衰减(尘埃沉降,几年回落)
const MILANK_T := 45         # 米兰科维奇轨道周期(比冰期长~3倍)
const milankDepth := 0.45    # 轨道调制深度(冰期幅度在 1-depth~1 间起伏)

# 冰川性海平面:全球冰量当存量(随冷积/随暖融)↔海洋体积,守恒(水在冰↔洋)。冰多→海退→陆扩
var geo = null            # Geo 注入:为 null 时海平面静态(不重算海陆)
var iceVol := 0.0
var refIce := -1.0        # 基准冰量(首年捕获)
var seaOffset := 0.0      # 海平面对高程阈值的偏移(冰多→负→海退)
const iceAccK := 1.0      # climCool→冰量目标
const iceRelax := 0.15    # 冰量弛豫率
const seaK := 0.005       # 冰量偏离→海平面偏移(高程单位)
const SEA_BASE := 0.82    # geo 缺省时的海平面基准

# ---------- 33 元素化学底物(从 world.html;全球网格版,逐元素守恒)----------
const NE := 33
const MN := ["钠","钙","镁","钾","铁","氯","硫酸盐","碳酸盐","硅","铜","碘","锌","锡","铅","银","金","硫","碳","硝","磷","汞","硼","氟","铀","钍","铝","锰","钛","镍","铬","钼","钴","硒"]
const SEAREF := [3000.0,110.0,360.0,110.0,0.5,5390.0,750.0,30.0,1.0,0.1,20.0,0.5,0.0,0.0,0.0,0.0,2.0,0.0,5.0,0.1,0.0,5.0,1.0,3.3,0.0,0.0,0.0,0.0,0.5,0.2,10.0,0.0,0.1]  # 海水本底谱
const ESOL := [8.0,0.4,2.0,3.0,0.05,9.0,1.2,0.6,0.08,0.03,12.0,0.2,0.002,0.004,0.003,0.0005,0.5,0.1,10.0,0.05,0.001,1.5,0.8,0.01,0.0002,0.001,0.3,0.0005,0.05,0.02,0.4,0.05,0.3]  # 溶解度上限
const EREL := [0.05,0.30,0.40,0.05,0.35,0.02,0.08,0.15,0.20,0.30,0.0,0.15,0.01,0.02,0.01,0.005,0.30,0.0,0.0,0.15,0.08,0.0,0.03,0.01,0.02,0.20,0.20,0.30,0.25,0.30,0.0,0.20,0.02]  # 风化释放谱(玄武岩/平均洋壳)
const WK := 0.0006        # 风化基率
const E_BURY := 5e-4      # 海洋埋藏率(对超本底)
const E_RETURN := 0.03    # 俯冲池→火山返还(每地质年)
var disE := PackedFloat64Array()    # 各格溶解元素,索引 k*NE+e
var depE := PackedFloat64Array()    # 各格沉积元素
var subPoolE := PackedFloat64Array()  # 俯冲池(全局,NE)
var rockE := PackedFloat64Array()     # 岩石/地幔元素源(全局,NE)

var globalCO2 := 2.0
const CO2ref := 2.0
const cGhouse := 2.2
const volcOut := 0.3
const weatherK := 0.2        # 风化率(局部化后所有格都风化=等效原全局风化,恒温器自稳)
const bioK := 0.1
const VPULSE_T := 40
const VPULSE_A := 3.0
# —— 守恒账本(从 world.html 搬:碳 4 库闭合 + 大氧化 GOE + 氮两库)。总量只在库间搬,守恒 ——
var ocnC: float = 2.0       # 海洋溶解碳库
var fosC: float = 0.0       # 化石/沉积有机碳库
var organicC: float = 0.0   # 史前有机汤碳库(=Org 之和×cOrgK,守恒)
var bioC: float = 0.0       # 生物量碳库(生命固碳/吃汤→此,呼吸→局部CO2,死亡→化石/碎屑,守恒)
var o2Prod: float = 0.0     # 光合产氧累积(stepLife 累加,carbonStep 用于 GOE 后清零)
var rockC: float = 10000.0  # 岩石+地幔碳库(火山源/风化汇)
const seaExK := 0.05        # 海气碳交换率
const buryK := 0.05         # 生物碳泵:净埋藏率(大气→化石,放等量 O₂)。温和→火山≈风化+埋藏,大气CO2自稳
const co2Diff := 0.2        # 大气 CO2 四邻混合率(局部场扩散)
const foxCK := 0.002        # 化石出露氧化率(→大气)
var globalO2: float = 0.0   # 大气 O₂(%)
var globalRed: float = 4.0  # 还原缓冲库(海洋Fe²⁺/火山还原气)→压住早期 O₂,耗尽才 GOE
const o2ResupD := 0.02      # 火山还原气补给(当场吃 O₂)
const o2RespK := 0.02       # 净耗氧
const redSupK := 0.01       # 还原物持续补给
var atmN2: float = 1000.0   # 大气 N₂ 库
var availN: float = 2.0     # 可用氮(生物可取)
const nfixGK := 0.05        # 固氮率(N₂→可用)
const denitGK := 0.03       # 反硝化率(可用→N₂,缺氧强)
const sFixK := 0.02         # 闪电固氮率(非生物,暖湿→雷暴;生命前也供氮)

var geoT := 0

func _init() -> void:
	_LAT.resize(NLat); _UB.resize(NLat)
	UMAX = 1.0
	for j in NLat:
		_LAT[j] = -90.0 + (j + 0.5) * 180.0 / NLat
		_UB[j] = uband(_LAT[j])
		UMAX = max(UMAX, abs(_UB[j]))
	for buf in [_s0, _sl0, _t1, _flow, _fTo, _fSa, _fDr]: buf.resize(SZ)
	_comp.resize(SZ)

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
func gridF(v: float) -> PackedFloat64Array:
	var g := PackedFloat64Array(); g.resize(SZ); g.fill(v); return g
func nearSea(j: int, i: int, dc: float) -> float:
	var jb := j * NLon
	for d in range(1, NLon / 2 + 1):
		var il := posmod(i - d, NLon)
		var ir := (i + d) % NLon
		if Land[jb + il] == 0: return S[jb + il]
		if Land[jb + ir] == 0: return S[jb + ir]
	return max(-2.0, eqT(_LAT[j], dc))

# ---------- 气候一日 ----------
func stepDay(d: int) -> void:
	var dc := decl(d)
	for k in SZ: _s0[k] = S[k]
	for k in SZ: _sl0[k] = SAL[k]
	for j in NLat:
		var jb := j * NLon
		var jl: int = max(0, j - 1) * NLon
		var jr: int = min(NLat - 1, j + 1) * NLon
		var lat := _LAT[j]
		var eqO: float = max(-2.0, eqT(lat, dc))
		var pb := precipBand(lat, dc)
		for i in NLon:
			var k := jb + i
			if Land[k] != 0: continue
			S[k] += OceanInertia * (eqO - _s0[k]) + OceanHeatMix * ((_s0[jl + i] + _s0[jr + i]) / 2.0 - _s0[k])
			var ev: float = max(0.0, _s0[k]) / 30.0
			SAL[k] += SalRate * (ev - 1.6 * pb) + SalMix * ((_sl0[jl + i] + _sl0[jr + i]) / 2.0 - _sl0[k])
	# 大洋经向翻转环流(MOC)
	var dens := 0.0
	var n := 0
	for j in NLat:
		if abs(_LAT[j]) < 50.0: continue
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			if Land[k] != 0: continue
			dens += 0.8 * (SAL[k] - 34.5) - 0.12 * (S[k] - 10.0) - FRESH
			n += 1
	var tgt: float = max(0.0, (dens / n) * MOCgain if n > 0 else 0.0)
	MOC += 0.05 * (tgt - MOC)
	for j in NLat:
		var a: float = abs(_LAT[j])
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			if Land[k] != 0: continue
			if a >= 50.0: S[k] += MOCheat * MOC
			elif a < 35.0: S[k] -= MOCheat * MOC * 0.5
	# 大气温度
	for j in NLat:
		var jb := j * NLon
		var eqA := eqT(_LAT[j], dc)
		for i in NLon:
			var k := jb + i
			if Land[k] != 0: T[k] += LandInertia * (eqA - T[k])
			else: T[k] += SeaCouple * (S[k] - T[k])
	# 纬向平流
	for k in SZ: _t1[k] = T[k]
	for j in NLat:
		var jb := j * NLon
		var u := _UB[j]
		var w: float = min(1.0, abs(u) / UMAX)
		var up := -1 if u > 0.0 else 1
		for i in NLon:
			var iu := posmod(i + up, NLon)
			T[jb + i] += Adv * w * (_t1[jb + iu] - _t1[jb + i])
			U[jb + i] = u
	# 降水
	for j in NLat:
		var jb := j * NLon
		var base := precipBand(_LAT[j], dc)
		for i in NLon:
			var k := jb + i
			var p := base
			if Land[k] != 0:
				var dT: float = T[k] - nearSea(j, i, dc)
				p *= 1.0 + 0.5 * max(0.0, min(1.0, dT / 8.0)) - 0.4 * max(0.0, min(1.0, -dT / 8.0))
			P[k] = max(0.0, min(1.2, p))
	# 西边界流增冷
	for j in NLat:
		var a: float = abs(_LAT[j])
		if a < 18.0 or a > 42.0: continue
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			if Land[k] != 0: continue
			if Land[jb + (i + 1) % NLon] != 0: S[k] -= GyreCool
	# 气压带 + 锋面
	var PBELT := 20.0
	var PKT := 2.0
	for j in NLat:
		var jb := j * NLon
		var belt := -PBELT * cos(2.0 * PI * abs(_LAT[j]) / 60.0)
		var m := 0.0
		for i in NLon: m += T[jb + i]
		m /= NLon
		for i in NLon: PR[jb + i] = 1013.0 + belt - PKT * (T[jb + i] - m)
	for j in NLat:
		var jb := j * NLon
		var jl: int = max(0, j - 1) * NLon
		var jr: int = min(NLat - 1, j + 1) * NLon
		for i in NLon: FR[jb + i] = abs(T[jr + i] - T[jl + i]) / 2.0

func initClimate() -> void:
	Land = PackedByteArray(); Land.resize(SZ)
	T = gridF(0.0); S = gridF(0.0); SAL = gridF(34.5)
	P = gridF(0.0); U = gridF(0.0); PR = gridF(1013.0); FR = gridF(0.0)
	for j in NLat:
		var jb := j * NLon
		var lat := _LAT[j]
		var e0: float = max(-2.0, eqT(lat, 0.0))
		for i in NLon:
			var k := jb + i
			var isl: bool = false if WATERWORLD else (land_mask[j][i] if land_mask != null else isLand(i))
			Land[k] = 1 if isl else 0
			T[k] = eqT(lat, 0.0)
			S[k] = e0

# ---------- 生命层 ----------
func Teff(j: int, i: int) -> float:
	return T[j * NLon + i] + cGhouse * (globalCO2 - CO2ref) - climCool * pow(abs(_LAT[j]) / 90.0, 1.3) * 2.0 - impactWinter
func updateHab() -> void:
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var tFit := exp(-pow((Teff(j, i) - 25.0) / 16.0, 2.0))
			var water: float = P[k] if Land[k] != 0 else 1.0
			Hab[k] = clampf(tFit * sqrt(max(0.0, water)), 0.0, 1.0)
func envSalt(j: int, i: int) -> float:
	var k := j * NLon + i
	return 0.0 if Land[k] != 0 else SAL[k]
func envDry(j: int, i: int) -> float:
	var k := j * NLon + i
	return (1.0 - P[k]) if Land[k] != 0 else 0.0

func stepLife(dt: float) -> void:
	updateHab()
	var aT := 1.0 - exp(-0.05 * dt)
	var aS := 1.0 - exp(-0.04 * dt)
	var aD := 1.0 - exp(-0.05 * dt)
	# 史前有机化学(world.html 564-567):org/prot/lip 三库张弛 合成→聚合↔水解→降解,跨阈点燃生命。
	# ⚠ 局部底座未建:energy(闪电charge/喷口freeEnergy)、co2/o2/redox 暂用全局近似;
	#    feed 的氮暂用全局 availN,催化 cat 已接每格 depE(硫/镍)。待局部化学状态层建好再接局部。
	var redox := clampf(globalO2 / 5.0, 0.0, 1.0)
	var nAvail := clampf(availN / 3.0, 0.0, 1.0)
	var eChem := 0.4 + 0.6 * clampf(globalRed / 4.0, 0.0, 1.0)
	var dwO := OCHEM * dt / 10.0
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var ke := k * NE
			var tf := Teff(j, i)
			var warm := clampf((tf + 5.0) / 25.0, 0.0, 1.0) * clampf((60.0 - tf) / 40.0, 0.0, 1.0)
			var feed := clampf(Co2[k] / 2.0, 0.0, 1.0) * nAvail * (1.0 - redox)      # 原料:局部CO₂×氮×还原环境
			var cat := clampf((depE[ke + 16] + depE[ke + 28]) / 2.0, 0.0, 0.8)        # 局部矿物表面催化(硫/镍 depE)
			var water := Hab[k]                                                       # 含水近似(待每格 Soil/Lake)
			var conc := clampf((1.0 - water) + 0.8 * cat, 0.0, 1.5)                   # 浓缩:干涸+吸附
			var energy := 0.6 * warm + eChem                                         # 能量:闪电(暖→对流代理)+喷口还原(对齐 world 0.6×charge+freeEnergy)
			var org := Org[k]; var prot := Prot[k]; var lip := Lip[k]
			var syn := oSynK * energy * feed * dwO
			var poly := oPolyK * org * org * conc * cat * dwO
			var hyd := oHydK * prot * clampf(water, 0.0, 1.0) * dwO
			var dec := oDecK * (org + prot) * (1.0 + 5.0 * redox) * dwO
			var nOrg := maxf(0.0, org + syn + hyd - poly - 0.5 * dec)
			var nProt := maxf(0.0, prot + poly - hyd - 0.5 * dec)
			var nLip := maxf(0.0, lip + lipFrac * syn - lipDecay * lip)
			var dco := oCfrac * ((nOrg - org) + (nProt - prot) + (nLip - lip))        # 想从局部大气转移的碳
			if dco > Co2[k]: dco = Co2[k]                                             # 受局部 CO2 限,不凭空造碳
			Co2[k] -= dco                                                            # 合成扣局部CO2/降解还(三库碳由 organicC 实时反映)
			Org[k] = nOrg; Prot[k] = nProt; Lip[k] = nLip
			if N[k] < SEED and (nOrg + nProt) > ORG_IGNITE and Hab[k] > 0.05:         # 汤(org+prot)够浓→点燃
				N[k] = SEED; Topt[k] = Teff(j, i); Salt[k] = envSalt(j, i); Dry[k] = envDry(j, i)
	# organicC 不在此累积,由 carbonStep 末尾按 Σ三库实时算(与吃汤消耗一致,根除累积漂移)
	# 增长 + 本地适应 + 形态发育
	for j in NLat:
		var jb := j * NLon
		var moveBase := clampf(0.3 + 0.45 * abs(_LAT[j]) / 90.0 + 0.3 * climCool / ICE_AMP, 0.0, 1.0)
		for i in NLon:
			var k := jb + i
			if N[k] <= 0.0: continue
			var teff := Teff(j, i)
			var es := envSalt(j, i)
			var ed := envDry(j, i)
			var fT := exp(-pow((Topt[k] - teff) / FITW, 2.0))
			var fS := exp(-pow((Salt[k] - es) / SALTW, 2.0))
			var fD := exp(-pow((Dry[k] - ed) / DRYW, 2.0))
			var fit := fT * fS * fD
			# 三代谢能量预算(world.html 582-597):异养(吃汤)/化能(还原剂)/光合(光);收入-维持-死亡→饿死。
			# ⚠ redu/o2 暂用全局 globalRed/globalO2 近似(待局部);co2/food/碳流已局部,经 bioC 守恒。
			var nn := N[k]
			var food := Org[k] + Prot[k]
			var co2a := clampf(Co2[k] / 2.0, 0.0, 1.0)
			var a := clampf(rAuto[k], 0.0, 1.0)
			var p := clampf(rPhoto[k], 0.0, 1.0)
			var o2f := clampf(globalO2 / o2half, 0.0, 1.0)
			var aerB := 1.0 + aerBoost * clampf(rAero[k], 0.0, 1.0) * o2f + euBoost * clampf(rEuk[k], 0.0, 1.0) * o2f
			var szSlow := 1.0 - sizeCost * clampf(rSize[k], 0.0, 1.0) * (1.0 - 0.5 * clampf(rEuk[k], 0.0, 1.0))
			var gB := aerB * szSlow * Hab[k] * (1.0 - 0.3 * clampf(rMulti[k], 0.0, 1.0)) * (1.0 - diffRepCost * clampf(rDiff[k], 0.0, 1.0)) * (1.0 - shellGrowCost * clampf(rShell[k], 0.0, 1.0))   # ×多细胞/分化/壳 增殖代价
			var wHet := rBirthK * (food / (food + rKhalf)) * fit * gB
			var wChemo := rBirthAutoK * clampf(globalRed / 4.0, 0.0, 1.0) * co2a * fit * gB
			var wPhoto := rBirthPhotoK * clampf(Hab[k] * 1.6, 0.0, 1.0) * co2a * fit * gB
			var dl := dt / 10.0
			var realHet: float = minf(wHet * nn * (1.0 - a) * dl, food * rYield)
			var realChemo: float = maxf(0.0, minf(wChemo * nn * a * (1.0 - p) * dl, (Co2[k] - 0.05) / cFixK))
			var realPhoto: float = maxf(0.0, minf(wPhoto * nn * a * p * dl, (Co2[k] - 0.05) / cFixK))
			var income := realHet + realChemo + realPhoto
			var tempMet := clampf(0.6 + 0.4 * (teff + 5.0) / 25.0, 0.4, 1.8)
			var maint := rMaintK * nn * tempMet * dl
			var deaths := rDeathK * nn * (1.0 + extinctK * (1.0 - fit)) * dl
			# 碳流(守恒,经 bioC):吃汤碳→bioC;固局部CO2→bioC;呼吸 bioC→局部CO2
			var fr: float = minf(1.0, (realHet / rYield) / maxf(food, 1e-6))
			var cEat := oCfrac * food * fr
			Org[k] *= (1.0 - fr); Prot[k] *= (1.0 - fr)
			bioC += cEat / float(SZ)                                             # 汤碳→生物碳(organicC 由 carbonStep 按Σ三库实时算)
			var fixC: float = minf(cFixK * (realChemo + realPhoto), Co2[k])
			Co2[k] -= fixC; bioC += fixC / float(SZ)                             # 固局部CO2→生物碳(均值)
			var respC: float = respCK * maint
			bioC -= respC / float(SZ); Co2[k] += respC                           # 呼吸:生物碳→局部CO2
			o2Prod += o2YieldK * realPhoto
			N[k] = maxf(0.0, nn + income - maint - deaths)
			# 代谢型适应:自养(化能/光合更优)↔异养;光合↔化能
			if N[k] > 1e-3:
				rAuto[k] = clampf(a + rAutoAdaptK * dl * (maxf(wChemo, wPhoto) - wHet), 0.0, 1.0)
				rPhoto[k] = clampf(p + rAutoAdaptK * dl * (wPhoto - wChemo), 0.0, 1.0)
				rAero[k] = clampf(rAero[k] + rAeroAdaptK * dl * (aerBoost * o2f + 3.0 * redox - aerCostSel), 0.0, 1.0)   # 富氧→好氧度升,缺氧→纯成本归零
				var szc := clampf(rSize[k], 0.0, 1.0)
				rEuk[k] = clampf(rEuk[k] + euAdaptK * dl * (euGain * o2f * clampf(szc * 2.0, 0.0, 1.0) - euCost), 0.0, 1.0)   # 富氧+体型→真核化
				var predP := clampf(H[k] / 5.0, 0.0, 1.0)
				rSize[k] = clampf(rSize[k] + sizeAdaptK * dl * (predP * 0.5 + 0.3 - 0.4), 0.0, 1.0)   # 捕食压→大体型(防御)
				var euG := clampf(rEuk[k] * 2.0, 0.0, 1.0)
				rMulti[k] = clampf(rMulti[k] + multiAdaptK * dl * (euG * predP * multiDef - multiCost), 0.0, 1.0)   # 真核×捕食压→多细胞
				var muG := clampf(rMulti[k] * 2.0, 0.0, 1.0)
				rDiff[k] = clampf(rDiff[k] + diffAdaptK * dl * (muG * (0.6 + predP * 0.5) - diffCost), 0.0, 1.0)   # 多细胞×(稳定+捕食)→分化
				var minAvail := clampf(disE[k * NE + 1] / 150.0, 0.0, 1.0)
				rShell[k] = clampf(rShell[k] + shellAdaptK * dl * (muG * predP * minAvail - shellCost), 0.0, 1.0)   # 多细胞×捕食×钙→壳
			# 有性生殖加速适应(红皇后:有性投资→适应更快)
			var sb: float = 1.0 + SEX_BOOST * rSex[k]
			Topt[k] += min(0.99, aT * sb) * (teff - Topt[k])
			Salt[k] += min(0.99, aS * sb) * (es - Salt[k])
			Dry[k] += min(0.99, aD * sb) * (ed - Dry[k])
			# rSex 演化:复杂度门 ×(失配 + 寄生压)→升;成本拉回克隆
			var gate := clampf(Sym[k] * 2.0, 0.0, 1.0)
			var paraP := clampf(Par[k] / 5.0, 0.0, 1.0)
			rSex[k] = clampf(rSex[k] + SEX_K * (gate * ((1.0 - fit) * 1.2 + paraP * 0.8) - SEX_COST), 0.0, 1.0)
			# 寄生(载量∝宿主密度,有性抗性压制 = 红皇后):rSex=1 时完全抗性→压垮寄生
			if parasitesOn:
				if N[k] > PAR_SEEDN and Par[k] < SEED: Par[k] = SEED
				if Par[k] > 0.0:
					if N[k] > 0.1:
						var hostD := clampf(N[k] / (N[k] + 10.0), 0.0, 1.0)
						var resist := clampf(1.0 - rSex[k], 0.0, 1.0)
						var kill: float = min(PAR_KILL * Par[k] * hostD * (dt / 10.0), N[k] * 0.4)
						N[k] = N[k] - kill
						Par[k] = clampf(Par[k] + (PAR_GROW * hostD * resist - PAR_DECAY) * Par[k] * (dt / 10.0), 0.0, PAR_MAX)
					else:
						Par[k] = max(0.0, Par[k] * (1.0 - PAR_DECAY * (dt / 10.0)))
			var sizeP := clampf(N[k] / Kmax, 0.0, 1.0)
			var gS := clampf((Sym[k] - MGATE) / MGW, 0.0, 1.0)
			var gG := clampf((Seg[k] - MGATE) / MGW, 0.0, 1.0)
			Sym[k] = clampf(Sym[k] + morphK * (moveBase - Sym[k] - morphCost), 0.0, 1.0)
			Seg[k] = clampf(Seg[k] + morphK * (gS * moveBase - Seg[k] - morphCost), 0.0, 1.0)
			Limb[k] = clampf(Limb[k] + morphK * (gG * moveBase - Limb[k] - morphCost), 0.0, 1.0)
			Axis[k] = clampf(Axis[k] + morphK * (gS * sizeP - Axis[k] - morphCost), 0.0, 1.0)
	# 四邻扩散 + 带性状迁移(守恒)
	_flow.fill(0.0); _fTo.fill(0.0); _fSa.fill(0.0); _fDr.fill(0.0)
	var f := clampf(MOVE * dt / 10.0, 0.0, 0.24)
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var nv := N[k]
			if nv <= 0.0: continue
			var nb := [jb + (i + 1) % NLon, jb + posmod(i - 1, NLon)]
			if j > 0: nb.append((j - 1) * NLon + i)
			if j < NLat - 1: nb.append((j + 1) * NLon + i)
			for bk in nb:
				var bar := BARRIER if Land[k] != Land[bk] else 1.0
				var mv: float = f * bar * max(0.0, (nv - N[bk]) * 0.5) * Hab[bk]
				_flow[k] -= mv; _flow[bk] += mv
				_fTo[bk] += mv * Topt[k]; _fSa[bk] += mv * Salt[k]; _fDr[bk] += mv * Dry[k]
	for k in SZ:
		if _flow[k] > 0.0:
			var tot := N[k] + _flow[k]
			if tot > 0.0:
				Topt[k] = (Topt[k] * N[k] + _fTo[k]) / tot
				Salt[k] = (Salt[k] * N[k] + _fSa[k]) / tot
				Dry[k] = (Dry[k] * N[k] + _fDr[k]) / tot
		N[k] = max(0.0, N[k] + _flow[k])

	# ---------- 食物网:N(生产者)→ H(食草)→ C(食肉),Holling-II ----------
	var ds := dt / 10.0
	for k in SZ:
		var nv := N[k]
		if H[k] < SEED and nv > FW_SEEDN: H[k] = SEED
		if H[k] > 0.0:
			var graze: float = min(FW_GRAZE * H[k] * (nv / (nv + FW_HALF)) * ds, nv * 0.5)
			N[k] = nv - graze
			H[k] = max(0.0, H[k] + FW_YIELD * graze - FW_MH * H[k] * ds)
		var hv := H[k]
		if C[k] < SEED and hv > FW_SEEDH: C[k] = SEED
		if C[k] > 0.0:
			var graze2: float = min(FW_GRAZE * C[k] * (hv / (hv + FW_HALF)) * ds, hv * 0.5)
			H[k] = hv - graze2
			C[k] = max(0.0, C[k] + FW_YIELD * graze2 - FW_MC * C[k] * ds)
	_diffuse(H, FW_DIFF * ds)
	_diffuse(C, FW_DIFF * ds)
	_diffuse(Par, FW_DIFF * ds)
	var soC := 0.0
	var scC := 0.0
	for k in SZ:
		soC += Org[k] + Prot[k] + Lip[k]; scC += Co2[k]
	organicC = oCfrac * soC / float(SZ)                                          # 末尾刷新有机碳库(=Σ三库)
	globalCO2 = scC / float(SZ)                                                  # 末尾刷新 globalCO2(stepLife 改了局部 Co2,否则测量滞后)

func _diffuse(F: PackedFloat64Array, rate: float) -> void:   # 四邻扩散(守恒),复用 _flow 缓冲
	_flow.fill(0.0)
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var v := F[k]
			if v <= 0.0: continue
			var nb := [jb + (i + 1) % NLon, jb + posmod(i - 1, NLon)]
			if j > 0: nb.append((j - 1) * NLon + i)
			if j < NLat - 1: nb.append((j + 1) * NLon + i)
			for bk in nb:
				var mv: float = rate * max(0.0, (v - F[bk]) * 0.5)
				_flow[k] -= mv; _flow[bk] += mv
	for k in SZ: F[k] = max(0.0, F[k] + _flow[k])

# ---------- 物种 / 谱系 / 大灭绝 ----------
func extinctionCause() -> String:
	if impactWinter > 6.0: return "☄撞击冬天"
	if globalCO2 > CO2ref * 2.0: return "🌋暖室·海洋酸化"
	if climCool > 12.0: return "❄️大冰期"
	if climCool > 6.0: return "❄️冰期降温"
	if globalO2 < 2.0: return "🅾缺氧海(O₂不足)"
	return "环境胁迫"
func massExtinctionCheck(ext: int) -> void:
	var alive := phylo.filter(func(p): return p["deathY"] < 0).size()
	var thr: float = max(max(2.0, alive * 0.3), extEMA * 2.2)
	var last: float = massExt[-1]["ky"] if massExt.size() > 0 else -1e9
	if ext > thr and geoT > 1 and (geoT - last) >= ICE_PERIOD * 0.4:
		var cause := extinctionCause()
		massExt.append({"ky": geoT, "lost": ext, "cause": cause})
		if massExt.size() > 40: massExt.pop_front()
		_push_event("💀", "大灭绝 · %s · 损 %d 种" % [cause, ext])
	extEMA += 0.12 * (ext - extEMA)

func updateSpecies() -> int:
	_comp.fill(-1)
	var nc := 0
	var members := []
	for j in NLat:
		for i in NLon:
			var k := j * NLon + i
			if _comp[k] >= 0 or N[k] <= SEED: continue
			var st := [[j, i]]
			_comp[k] = nc
			var mem := []
			while st.size() > 0:
				var c = st.pop_back()
				var cj: int = c[0]; var ci: int = c[1]
				var ck := cj * NLon + ci
				mem.append(c)
				var nb := [[cj, (ci + 1) % NLon], [cj, posmod(ci - 1, NLon)]]
				if cj > 0: nb.append([cj - 1, ci])
				if cj < NLat - 1: nb.append([cj + 1, ci])
				for nn in nb:
					var nj: int = nn[0]; var ni: int = nn[1]
					var nk := nj * NLon + ni
					if _comp[nk] < 0 and N[nk] > SEED and Land[nk] == Land[ck] and floor(Topt[nk] / TBUCKET) == floor(Topt[ck] / TBUCKET):
						_comp[nk] = nc; st.append(nn)
			members.append(mem); nc += 1
	# 每个连通分量找它最大的旧物种(继承祖先)
	var compOld := []
	for c in nc:
		var cnt := {}
		for m in members[c]:
			var o: int = spId[m[0] * NLon + m[1]]
			if o > 0: cnt[o] = cnt.get(o, 0) + 1
		var best := 0; var bo := 0
		for k in cnt:
			if cnt[k] > best: best = cnt[k]; bo = k
		compOld.append(bo)
	# 大分量先继承 id,裂出的次要分量记新种(异域分支)
	var order := []
	for c in nc: order.append(c)
	order.sort_custom(func(a, b): return members[a].size() > members[b].size())
	var seen := {}
	for c in order:
		var old: int = compOld[c]
		var s := 0.0; var w := 0.0
		for m in members[c]:
			var mk: int = m[0] * NLon + m[1]
			s += Topt[mk] * N[mk]; w += N[mk]
		var mean := s / w if w > 0.0 else 0.0
		var land = Land[members[c][0][0] * NLon + members[c][0][1]]
		var id: int
		if old == 0:
			id = nextSp; nextSp += 1
			phylo.append({"id": id, "parent": -1, "bornY": geoT, "deathY": -1, "Topt": snappedf(mean, 0.1), "land": land})
		elif not seen.has(old):
			id = old; seen[old] = true
		else:
			id = nextSp; nextSp += 1
			phylo.append({"id": id, "parent": old, "bornY": geoT, "deathY": -1, "Topt": snappedf(mean, 0.1), "land": land})
		for m in members[c]: spId[m[0] * NLon + m[1]] = id
	# 灭绝判定
	var live := {}
	for k in SZ:
		if spId[k] > 0 and N[k] > SEED: live[spId[k]] = true
	var ext := 0
	for p in phylo:
		if p["deathY"] < 0 and not live.has(p["id"]): p["deathY"] = geoT; ext += 1
	for k in SZ:
		if N[k] <= SEED: spId[k] = 0
	if phylo.size() > 2000: phylo = phylo.slice(phylo.size() - 2000)
	return ext

func carbonStep() -> void:
	var bio := 0.0
	for k in SZ: bio += N[k]
	# 碳:4 库(大气 globalCO2 / 海洋 ocnC / 化石 fosC / 岩石+地幔 rockC)间只搬运,总量守恒
	# 大气 CO2 局部化(每格 Co2[k]=该格大气碳,ΣCo2=大气总量,extensive 守恒):
	# 火山/化石氧化注入,风化(陆)/海气(海)/埋藏(生命)逐格作用;rockC/ocnC/fosC 为总量库。
	rockC -= volcOut                                                              # 火山:岩石→大气
	var pulse: float = VPULSE_A if (geoT > 0 and geoT % VPULSE_T == 0) else 0.0
	rockC -= pulse                                                               # 暗色岩省脉冲
	var oxid := foxCK * fosC; fosC -= oxid                                        # 化石出露氧化→大气
	var injPer := volcOut + pulse + oxid                                          # 每格大气注入(mean += injPer)
	var wTot := 0.0; var oTot := 0.0
	for k in SZ:
		var c := Co2[k] + injPer
		var tempf := clampf(1.0 + 0.06 * (c - CO2ref), 0.4, 3.0)                 # 暖→风化快(恒温器负反馈)
		var wq: float = minf(c, weatherK * (c / CO2ref) * tempf)
		c -= wq; wTot += wq                                                      # 风化:所有格大气→岩石(陆地碳硅酸盐+海底风化,恒温器汇)
		if Land[k] == 0:
			var dOcn := seaExK * (c - ocnC); c -= dOcn; oTot += dOcn             # 海洋额外:海气交换趋平衡
		Co2[k] = maxf(0.0, c)
	rockC += wTot / float(SZ); ocnC += oTot / float(SZ)                          # 风化/海气汇入全局库(守恒)
	# 生物碳泵 + 再矿化:生物量碳 bioC 一部分埋藏成化石(锁碳放O₂),一部分氧化回大气(守恒)
	var buryB := buryK * clampf(bioC / 50.0, 0.0, 2.0)
	bioC -= buryB; fosC += buryB
	var remin := reminK * bioC; bioC -= remin
	for k in SZ: Co2[k] += remin                                                 # 库→每格大气加全量(mean 增 remin = bioC 减,守恒)
	_diffuse(Co2, co2Diff)                                                        # 大气混合
	var sc := 0.0
	var so := 0.0
	for k in SZ:
		sc += Co2[k]; so += Org[k] + Prot[k] + Lip[k]
	globalCO2 = sc / float(SZ)                                                    # 全局指标=场均浓度
	organicC = oCfrac * so / float(SZ)                                           # 有机碳库=Σ三库实时(与史前化学/吃汤一致,免累积漂移)
	# 氧(GOE):净埋藏有机碳=放等量 O₂;先被火山还原气 + 还原缓冲库吃,库耗尽才阈值式跃升
	var avail := o2Prod / float(SZ); o2Prod = 0.0                                 # GOE 用光合产氧(均值量纲),用后清零
	var byGas: float = min(avail, o2ResupD); avail -= byGas
	var byRed: float = min(avail, globalRed * 0.02); avail -= byRed; globalRed = max(0.0, globalRed - byRed)
	globalO2 = clampf(globalO2 + avail - o2RespK * globalO2, 0.0, 21.0)
	globalRed = min(500.0, globalRed + redSupK)                                  # 火山持续补还原物
	# 氮:固氮(N₂→可用)↔反硝化(可用→N₂,缺氧强),两库守恒
	var anox := clampf(1.0 - globalO2 / 5.0, 0.0, 1.0)
	var lightFix: float = sFixK * clampf(globalCO2 / CO2ref, 0.5, 2.0) * clampf(1.0 - availN / 5.0, 0.0, 1.0)   # 闪电固氮(非生物,暖湿→雷暴多;生命前也供氮)
	atmN2 -= lightFix; availN += lightFix
	var fix: float = nfixGK * clampf(bio / 5000.0, 0.0, 1.0) * clampf(1.0 - availN / 5.0, 0.0, 1.0)
	atmN2 -= fix; availN += fix
	var den := denitGK * availN * anox; availN -= den; atmN2 += den

func elementStep() -> void:   # 33 元素:风化(岩→溶)→溶解度沉淀(溶→沉)→海洋埋藏(溶→俯冲)→火山返还。逐元素守恒
	var cf: float = max(0.1, globalCO2 / CO2ref)
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var base := k * NE
			var water: float = (P[k] if Land[k] != 0 else 1.0)
			if Land[k] != 0:
				var act: float = clampf(water, 0.0, 1.0) * clampf((T[k] + 5.0) / 25.0, 0.0, 1.5) * cf
				for e in NE:
					var rel: float = min(WK * float(EREL[e]) * act, rockE[e])
					rockE[e] -= rel; disE[base + e] += rel
			var wcap: float = max(0.05, water)
			for e in NE:
				var cap: float = float(ESOL[e]) * wcap
				var d: float = disE[base + e]
				if d > cap and Land[k] != 0:   # 溶解度沉淀只在陆地/蒸发,海洋靠埋藏稳在 SEAREF
					var pp: float = (d - cap) * 0.2
					disE[base + e] = d - pp; depE[base + e] += pp
			if Land[k] == 0:
				for e in NE:
					var exc: float = disE[base + e] - float(SEAREF[e])
					if exc > 0.0:
						var b: float = E_BURY * exc
						disE[base + e] -= b; subPoolE[e] += b
	for e in NE:                       # 俯冲池→火山返还(分摊各格溶解,守恒)
		var ret: float = E_RETURN * subPoolE[e]
		if ret <= 0.0: continue
		subPoolE[e] -= ret
		var per: float = ret / SZ
		for k in SZ: disE[k * NE + e] += per

func effSea() -> float:                       # 当前有效海平面阈值(高程单位)
	return (geo.SEA if geo != null else SEA_BASE) + seaOffset
func _seaStep() -> void:                       # 冰量↔海平面,守恒;冰多→海退→重算海陆
	var target := iceAccK * climCool
	iceVol += iceRelax * (target - iceVol)
	if refIce < 0.0: refIce = iceVol
	seaOffset = -seaK * (iceVol - refIce)
	if geo != null:
		var m = geo.coarse_land_at(NLat, NLon, effSea())
		for j in NLat:
			var jb := j * NLon
			for i in NLon: Land[jb + i] = 1 if m[j][i] else 0

func stepGeo() -> void:
	geoT += 1
	var milank := 1.0 - milankDepth * (0.5 + 0.5 * sin(2.0 * PI * geoT / MILANK_T))   # 米兰科维奇:轨道慢周期调制冰期强弱
	climCool = ICE_AMP * milank * clampf(sin(2.0 * PI * geoT / ICE_PERIOD), 0.0, 1.0)
	impactWinter = maxf(0.0, impactWinter * (1.0 - impactDecay))                       # 撞击冬天逐年衰减(尘埃沉降)
	if geoT % IMPACT_T == 0:                                                           # 确定性周期撞击
		impactWinter += IMPACT_WINTER
		var ic: float = minf(rockC, IMPACT_CO2); rockC -= ic; for ck in SZ: Co2[ck] += ic   # 撞击气化注碳(岩石→每格大气,守恒)
		_push_event("☄", "天体撞击 · 撞击冬天 + 注碳脉冲")
	if geo != null:
		var erupt: int = geo.tectonics()        # 火山抬升/侵蚀改高程
		if erupt > 0:                            # 喷发注碳(岩石/地幔→大气,守恒)
			var pulse: float = min(rockC, erupt * 0.5)
			rockC -= pulse; for ck in SZ: Co2[ck] += pulse                             # 火山喷发注碳(岩石→每格大气,守恒)
	_seaStep()
	carbonStep()
	elementStep()
	massExtinctionCheck(updateSpecies())
	_track_events()

func _push_event(icon: String, text: String) -> void:
	events.append({"ky": geoT, "icon": icon, "text": text})
	if events.size() > 200: events.pop_front()

func _track_events() -> void:
	if not _seen_life:
		var any := false
		for k in SZ:
			if N[k] > SEED: any = true; break
		if any: _seen_life = true; _push_event("🌱", "生命起源")
	var ice_now := climCool > 6.0
	if ice_now and not _in_ice: _push_event("❄️", "冰期降临")
	_in_ice = ice_now
	var warm_now := globalCO2 > CO2ref * 1.8
	if warm_now and not _in_warm: _push_event("🌋", "暖室期开始")
	_in_warm = warm_now

# ---------- 体制(门级)从形态变量涌现 ----------
func bodyPlan(j: int, i: int) -> String:
	var k := j * NLon + i
	var sym: float = Sym[k]; var seg: float = Seg[k]; var limb: float = Limb[k]; var axis: float = Axis[k]
	if sym < 0.4: return "刺胞"
	if axis > 0.5: return "脊索"
	if seg > 0.5 and limb > 0.4: return "节肢"
	if seg > 0.5: return "环节"
	return "蠕虫"

# ---------- 启动:气候预热 ----------
func spinUp() -> void:
	initClimate()
	N = gridF(0.0); H = gridF(0.0); C = gridF(0.0); Hab = gridF(0.0); Topt = gridF(0.0); Salt = gridF(0.0); Dry = gridF(0.0)
	Org = gridF(0.0); Prot = gridF(0.0); Lip = gridF(0.0)
	spId = PackedInt32Array(); spId.resize(SZ)
	rSex = gridF(0.0); Par = gridF(0.0)
	rAuto = gridF(0.0); rPhoto = gridF(0.0); rAero = gridF(0.0); rEuk = gridF(0.0); rSize = gridF(0.0)
	rMulti = gridF(0.0); rDiff = gridF(0.0); rShell = gridF(0.0)
	rNeuro = gridF(0.0); rEndo = gridF(0.0); rSymb = gridF(0.0); rMemb = gridF(0.0)
	Sym = gridF(0.0); Seg = gridF(0.0); Limb = gridF(0.0); Axis = gridF(0.0)
	phylo = []; nextSp = 1; extEMA = 1.0; massExt = []
	events = []; _seen_life = false; _in_ice = false; _in_warm = false
	MOC = 1.0; geoT = 0; climCool = 0.0; globalCO2 = 2.0; impactWinter = 0.0
	iceVol = 0.0; refIce = -1.0; seaOffset = 0.0
	Co2 = gridF(CO2ref); ocnC = 2.0; fosC = 0.0; rockC = 10000.0; globalO2 = 0.0; globalRed = 4.0; atmN2 = 1000.0; availN = 2.0; organicC = 0.0; bioC = 0.0; o2Prod = 0.0
	disE = PackedFloat64Array(); disE.resize(SZ * NE)
	depE = PackedFloat64Array(); depE.resize(SZ * NE)
	subPoolE = PackedFloat64Array(); subPoolE.resize(NE)
	rockE = PackedFloat64Array(); rockE.resize(NE); rockE.fill(100000.0)
	for k in SZ:
		if Land[k] == 0:
			for e in NE: disE[k * NE + e] = float(SEAREF[e])
	for d in 3 * YEAR: stepDay(d % YEAR)
