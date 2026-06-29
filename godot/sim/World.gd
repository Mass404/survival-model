class_name World
extends RefCounted
const ChemS = preload("res://sim/Chem.gd")   # #3 真热力学:Arrhenius 风化温度依赖
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
# A层 基因型→表型(开放式进化地基):每格6基因→sigmoid(Wg−bias)develop出复杂度链6性状,演化作用在基因上(零随机)
var geneE := PackedFloat64Array()   # 每格6基因,索引 k*GENE_K+g(0体型1真核2多胞3壳4神经5温血)
var _devW := []                     # 6×6 发育矩阵(spinUp 确定性构造:对角占优+sin耦合)
const GENE_K := 6
const DEV_BIAS := 2.0               # 发育偏置:gene=0→性状≈0.12(落 sigmoid 响应区,避尾部梯度消失)
const GENE_ETA := 2.0               # 基因梯度学习率(反传)
# B层 开放式进化:种子化随机突变(新颖性来源,逃梯度局部最优)。同 mutSeed→可复现(testsuite 双实例 bit 一致仍成立)
var mutSeed := 1                    # 世界种子(改→不同世界;默认固定→确定可复现)
const MUT_K := 0.08                 # 基因突变幅度/地质年
# B2 真·可变维度开放式:潜在表型维度(程序不预设含义),功能从"环境×选择"涌现=涌现生态位分化
const N_LAT := 8                    # 潜在维度池上限(有效维度数由门控基因演化决定)
const LAT_EFF := 0.04               # 潜在性状对生长弱耦合(小→不挠核心 35/35)
const LAB := 1.5  # E5fix2 strong division-of-labor gain (signal-to-noise test)
const DIVLAB := 8.0  # E5fix3 division reward into rMulti gene gradient
const SENS_EVADE := 0.4
const DFORM := 0.4
const LATR_PROTECT := 0.9  # E5fix5 protect high-d latR from migration averaging
const LAT_ETA := 3.0                # 潜在基因梯度学习率
const GRN_T := 3                    # GRN1 发育迭代步数(性能/动力学权衡)
const NLAT2 := N_LAT * N_LAT        # 调控矩阵元素数/格
const EXPR_COST := 0.015            # B3 每个表达维的代价→简约压力→有效维度数涌现
var latGene := PackedFloat64Array() # 每格 N_LAT 潜在基因(值)
var latGate := PackedFloat64Array() # B3 每维表达门控基因(开/关→有效维度数可变)
var latR := PackedFloat64Array()    # GRN1 每格调控矩阵(N_LAT×N_LAT;0→退化成一次性,演化出网络动力学)
var _latP := PackedFloat64Array()   # GRN1 迭代发育出的潜在表型缓存(SZ*N_LAT)

