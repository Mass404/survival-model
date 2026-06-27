# 交接状态 · 2026-06-26

接手前先读这份。项目是**一个生存游戏**:人在一颗"活的、确定性演化星球"的某地求生;演化星球是底层。
工程主体在 `godot/`(Godot 4.6.1 mono)。设计理念见 `GAME_NOTES.md`、`design_overview.md`。

---

## 〇、四条铁律(绝不能破 — 从已删的 HANDOFF_TO_CODE 誊入,源头见 design_overview.md)

1. **属性=存量,动作=流量**。
2. **单一突变入口**。
3. **零随机** — 所有事件由元素跨阈确定性涌现(张弛/relaxation-oscillation);演化用 adaptive dynamics(性状沿适应度梯度爬)+ 阈值解锁创新,**不掷骰子**。允许多谱系竞争的"内生混沌"当对称破缺,但**禁止外生 PRNG**。
4. **守恒 + 涌现**(没有一条结果是写死的)。守恒账本(碳/氮/33元素)逐项总量一克不差是硬指标。

---

## 一、怎么跑 / 怎么验证(铁律:先 headless 数值验证,再落地)

- Godot 可执行:`D:\Program Files\Godot\Godot_v4.6.1-stable_mono_win64_console.exe`(带 `_console` 的有 stdout,headless 用它)。
- 开窗口跑游戏:`Godot..._win64.exe --path godot`(非 console)。
- Headless 跑某验证器:`Godot..._console.exe --headless --path godot --script res://<X>.gd`
- 单文件语法检查:`... --check-only --script res://<X>.gd`
- **慢**:含深时间(stepGeo/stepLife)的验证器一次几十秒~几分钟;`testsuite.gd` ~3-4 分钟。建议后台跑。

**验证器清单**(`godot/*.gd`,都是确定性、零随机):
- 综合:`testsuite.gd`(四铁律:逐年守恒+确定性+涌现+健全,**35 断言,当前 35/35 全过**)、`validate.gd`(生命健全性)
- 守恒/化学:`conscheck`(碳氮守恒+GOE)、`elemcheck`(33元素守恒+成矿异质+redox铀)、`chemcheck`(配平反应)、`chembridgecheck`(物种↔元素桥)
- 真物化:`weathercheck`(Arrhenius风化)、`carbonatecheck`(碳酸盐Ksp)、`phcheck`(海洋pH)
- 行星:`worldcheck`(金属丰度)、`magcheck`(磁层/辐射/极光)、`escapecheck`(大气逃逸)、`platecheck`(板块构造)、`geocheck`/`tectcheck`(地形)、`slcheck`(海平面)
- 局部生存层:`localcheck`/`survivecheck`/`bodycheck`/`anycellcheck`(任意格空降)/`cellmovecheck`(网格移动)/`spawncheck`(开局)/`ventcheck`/`ringcheck`/`eclcheck`/`climcheck`/`fwcheck`(食物网)/`rqcheck`(红皇后)/`prebiocheck`/`gcheck`
- **纪律:绝不为了让验证器变绿而放松判据。判据红 = 真缺陷,修代码不是改判据(除非判据本身被证明测错了东西——那要在 commit 里讲清理由)。**

---

## 二、架构(两层统一)

- **全球行星层 `godot/sim/World.gd`**(18×24 粗网格,深时间逐日/逐年):气候/洋流、生命演化(~18性状+食物网)、史前化学、33元素逐格化学、碳氮氧守恒账、磁层/辐射、大气逃逸。`Geo.gd`=地形生成(256×128)+板块构造。
- **局部生存层 `godot/sim/Local.gd`**(逐分钟):是全球格的"放大镜"——能在**地球任意(纬,经)格空降求生**(`enter_cell`),读该格岩性/高程/化学矿/气候即时生成 locale;网格邻接移动(大圆距离)。人体生理 `Body.gd`。**单一真相=全局格**。
- **真物理化学引擎 `godot/sim/Chem.gd`**:元素原子量、化合物物性(熔点/密度)、**配平化学反应**(ΔH+点燃温)、Arrhenius、碳酸钙Ksp、海洋pH 公式。全局化学按原子记账接它。
- UI/渲染:`Main.gd`(全球)、`LocalMain.gd`(局部生存)、`CanvasView.gd`、`PhyloView.gd`。

---

## 三、本会话(2026-06-25~26)做了什么(都已验证+提交;E1+E2 未 push,其余已 push)

- **R1–R5**:补 world.html 遗漏——海底热液喷口、行星环、日月食、金属丰度多世界、磁层-辐射-极光-氡-风寒。
- **U1–U4 两层统一**:局部生存层从 5 个写死地点改成可在全球任意格空降+网格移动+开局空降宜居格(单一真相=全局格)。
- **真物理化学(用户重点)**:P1 Chem 引擎(配平反应/物性/反应热)→ M1 物种↔33元素桥 → M2 硅酸盐风化真 Arrhenius(碳硅酸盐恒温器"源") → M4 碳酸盐真 Ksp 逆行溶解度("汇") → N2 海洋 pH+酸化+碳酸盐补偿 → redox 控制铀成矿(真铀地化)。
- **底层世界三块**:N1 大气逃逸(R4金属丰度+R5磁层→无磁场→死星闭环)、N3 板块构造(地质活动集中在板块边界:汇聚造山/离散裂谷)。
- **E1+E2 生物进化解卡(`e4c78bd`,testsuite 32→35/35)**:复杂度性状链以前卡死(永远蠕虫)——修通后 rEuk/rSize/rMulti 从0涨到1.0(体型增大跟O₂挂钩=寒武爆发);食物网三级立住(食草峰21→264、食肉峰0→8.8,靠捕食者反防御裕度=军备竞赛)。