# ---------- 预分配缓冲 / 缓存 ----------
var _s0 := PackedFloat64Array()
var _sl0 := PackedFloat64Array()
var _t1 := PackedFloat64Array()
var _flow := PackedFloat64Array()
var _fTo := PackedFloat64Array()
var _fSa := PackedFloat64Array()
var _fDr := PackedFloat64Array()
var _fGeneE := PackedFloat64Array()   # IH 继承层:基因组随生物量迁移携带(质量加权=遗传+基因流)
var _fLatGene := PackedFloat64Array()
var _fLatGate := PackedFloat64Array()
var _fLatR := PackedFloat64Array()   # GRN1b 调控矩阵随生物量迁移携带(继承)
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
const FW_HALF := 8.0       # 半饱和猎物量(食草者对生产者)
const FW_HALF_C := 3.0     # 食肉者半饱和(低→稀疏猎物也能立足;粗网格一格=巨大面积)
const FW_GRAZE := 0.5      # 单位捕食者最大摄食压
const FW_YIELD := 0.25     # 营养传递效率
const FW_MH := 0.04        # 食草者死亡率(给反防御裕度,使防御猎物上仍可存活)
const FW_MC := 0.03        # 食肉者死亡率(低→扛过猎物崩,持续共存)
const FW_SEEDN := 5.0      # 生产者够多→点燃食草者
const FW_SEEDH := 1.0      # 食草者够多→点燃食肉者
const FW_DIFF := 0.10      # 消费者扩散率(低→消费者聚集在高产格,单格密度足以支撑上一营养级)
const FW_FORAGE := 0.15  # E3 觅食定向流动强度
const FW_FLEE := 0.10  # E3 flee strength
const FW_MIGR := 0.08  # E3 migrate strength
const FW_HERD := 0.35  # E3 herd defense max reduction
const FW_HERD_HALF := 8.0  # E3 herd defense half-density
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
const neuroForage := 0.4     # 神经觅食增益(gB)
const neuroEvade := 0.6      # 神经避敌(被捕食减免)
const neuroSelCost := 0.08   # 神经成本
const neuroAdaptK := 0.04    # 神经适应速率
const endoSelCost := 0.12    # 温血成本
const endoAdaptK := 0.04     # 温血适应速率
const symbBenefit := 0.6     # 共生增益(gB)
const symbCost := 0.18       # 共生成本
const symbAdaptK := 0.04     # 共生适应速率
const membBoost := 0.35      # 膜浓缩增殖增益(gB)
const membAdaptK := 0.1      # 膜适应速率
const cmc := 0.5             # 脂质临界胶束浓度(过CMC自组装膜泡)
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
# 逐格岩性(G1):6 种岩各自释放谱 + 风化速率。索引 0花岗岩 1石灰岩 2玄武岩 3砂岩 4蒸发岩 5黏土
const LITH_NAMES := ["花岗岩","石灰岩","玄武岩","砂岩","蒸发岩","黏土"]
const LITH_RATE := [0.4, 1.0, 0.8, 0.5, 1.5, 0.7]
const LITH_VEC := [
	[0.02,0.05,0.02,0.15,0.02,0.01,0.02,0.05,0.40,0.005,0.0,0.02,0.20,0.01,0.005,0.02,0.01,0.0,0.0,0.02,0.0,0.0,0.15,0.15,0.20,0.40,0.05,0.05,0.0,0.0,0.02,0.0,0.0],
	[0.03,0.80,0.15,0.02,0.01,0.02,0.10,0.90,0.05,0.005,0.0,0.02,0.0,0.25,0.10,0.0,0.05,0.02,0.02,0.20,0.05,0.0,0.02,0.05,0.02,0.05,0.10,0.0,0.0,0.0,0.05,0.0,0.02],
	[0.05,0.30,0.40,0.05,0.35,0.02,0.08,0.15,0.20,0.30,0.0,0.15,0.01,0.02,0.01,0.005,0.30,0.0,0.0,0.15,0.08,0.0,0.03,0.01,0.02,0.20,0.20,0.30,0.25,0.30,0.0,0.20,0.02],
	[0.05,0.05,0.03,0.03,0.03,0.03,0.03,0.04,0.50,0.01,0.0,0.02,0.0,0.0,0.0,0.005,0.02,0.15,0.02,0.02,0.0,0.0,0.01,0.10,0.02,0.05,0.02,0.10,0.0,0.0,0.05,0.0,0.10],
	[1.50,0.50,0.20,0.10,0.00,1.40,0.80,0.10,0.02,0.0,0.0,0.05,0.0,0.0,0.0,0.0,0.40,0.0,0.30,0.0,0.0,0.40,0.02,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.10,0.0,0.20],
	[0.10,0.20,0.20,0.15,0.10,0.08,0.10,0.20,0.15,0.05,0.0,0.20,0.0,0.03,0.01,0.0,0.05,0.30,0.15,0.10,0.01,0.02,0.02,0.05,0.10,0.40,0.15,0.10,0.10,0.10,0.05,0.10,0.05],
]
var Lith := PackedByteArray()    # 每格岩性索引
var Lithified := PackedByteArray()  # G5:该格是否已固结成沉积岩
# R1 海底热液喷口:化能合成生命摇篮 + 硫化物矿
var Vent := PackedFloat64Array()    # 每格喷口强度(0=非喷口)
const HYDRO_E := [9, 13, 11, 14, 15, 12, 30, 20]  # 热液硫化物:铜铅锌银金锡钼汞
const VENT_SULF := 0.06             # 喷口硫化物沉积率(幔金属→烟囱)
const LITH_THR_G := 80.0         # 沉积固结阈值(够高→砂矿先在下游富集,再固结)
const PLACER_G := [15, 12, 27]   # 砂矿:金/锡/钛(固体随河搬运富集下游)
# G2 逐格土壤水/地下水
const SOIL_CAP := 2.0
var Soil := PackedFloat64Array()     # 土壤含水
var GW := PackedFloat64Array()       # 地下水
var Runoff := PackedFloat64Array()   # 累积径流(供 G3 河网路由)
# G3 河网(D8 流向)
var Elev := PackedFloat64Array()     # 每格高程(取自 geo)
var Down := PackedInt32Array()       # 每格下游格索引(-1=汇/洋)
var _drainOrder := PackedInt32Array() # 按高程从高到低的处理顺序
const RIVER_GK := 0.5                 # 径流→溶解元素下游搬运系数
# G4 逐格雪/冰川(真冰量喂海平面,替代 climCool 代理)
var Snow := PackedFloat64Array()
var Glacier := PackedFloat64Array()
const SNOW_LINE := 0.0                # 雪线有效温(Teff≤此值积雪)
const SNOW_MAX := 80.0                # 单格雪上限
const GLAC_FLOW := 0.05               # 冰川流动/崩解损耗率(回海,使冰量有界)
const ICE_SEA_K := 0.00003            # 真冰量→海平面偏移(标定到 ~百米级海退)
const WK := 0.0006        # 风化基率
# R4 行星配置:金属丰度(星系化学演化代;地球=1,贫金属第一代→0)。重元素丰度∝金属丰度
var metallicity := 1.0
const HEAVY_E := [9, 12, 13, 14, 15, 20, 23, 24]   # 超新星产重元素:铜锡铅银金汞铀钍(贫金属星无矿无核燃料)

# R5 行星磁层(从 world.html magField/magShield):地磁发电机 B ∝ 核活动(放射成因热)×自转。
# 与火山同根(放射性燃料 U/Th/K ∝ 金属丰度^1.3,超新星产物)。耦合:大气屏蔽率→地表辐射、极光。
const MAG_BSURF := 50.0       # 参考地表场 μT(地球态)
const MAG_BCRIT := 20.0       # 屏蔽住太阳风/锁住辐射所需场 μT
var planet_radio := 1.0       # 放射性燃料基准(U/Th/K),地球=1;贫金属第一代→几乎无→冷核
var planet_rot_h := 24.0      # 自转周期(小时),越快磁场越强
var planet_radius_km := 6371.0   # 行星半径 km(小行星散热快→核活动低)
var planet_mass_e := 1.0         # 行星质量(地球=1);定表面重力/逃逸速度→大气保持能力
# 大气逃逸(太阳风剥离,非热逃逸为主):无磁场→太阳风剥大气(火星化);小重力→更易逃逸。
# 接 R5 磁层 + R4 金属丰度:贫金属→无发电机→磁场塌→大气被剥→死星。地球(强场)逃逸=0→守恒不动。
const STRIP_K := 0.04            # 太阳风剥离基率(每地质年,对无屏蔽大气)
var escapedC := 0.0             # 累计逃逸到太空的碳(均值量纲,守恒账)
var escapedN := 0.0             # 累计逃逸到太空的氮

func core_activity() -> float:   # 核对流活动 = 放射成因热/散热(∝1/R):地球≈1稳定;小星/贫铀→偏低
	var radio_fuel: float = planet_radio * pow(metallicity, 1.3)   # 重元素(SN产)对代数更敏感
	return min(1.0, radio_fuel / (6371.0 / planet_radius_km))

func mag_field() -> float:       # 地表磁场强度 μT
	return MAG_BSURF * core_activity() * (24.0 / planet_rot_h)

func mag_shield() -> float:      # 大气/磁层屏蔽率(强场→1=不漏)
	return min(1.0, mag_field() / MAG_BCRIT)

const E_BURY := 5e-4      # 海洋埋藏率(对超本底)
const E_RETURN := 0.03    # 俯冲池→火山返还(每地质年)
# 真铀地球化学:U/Mo/Se 氧化态可溶(随河走)、还原态沉淀成矿(roll-front/黑页岩型)。
# 还原环境=有机质/生命富集处→把溶解的氧化还原敏感金属还原沉淀,造出陆地铀矿异质(无此机制则全溶进海)。
const REDOX_E := [23, 30, 32]   # 氧化还原敏感成矿元素:铀/钼/硒
const REDOX_SCALE := 4.0        # 还原强度归一(生物量+有机汤)
const REDOX_PK := 0.5           # 还原沉淀比例/步(还原陷阱沉淀,U 主要成黑页岩/roll-front)
# 海相碳酸盐沉淀(真 Ksp 逆行溶解度):[Ca]·[CO₃] 过饱和→沉 CaCO₃ 灰岩;暖浅海更易沉(逆行)。
const KSP_CACO3 := 3000.0       # 碳酸钙溶度积阈(标定到 SEAREF Ca110×碳酸盐30≈3300 附近)
const CARB_PPK := 0.02          # 碳酸盐沉淀速率/步(过饱和分数)
var oceanPH := 8.1             # 海洋 pH(碳酸缓冲,CO₂↑→酸化↓;诊断+碳酸盐补偿)
const PH_DISSOLVE := 7.9        # 碳酸盐补偿:海洋 pH 低于此→已沉灰岩回溶(海洋酸化溶壳/CCD)
const CARB_DISSOLVE_K := 0.04   # 酸化回溶速率/步·每 pH 单位
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
	_fGeneE.resize(SZ * GENE_K); _fLatGene.resize(SZ * N_LAT); _fLatGate.resize(SZ * N_LAT); _fLatR.resize(SZ * NLAT2)
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
	Lith = PackedByteArray(); Lith.resize(SZ)
	Lithified = PackedByteArray(); Lithified.resize(SZ)
	Vent = PackedFloat64Array(); Vent.resize(SZ)
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
			if not isl:
				Lith[k] = 2                               # 玄武岩洋壳
				var vh: float = sin(j * 45.3 + i * 91.7) * 1234.5
				vh = vh - floorf(vh)
				if vh < 0.10: Vent[k] = 1.0               # ~10% 洋格=海底热液喷口
			else:
				var hsh: float = sin(j * 12.9898 + i * 78.233) * 43758.5453
				hsh = hsh - floorf(hsh)
				var relief: float = (geo.elev_at(lat, (i + 0.5) * 360.0 / NLon) - geo.SEA) if geo != null else 0.3
				if relief > 0.25: Lith[k] = 0             # 高地花岗岩
				elif hsh < 0.30: Lith[k] = 5              # 黏土
				elif hsh < 0.55: Lith[k] = 3              # 砂岩
				elif hsh < 0.80: Lith[k] = 1              # 石灰岩
				else: Lith[k] = 0                         # 花岗岩

# ---------- 生命层 ----------
func Teff(j: int, i: int) -> float:
	var k := j * NLon + i
	var sa: float = (clampf(Snow[k] / 20.0, 0.0, 1.0) * 4.0) if Snow.size() == SZ else 0.0   # 雪盖反照率致冷
	return T[k] + cGhouse * (globalCO2 - CO2ref) - climCool * pow(abs(_LAT[j]) / 90.0, 1.3) * 2.0 - sa - impactWinter
func updateHab() -> void:
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var tFit := exp(-pow((Teff(j, i) - 25.0) / 16.0, 2.0))
			var water: float = P[k] if Land[k] != 0 else 1.0
			Hab[k] = clampf(tFit * sqrt(max(0.0, water)), 0.0, 1.0)
			if Vent[k] > 0.0: Hab[k] = max(Hab[k], clampf(Vent[k] * 0.7, 0.0, 1.0))   # 化能合成:喷口供能→黑暗深海也宜居
func envSalt(j: int, i: int) -> float:
	var k := j * NLon + i
	return 0.0 if Land[k] != 0 else SAL[k]
func envDry(j: int, i: int) -> float:
	var k := j * NLon + i
	return (1.0 - P[k]) if Land[k] != 0 else 0.0

func soilStep(dt: float) -> void:   # G2 逐格土壤水平衡:降水→蒸发→满溢径流→深渗地下水→基流。供 G3 河网
	var ds := dt / 10.0
	for k in SZ:
		if Land[k] == 0: continue
		var evap: float = clampf(T[k] * 0.02 + 0.1, 0.05, 1.5)
		Soil[k] = Soil[k] + (P[k] * 0.6 - evap) * ds - 0.08 * Soil[k] * ds
		var ro: float = 0.08 * Soil[k] * ds
		if Soil[k] > SOIL_CAP: ro += Soil[k] - SOIL_CAP; Soil[k] = SOIL_CAP
		if Soil[k] < 0.0: Soil[k] = 0.0
		if Soil[k] > 0.7 * SOIL_CAP:
			var deep: float = 0.05 * (Soil[k] - 0.7 * SOIL_CAP) * ds
			Soil[k] -= deep; GW[k] += deep
		var base: float = 0.02 * GW[k] * ds
		GW[k] -= base
		Runoff[k] += ro + base

func _neighbors4(j: int, i: int) -> Array:
	var out := [j * NLon + (i + 1) % NLon, j * NLon + posmod(i - 1, NLon)]
	if j > 0: out.append((j - 1) * NLon + i)
	if j < NLat - 1: out.append((j + 1) * NLon + i)
	return out