---

## 四、已知缺口 / 下一步(按价值排)

**生物进化 ✅ 本会话(2026-06-27)三条全部完成、testsuite 全程 35/35:**
- **E4 地质年代可辨生物**(`01ee5b2`):bodyPlan 接复杂度性状(rMulti/rEuk/rShell/rNeuro/rEndo)跨阈确定性涌现—原核菌→真核单胞→软体多胞→辐射/环节软体→矿化壳·寒武→神经软体/节肢·神经→脊索动物→温血脊椎;validate 主导体制从"蠕虫"演化到"温血脊椎"。(踩坑:注入伪造了行号 1322↔真1120、缩进 1-tab↔真0-tab,后者让 GDScript 把 func 当 lambda;靠同文件 getAdapt 真实缩进对齐修好。)
- **E3 行为逻辑**(`68dc2e1`):新增守恒定向流动 `_advect(F, pref, rate)`(生物量沿"吸引势"上坡向邻格搬运,正梯度归一化、_flow 配对加减→守恒,确定性),叠加在被动 `_diffuse` 上。觅食(食肉峰8.8→15.7)/避敌(势=-C)/迁徙(趋Hab,食草259→272)/社群(集群防御 herdDef,272→276)。
- **食物网稳定性**(`0ad95ea`):**原以为是交接说的"非线性硬骨头",实为 `szD` 失衡 tradeoff**。fwdiag/fwcheck 诊断定位:防御性状(rSize/rMulti)演化满后 szD 触地板 0.45,把"食草吃生产者"的摄食腰斩(净率 +0.085→+0.016)→食草维持不住高密度斑块(maxH 钳在0.3、够不到食肉门槛~1.3)→食肉饿死(80年仅持续16年)。调地板 **0.45→0.7**,食肉持续 **16→67年**、大灭绝 4→3次。**⚠️遗留隐患:szD 防御只有代价(降食草摄食)、无收益(食肉吃食草那项无对应减免),本次调地板治标;未来可重构成"代价(降摄食)+收益(减被捕食)"的平衡军备竞赛。** 诊断器 `fwdiag.gd`(逐年追踪单格 maxH/maxC)已入库。

**真物理化学(可继续加深,边际收益递减,非硬缺口):**
- 玩家侧生存化学(取火/冶炼/烧陶/烹饪)——**用户明确押后了**,等世界基础够了再做。Chem 的11个配平反应+点燃温已为它备好。
- 材料物性(熔点/密度/硬度)接进玩法;其余元素沉淀也换真 Ksp(现只碳酸盐)。

**底层世界:**
- **N4 真大陆漂移(advection)**:N3 只做了边界地质,真正的板块平移(带着逐格化学/生命迁移)耦合极大,没做。且 `World.Elev` 逐格高程在 spinUp 后静态(只 land mask 经 `_seaStep` 逐年重算),要让漂移完全传导需重算 World.Elev。
- 游戏 `LocalMain` 开局只跑 `for d in 180: stepDay`(无 stepLife/stepGeo)→ 矿/生物量未发育、`find_spawn` 走退路;要"在演化好的星球上求生"需开局补跑深时间。

---

## 五、关键坑(GDScript / 模拟)

- `class_name` 在裸 `--script` 下不解析 → 跨文件用 `preload("res://...")`。
- `abs/max/min/clamp` 返回 **Variant**,`:=` 推断报错 → 显式 `: float`/`floatf` 或用 `=`;const 嵌套 Dictionary 取值是 Variant,算术要 `float()` 包。
- `%` 格式化**不支持 `%e`**(用 `str()`)。
- Edit 工具匹配 World.gd 含**制表符**的多行老对不上 → 用 Python 脚本按唯一标记行插入(注意缩进的真实 tab 数,行号后那个 tab 别数进去)。
- **守恒是铁律**:任何新机制移动量都要守恒。新增的"汇/源"(如大气逃逸)要建账本池(`escapedC/escapedN`)并接进 conscheck,否则碳氮守恒会"假漂移"。
- 复杂度性状(防御)与食物网**强耦合**:解锁防御必然冲击食物网,要同步给捕食者反适应裕度。
- 真实流程:行星先深时间演化(stepGeo成矿+stepLife出生命)→ 玩家再空降;只跑 stepDay 矿和生物量长不出来。

---

## 六、记忆(Claude Code 持久记忆,同机另一 Claude Code 会话可见)

`~/.claude/projects/D--Project-survival-model/memory/` —— 关键几条:
`godot-port.md`(怎么跑/坑/testsuite 35/35 修复详情)、`real-chemistry-engine.md`(真物化全进度)、`full-port-layered-architecture.md`(两层统一)、`game-preproduction.md`(游戏定位)、`MEMORY.md`(索引)。