func _buildDrainage() -> void:   # G3:按高程算每格下游(最陡下降),建排水网 + 高→低处理顺序
	if geo == null: return
	Elev.resize(SZ); Down.resize(SZ)
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			Elev[jb + i] = geo.elev_at(_LAT[j], (i + 0.5) * 360.0 / NLon)
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			Down[k] = -1
			if Land[k] == 0: continue
			var lowk := -1
			var lowe: float = Elev[k]
			for nb in _neighbors4(j, i):
				if Elev[nb] < lowe: lowe = Elev[nb]; lowk = nb
			Down[k] = lowk
	var order := []
	for k in SZ: order.append(k)
	order.sort_custom(func(a, b): return Elev[a] > Elev[b])
	_drainOrder = PackedInt32Array(order)

func riverStep() -> void:   # G3:按高→低顺序把溶解元素顺流路由到下游(河网/下游富集/三角洲)。守恒
	if Down.size() != SZ: return
	for idx in _drainOrder.size():
		var k: int = _drainOrder[idx]
		var dn: int = Down[k]
		if dn < 0 or Land[k] == 0: continue
		var ro: float = Runoff[k]
		if ro <= 0.0: continue
		var frac: float = clampf(ro * RIVER_GK, 0.0, 0.5)
		var b0 := k * NE
		var b1 := dn * NE
		for e in NE:
			var mv: float = disE[b0 + e] * frac
			disE[b0 + e] -= mv; disE[b1 + e] += mv
		for pe in PLACER_G:                          # G5 砂矿:重稳矿物固体随河搬运→下游富集(守恒)
			var mvp: float = depE[b0 + pe] * frac * 0.4
			depE[b0 + pe] -= mvp; depE[b1 + pe] += mvp
	Runoff.fill(0.0)

func _classifySedG(base: int) -> int:   # 按沉积成分定沉积岩岩性
	var salt: float = disE_dep(base, 0) + disE_dep(base, 5) + disE_dep(base, 6)   # Na+Cl+SO4
	var carb: float = disE_dep(base, 1) + disE_dep(base, 7)                       # Ca+碳酸盐
	var sil: float = disE_dep(base, 8)                                            # SiO2
	if salt > carb and salt > sil: return 4    # 蒸发岩
	if carb > sil: return 1                    # 石灰岩
	return 3                                   # 砂岩
func disE_dep(base: int, e: int) -> float: return depE[base + e]

func lithifyStep() -> void:   # G5 沉积超阈→固结成沉积岩(岩性按成分),dep→rockE 守恒,改未来风化→岩石循环
	for k in SZ:
		if Land[k] == 0: continue
		var base := k * NE
		var tot := 0.0
		for e in NE: tot += depE[base + e]
		if tot > LITH_THR_G:
			Lith[k] = _classifySedG(base)
			Lithified[k] = 1
			for e in NE:
				var lk: float = depE[base + e] * 0.5
				depE[base + e] -= lk; rockE[e] += lk

func ventStep() -> void:   # R1 海底热液喷口:幔金属→硫化物烟囱(Cu/Pb/Zn/Ag/Au…)沉于喷口格,守恒 rockE→depE
	for k in SZ:
		if Vent[k] <= 0.0: continue
		var base := k * NE
		for he in HYDRO_E:
			var dep: float = min(VENT_SULF * Vent[k] * metallicity, rockE[he])   # 热液金属也∝金属丰度
			rockE[he] -= dep; depE[base + he] += dep

func snowStep() -> void:   # G4 逐格雪/冰川年质量平衡:冷格积雪→久雪成冰川,暖格消融。喂真冰量给海平面
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var te: float = Teff(j, i)
			if te <= SNOW_LINE:
				Snow[k] = min(Snow[k] + (SNOW_LINE - te) * 0.3 + P[k] * 1.0, SNOW_MAX)
			else:
				Snow[k] = max(0.0, Snow[k] - (te - SNOW_LINE) * 2.0)
			if Snow[k] > 40.0: Glacier[k] += 0.3                          # 厚雪转冰川
			Glacier[k] = max(0.0, Glacier[k] - GLAC_FLOW * Glacier[k] - max(0.0, te - SNOW_LINE) * 0.5)  # 流动崩解(回海)+暖融→有界

func stepLife(dt: float) -> void:
	updateHab()
	soilStep(dt)
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
			var memb := clampf(rMemb[k], 0.0, 1.0) if Lip[k] > cmc else 0.0
			_latDevelop(k)                                                             # GRN1 迭代发育潜在表型
			var gB := aerB * szSlow * Hab[k] * (1.0 - 0.3 * clampf(rMulti[k], 0.0, 1.0)) * (1.0 - diffRepCost * clampf(rDiff[k], 0.0, 1.0)) * (1.0 - shellGrowCost * clampf(rShell[k], 0.0, 1.0)) * (1.0 + neuroForage * clampf(rNeuro[k], 0.0, 1.0) * clampf(Sym[k], 0.0, 1.0)) * (1.0 + symbBenefit * clampf(rSymb[k], 0.0, 1.0) * clampf(1.0 - availN / 2.0, 0.0, 1.0)) * (1.0 + membBoost * memb)   # ×多细胞/分化/壳代价 ×神经/共生/膜增益
			gB *= _latGrow(k, j)                                                       # B2 潜在维度耦合生长
			gB *= 1.0 + LAB * clampf(rMulti[k], 0.0, 1.0) * _divPotential(k)  # E5fix2: strong continuous gain on GRN division potential
			gB *= 1.0 + MORPH_LIGHT * clampf(_mH[k] / 4.0, 0.0, 1.0)  # E9-3 L-system 形态受光增益: 高->受光->生长(选择塑形)
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
				# A层:从基因 develop 复杂度链6性状(sigmoid(Wg−bias)),再把各性状驱动力反传到基因(零随机,守恒不碰)
				var _gb := k * GENE_K
				var _P := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
				for _m in GENE_K:
					var _s := -DEV_BIAS
					for _g in GENE_K: _s += float(_devW[_m][_g]) * geneE[_gb + _g]
					_P[_m] = 1.0 / (1.0 + exp(-_s))
				rSize[k] = float(_P[0]); rEuk[k] = float(_P[1]); rMulti[k] = float(_P[2]); rShell[k] = float(_P[3]); rNeuro[k] = float(_P[4]); rEndo[k] = float(_P[5])
				var szc := float(_P[0])
				var euG := clampf(float(_P[1]) * 2.0, 0.0, 1.0)
				var muG := clampf(float(_P[2]) * 2.0, 0.0, 1.0)
				var predP := clampf(H[k] / 5.0, 0.0, 1.0)
				var minAvail := clampf(disE[k * NE + 1] / 150.0, 0.0, 1.0)
				var coldStress := clampf((12.0 - teff) / 24.0, 0.0, 1.0)
				var nStress := clampf(1.0 - availN / 2.0, 0.0, 1.0)
				var _d := [
					sizeAdaptK * (predP * 0.5 + o2f * 0.4 - 0.35),
					euAdaptK * (euGain * o2f * clampf(szc * 2.0, 0.0, 1.0) - euCost),
					multiAdaptK * (euG * (0.2 + 0.8 * predP) * multiDef - multiCost),
					shellAdaptK * (muG * predP * minAvail - shellCost),
					neuroAdaptK * (muG * clampf((Sym[k] + predP) / 1.5, 0.0, 1.0) - neuroSelCost),
					endoAdaptK * (muG * coldStress - endoSelCost),
				]
				_d[2] += DIVLAB * _divPotential(k)  # E5fix3: division potential -> rMulti gene gradient
				for _g in GENE_K:
					var _dg := 0.0
					for _m in GENE_K: _dg += float(_d[_m]) * float(_P[_m]) * (1.0 - float(_P[_m])) * float(_devW[_m][_g])
					geneE[_gb + _g] += GENE_ETA * dl * _dg
				rDiff[k] = clampf(rDiff[k] + diffAdaptK * dl * (muG * (0.6 + predP * 0.5) - diffCost), 0.0, 1.0)   # 分化仍直接(未纳入基因)
				for _l in N_LAT:   # B3 潜在基因:值(门控加权)+ 门控(净益>代价才开)双演化→有效维度数涌现
					var _gate := 1.0 / (1.0 + exp(-latGate[k * N_LAT + _l]))
					var _lp := float(_latP[k * N_LAT + _l])
					var _ben := LAT_EFF * (2.0 * _lp - 1.0) * _latsig(_l, j)
					latGene[k * N_LAT + _l] += LAT_ETA * dl * _gate * LAT_EFF * _latsig(_l, j) * _lp * (1.0 - _lp)
					latGate[k * N_LAT + _l] += LAT_ETA * dl * _gate * (1.0 - _gate) * (_ben - EXPR_COST)
				rSymb[k] = clampf(rSymb[k] + symbAdaptK * dl * (nStress * symbBenefit - symbCost), 0.0, 1.0)   # 贫氮→共生固氮伙伴
				var mb := 1.0 if Lip[k] > cmc else -1.0
				rMemb[k] = clampf(rMemb[k] + membAdaptK * dl * mb, 0.0, 1.0)   # 脂质过CMC→膜泡
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
			Seg[k] = clampf(Seg[k] + morphK * (gS * moveBase + DFORM * _divP[k] - Seg[k] - morphCost), 0.0, 1.0)
			Limb[k] = clampf(Limb[k] + morphK * (gG * moveBase + DFORM * _divP[k] - Limb[k] - morphCost), 0.0, 1.0)
			Axis[k] = clampf(Axis[k] + morphK * (gS * sizeP + DFORM * _divP[k] - Axis[k] - morphCost), 0.0, 1.0)
	# 四邻扩散 + 带性状迁移(守恒)
	_flow.fill(0.0); _fTo.fill(0.0); _fSa.fill(0.0); _fDr.fill(0.0)
	_fGeneE.fill(0.0); _fLatGene.fill(0.0); _fLatGate.fill(0.0); _fLatR.fill(0.0)
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
				var _gk := k * GENE_K; var _gbk := int(bk) * GENE_K
				for _ig in GENE_K: _fGeneE[_gbk + _ig] += mv * geneE[_gk + _ig]
				var _lk := k * N_LAT; var _lbk := int(bk) * N_LAT
				for _il in N_LAT:
					_fLatGene[_lbk + _il] += mv * latGene[_lk + _il]
					_fLatGate[_lbk + _il] += mv * latGate[_lk + _il]
				var _rk := k * NLAT2; var _rbk := int(bk) * NLAT2
				for _ir in NLAT2: _fLatR[_rbk + _ir] += mv * latR[_rk + _ir]
	for k in SZ:
		if _flow[k] > 0.0:
			var tot := N[k] + _flow[k]
			if tot > 0.0:
				Topt[k] = (Topt[k] * N[k] + _fTo[k]) / tot
				Salt[k] = (Salt[k] * N[k] + _fSa[k]) / tot
				Dry[k] = (Dry[k] * N[k] + _fDr[k]) / tot
				for _jg in GENE_K: geneE[k * GENE_K + _jg] = (geneE[k * GENE_K + _jg] * N[k] + _fGeneE[k * GENE_K + _jg]) / tot
				var _protR: float = (1.0 - LATR_PROTECT * clampf(_divPotential(k), 0.0, 1.0)) if rMulti[k] >= 0.05 else 1.0  # E5fix5
				for _jl in N_LAT:
					latGene[k * N_LAT + _jl] = (latGene[k * N_LAT + _jl] * N[k] + _fLatGene[k * N_LAT + _jl]) / tot
					latGate[k * N_LAT + _jl] = (latGate[k * N_LAT + _jl] * N[k] + _fLatGate[k * N_LAT + _jl]) / tot
				for _jr in NLAT2: latR[k * NLAT2 + _jr] = (latR[k * NLAT2 + _jr] * N[k] + _fLatR[k * NLAT2 + _jr] * _protR) / (N[k] + _flow[k] * _protR)
		N[k] = max(0.0, N[k] + _flow[k])

	# ---------- 食物网:N(生产者)→ H(食草)→ C(食肉),Holling-II ----------
	var ds := dt / 10.0
	for k in SZ:
		var nv := N[k]
		if H[k] < SEED and nv > FW_SEEDN: H[k] = SEED
		if H[k] > 0.0:
			# 防御:体型/多细胞/壳/神经→减免被捕食。设地板(捕食者反适应/军备竞赛:防御抬高摄食难度但不归零)
			var szD: float = maxf(0.7, (1.0 - 0.6 * clampf(rSize[k], 0.0, 1.0)) * (1.0 - 0.9 * clampf(rMulti[k], 0.0, 1.0)) * (1.0 - shellDef * clampf(rShell[k], 0.0, 1.0)) * (1.0 - neuroEvade * clampf(rNeuro[k], 0.0, 1.0)))
			var graze: float = min(FW_GRAZE * H[k] * (nv / (nv + FW_HALF)) * szD * ds, nv * 0.5)
			N[k] = nv - graze
			H[k] = max(0.0, H[k] + FW_YIELD * graze - FW_MH * H[k] * ds)
		var hv := H[k]
		if C[k] < SEED and hv > FW_SEEDH: C[k] = SEED
		if C[k] > 0.0:
			# E3 social: herd defense - dense herbivore lowers per-capita predation (safety in numbers)
			var herdDef: float = 1.0 - FW_HERD * clampf(hv / (hv + FW_HERD_HALF), 0.0, 1.0)
			var senseOrg: float = clampf(rNeuro[k], 0.0, 1.0) * clampf(_divP[k] / 0.5, 0.0, 1.0)
			var senseEvade: float = 1.0 - SENS_EVADE * senseOrg
			var graze2: float = min(FW_GRAZE * C[k] * (hv / (hv + FW_HALF_C)) * ds * herdDef * senseEvade, hv * 0.5)
			H[k] = hv - graze2
			C[k] = max(0.0, C[k] + FW_YIELD * graze2 - FW_MC * C[k] * ds)
	# E3 觅食: 定向流动—食草趋生产者(N)、食肉趋食草(H)的高密度邻格(守恒,叠加在被动扩散上)
	_advect(H, N, FW_FORAGE * ds)
	_advect(C, H, FW_FORAGE * ds)
	# E3 flee: herbivore toward low-predator cells (pref=-C)
	var _negC := PackedFloat64Array()
	_negC.resize(SZ)
	for _k in SZ: _negC[_k] = -C[_k]
	_advect(H, _negC, FW_FLEE * ds)
	# E3 migrate: H/C toward high-habitability cells
	_advect(H, Hab, FW_MIGR * ds)
	_advect(C, Hab, FW_MIGR * ds)
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
func _advect(F: PackedFloat64Array, pref: PackedFloat64Array, rate: float) -> void:
	# E3 定向流动(守恒): F 沿 pref 上坡向邻格搬运,按正梯度归一化分配,确定性,复用 _flow
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
			var gsum := 0.0
			for bk in nb:
				var g: float = pref[bk] - pref[k]
				if g > 0.0: gsum += g
			if gsum <= 0.0: continue
			var movable: float = rate * v
			for bk in nb:
				var g2: float = pref[bk] - pref[k]
				if g2 > 0.0:
					var mv: float = movable * (g2 / gsum)
					_flow[k] -= mv; _flow[bk] += mv
	for k in SZ: F[k] = max(0.0, F[k] + _flow[k])

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
		# 真硅酸盐风化:速率 ∝ [碳酸/CO₂] × Arrhenius(地表温)。恒温器=高CO₂→温室增温→指数加速风化→抽CO₂(Walker反馈,真温度动力学)
		var tempf: float = clampf(ChemS.arrhenius(Teff(k / NLon, k % NLon), ChemS.EA_SILICATE, 15.0), 0.2, 4.0)
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
	# 海洋 pH:碳酸缓冲(pCO₂=大气CO₂,碱度=海洋平均 Ca+碳酸盐)。高CO₂→酸化→下面碳酸盐补偿回溶
	var alk := 0.0; var nOcn := 0
	for k in SZ:
		if Land[k] == 0: alk += disE[k * NE + 1] + disE[k * NE + 7]; nOcn += 1
	oceanPH = ChemS.ocean_ph(globalCO2, alk / float(maxi(1, nOcn)))
	for j in NLat:
		var jb := j * NLon
		for i in NLon:
			var k := jb + i
			var base := k * NE
			var water: float = (P[k] if Land[k] != 0 else 1.0)
			if Land[k] != 0:
				# 注:33 元素矿物供给速率仍用标定线性温度因子(成矿异质度依赖此标定);
				# 真 Arrhenius 已用于碳硅酸盐恒温器(carbonStep,定义气候的真实物化)。此处改 Arrhenius 需重标成矿,留待后续。
				var act: float = float(LITH_RATE[Lith[k]]) * clampf(water, 0.0, 1.0) * clampf((T[k] + 5.0) / 25.0, 0.0, 1.5) * cf
				for e in NE:
					var rel: float = min(WK * float(LITH_VEC[Lith[k]][e]) * act * (metallicity if e in HEAVY_E else 1.0), rockE[e])
					rockE[e] -= rel; disE[base + e] += rel
			var wcap: float = max(0.05, water)
			for e in NE:
				var cap: float = float(ESOL[e]) * wcap
				var d: float = disE[base + e]
				if d > cap and Land[k] != 0:   # 溶解度沉淀只在陆地/蒸发,海洋靠埋藏稳在 SEAREF
					var pp: float = (d - cap) * 0.2
					disE[base + e] = d - pp; depE[base + e] += pp
			# 氧化还原成矿:还原性格(有机/生命富集)把溶解的 U/Mo/Se 还原沉淀成矿(roll-front/黑页岩,真铀地化)
			var reduLoc: float = clampf((float(N[k]) + Org[k] + Prot[k] + Lip[k]) / REDOX_SCALE, 0.0, 1.0)
			if reduLoc > 0.0:
				for re in REDOX_E:
					var dr: float = disE[base + re]
					if dr > 0.0:
						var ppr: float = dr * REDOX_PK * reduLoc
						disE[base + re] = dr - ppr; depE[base + re] += ppr
			if Land[k] == 0:
				# 海相碳酸盐沉淀:真 Ksp 逆行溶解度,暖浅海过饱和→沉 CaCO₃ 灰岩(Ca+碳酸盐→沉积,守恒)
				var ksp: float = KSP_CACO3 * ChemS.ksp_caco3_factor(Teff(j, i))
				var iap: float = disE[base + 1] * disE[base + 7]   # [Ca]·[CO₃]
				if iap > ksp:
					var pc: float = min(disE[base + 1], disE[base + 7]) * CARB_PPK * (1.0 - ksp / iap) * clampf((oceanPH - 7.4) / 0.5, 0.0, 1.0)
					if pc > 0.0:
						disE[base + 1] -= pc; disE[base + 7] -= pc
						depE[base + 1] += pc; depE[base + 7] += pc   # 灰岩 = Ca + 碳酸盐 各1(配平)
				elif oceanPH < PH_DISSOLVE:
					# 碳酸盐补偿(海洋酸化/CCD):pH 低→已沉灰岩回溶,放回 Ca+碳酸盐(缓冲 pH,守恒)
					var dc: float = min(depE[base + 1], depE[base + 7]) * CARB_DISSOLVE_K * (PH_DISSOLVE - oceanPH)
					if dc > 0.0:
						depE[base + 1] -= dc; depE[base + 7] -= dc
						disE[base + 1] += dc; disE[base + 7] += dc
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
	var ice := 0.0
	for k in SZ: ice += Snow[k] + Glacier[k]    # G4:真实雪+冰川总量(替代 climCool 代理)
	iceVol = ice
	if refIce < 0.0 and geoT >= 6: refIce = iceVol     # 等极冰盖基线形成再定基准(永久冰盖不算海退)
	var rf: float = refIce if refIce >= 0.0 else iceVol
	seaOffset = clampf(-ICE_SEA_K * (iceVol - rf), -0.075, 0.075)   # 物理上限 ±150m
	if geo != null:
		var m = geo.coarse_land_at(NLat, NLon, effSea())
		for j in NLat:
			var jb := j * NLon
			for i in NLon: Land[jb + i] = 1 if m[j][i] else 0

func stepGeo() -> void:
	geoT += 1
	geneMutate()                                                                  # B层 种子化突变(年度)
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
	snowStep()
	_seaStep()
	carbonStep()
	atmosphereEscape()
	elementStep()
	ventStep()
	riverStep()
	lithifyStep()
	massExtinctionCheck(updateSpecies())
	_track_events()

# 大气逃逸(逐地质年):太阳风剥离 = 基率 ×(1−磁屏蔽)÷ 表面重力。守恒到 escapedC/N(逃逸到太空)。
# 地球(mag_shield=1)→剥离0→守恒不动;贫金属/无发电机→屏蔽塌→大气被剥→CO₂/N₂ 流失→死星。
func _gnoise(a: int, b: int, c: int) -> float:   # 确定性哈希噪声→[-1,1](种子 PRNG,可复现)
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (mutSeed * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0xFFFFFF) * 2.0 - 1.0

func geneMutate() -> void:   # B层:逐地质年给有生命格的基因加种子化随机扰动(探索,逃局部最优;不碰物质守恒)
	if MUT_K <= 0.0: return
	for k in SZ:
		if N[k] <= SEED: continue
		var gb := k * GENE_K
		for g in GENE_K:
			geneE[gb + g] += MUT_K * _gnoise(k, g, geoT)
		for l in N_LAT: latGene[k * N_LAT + l] += MUT_K * _gnoise(k, 100 + l, geoT)   # B2 潜在基因值突变
		for l in N_LAT: latGate[k * N_LAT + l] += MUT_K * _gnoise(k, 200 + l, geoT)   # B3 门控基因突变
		if rMulti[k] >= 0.05:  # E5fix4: multicell latR hill-climb mutation (keep only mutations that raise division potential d)
			var _dbef := _divPotential(k)
			var _bak := []
			for _mm in NLAT2: _bak.append(latR[k * NLAT2 + _mm])
			for m in NLAT2: latR[k * NLAT2 + m] += MUT_K * 0.5 * _gnoise(k, 300 + m, geoT)
			if _divPotential(k) < _dbef:
				for _mm in NLAT2: latR[k * NLAT2 + _mm] = _bak[_mm]
		else:
			for m in NLAT2: latR[k * NLAT2 + m] += MUT_K * 0.5 * _gnoise(k, 300 + m, geoT)

func _latsig(l: int, j: int) -> float:   # 每潜在维度绑不同纬度带环境信号(确定性)→含义从环境涌现
	return sin(float(l) * 1.7 + 2.2) * cos(_LAT[j] * PI / 180.0 * (1.0 + float(l) * 0.6))

func _latDevelop(k: int) -> void:   # GRN1:潜在表型=调控矩阵 latR 迭代发育到稳态(latR=0→退化成 sigmoid(latGene))
	if N[k] <= 1e-3: return   # 死格 latent 不参与,省算
	var lb := k * N_LAT
	var rb := k * NLAT2
	var a := []
	for l in N_LAT: a.append(1.0 / (1.0 + exp(-latGene[lb + l])))
	for _it in GRN_T:
		var na := []
		for l in N_LAT:
			var sgrn: float = latGene[lb + l]
			for m in N_LAT: sgrn += latR[rb + l * N_LAT + m] * float(a[m])
			na.append(1.0 / (1.0 + exp(-sgrn)))
		a = na
	for l in N_LAT: _latP[lb + l] = float(a[l])

func _divPotential(k: int) -> float:
	# E5fix2: division potential = |anti-init steady state - normal steady state(_latP)|; continuous from 0
	if rMulti[k] < 0.05: return 0.0
	var lb := k * N_LAT
	var rb := k * NLAT2
	var a := []
	for l in N_LAT: a.append(1.0 - 1.0 / (1.0 + exp(-latGene[lb + l])))
	for _it in GRN_T:
		var na := []
		for l in N_LAT:
			var s: float = latGene[lb + l]
			for m in N_LAT: s += latR[rb + l * N_LAT + m] * float(a[m])
			na.append(1.0 / (1.0 + exp(-s)))
		a = na
	var d := 0.0
	for l in N_LAT: d += absf(float(a[l]) - _latP[lb + l])
	return d

func _latGrow(k: int, j: int) -> float:   # 潜在性状弱耦合生长:表达匹配环境→增益、否则代价(功能涌现的选择压)
	var f := 1.0
	var lb := k * N_LAT
	for l in N_LAT:
		var gate := 1.0 / (1.0 + exp(-latGate[lb + l]))
		var lp := float(_latP[lb + l])
		f += gate * (LAT_EFF * (2.0 * lp - 1.0) * _latsig(l, j) - EXPR_COST)   # B3 仅门控开的维接生长且付代价
	return clampf(f, 0.5, 1.5)

func atmosphereEscape() -> void:
	var shield: float = mag_shield()
	if shield >= 1.0: return                                  # 强磁场全屏蔽,无剥离(地球态)
	var grav: float = planet_mass_e / pow(planet_radius_km / 6371.0, 2.0)   # 表面重力(地球=1);小重力→易逃逸
	var strip: float = clampf(STRIP_K * (1.0 - shield) / maxf(0.2, grav), 0.0, 0.5)
	if strip <= 0.0: return
	var lostC := 0.0
	for k in SZ:
		var l: float = Co2[k] * strip; Co2[k] -= l; lostC += l
	escapedC += lostC / float(SZ)                             # 均值量纲(与 globalCO2 一致)→守恒账
	globalCO2 = maxf(0.0, globalCO2 - lostC / float(SZ))
	var lostN: float = atmN2 * strip; atmN2 -= lostN; escapedN += lostN
	globalO2 = maxf(0.0, globalO2 * (1.0 - strip))            # O₂ 也被剥(不入碳氮守恒账)

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
	# E4: 体制按演化复杂度分阶段(原核-真核-多细胞-寒武壳-神经-脊索-温血),从性状跨阈确定性涌现
	var k := j * NLon + i
	var mu: float = rMulti[k]
	var eu: float = rEuk[k]
	var sh: float = rShell[k]
	var nu: float = rNeuro[k]
	var en: float = rEndo[k]
	var ax: float = Axis[k]
	var sym: float = Sym[k]
	var seg: float = Seg[k]
	var limb: float = Limb[k]
	if mu < 0.3:
		if eu < 0.3: return "原核菌"
		return "真核单胞"
	if en > 0.5: return "温血脊椎"
	if ax > 0.5: return "脊索动物"
	if nu > 0.5 and seg > 0.5 and limb > 0.4: return "节肢·神经"
	if sh > 0.5: return "矿化壳·寒武"
	if nu > 0.5: return "神经软体"
	if seg > 0.5: return "环节软体"
	if sym < 0.4: return "辐射软体"
	return "软体多胞"
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
	geneE = PackedFloat64Array(); geneE.resize(SZ * GENE_K)   # 基因初值0→develop出性状≈0
	latGene = PackedFloat64Array(); latGene.resize(SZ * N_LAT)   # B2 潜在基因值(中性起点)
	latGate = PackedFloat64Array(); latGate.resize(SZ * N_LAT)   # B3 门控(0→半开,演化定开几维)
	latR = PackedFloat64Array(); latR.resize(SZ * NLAT2)   # GRN1 调控矩阵(0 起点→退化成 B2/B3)
	_latP = PackedFloat64Array(); _latP.resize(SZ * N_LAT)
	_devW = []
	for _m in GENE_K:
		var _row := []
		for _kk in GENE_K: _row.append(1.4 if _m == _kk else 0.35 * sin(float(_m) * 1.7 + float(_kk) * 2.3))
		_devW.append(_row)
	phylo = []; nextSp = 1; extEMA = 1.0; massExt = []
	events = []; _seen_life = false; _in_ice = false; _in_warm = false
	MOC = 1.0; geoT = 0; climCool = 0.0; globalCO2 = 2.0; impactWinter = 0.0
	escapedC = 0.0; escapedN = 0.0
	iceVol = 0.0; refIce = -1.0; seaOffset = 0.0
	Co2 = gridF(CO2ref); ocnC = 2.0; fosC = 0.0; rockC = 10000.0; globalO2 = 0.0; globalRed = 4.0; atmN2 = 1000.0; availN = 2.0; organicC = 0.0; bioC = 0.0; o2Prod = 0.0
	disE = PackedFloat64Array(); disE.resize(SZ * NE)
	depE = PackedFloat64Array(); depE.resize(SZ * NE)
	subPoolE = PackedFloat64Array(); subPoolE.resize(NE)
	rockE = PackedFloat64Array(); rockE.resize(NE); rockE.fill(100000.0)
	Soil = gridF(SOIL_CAP * 0.5); GW = gridF(2.0); Runoff = gridF(0.0)
	Snow = gridF(0.0); Glacier = gridF(0.0)
	_buildDrainage()
	for k in SZ:
		if Land[k] == 0:
			for e in NE: disE[k * NE + e] = float(SEAREF[e])
	for d in 3 * YEAR: stepDay(d % YEAR)
