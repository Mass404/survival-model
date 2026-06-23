# 交接:把 world.html 功能搬进 Godot 全球系统

接手的 agent 看这份就够。先读这份,再读 `GAME_NOTES.md`(游戏定位)、`memory/godot-port.md`(踩坑)。

---

## 0. 一句话现状

`godot/` 里有一套**全球演化行星**(evolve 内核移植 + v9 像素星球皮)。任务是**把 `world.html` 的功能逐项搬进来**。已搬 5 项行星机制(见下),还剩 4 项。world.html 原文参考:根目录 `_world_ref.html`(未追踪),或 `git show d515596~1:world.html`。

## 1. 架构现实(决定怎么搬)

- **Godot 现系统 = 全球模型**:18×24 粗气候网格(逐天 `stepDay`)+ 256×128 显示;生命/物种/谱系/守恒账本都在这。核心文件 `godot/sim/World.gd`(纯逻辑 RefCounted)、`godot/sim/Geo.gd`(v9 高程+构造)、`godot/CanvasView.gd`(渲染)、`godot/Main.gd`(UI+时钟)。
- **world.html = 局部模型**:少数命名地点(逐分钟)+ 玩家旅行。它的机制分三类:
  1. **逐格可映射全球网格的**(化学/食物网/史前化学/局部地质)→ 按网格每格套用。**这是主要搬运工作。**
  2. **全球/纬度级的**(天文/潮汐/海平面)→ 本就是纬度+时间函数,直接接。
  3. **只属局部生存层的**(命名地点、路线、玩家、travelTo)→ 这是**生存游戏本体**,另起一层(任务 #9),**不是**给全球行星加机制。
- **不是 1:1 平移**:在 Godot 模型的抽象层重实现每个机制(扁平网格、逐天/逐地质年),不照抄 JS。world.html 生命层有 ~30 性状+能量预算;Godot 是简化版(N 生物量 + Topt/Salt/Dry 适应 + 形态门类)。搬功能=在简化抽象上加对应机制,数值验证关键涌现即可,别强求复刻全部性状。

## 2. 铁律(绝不能破,来自 design_overview/HANDOFF_TO_CODE)

1. 属性=存量,动作=流量。2. 单一突变入口。3. **零随机**——一切由跨阈确定性涌现 + adaptive dynamics,**不掷骰子**(禁外生 PRNG)。4. **守恒 + 涌现**(结果不写死)。
→ 守恒账本(碳4库/O₂/氮/33元素)逐库搬运、**逐项总量一克不差**是硬指标。

## 3. 工作流(每项照此,已验证有效)

中文讲机制 → **写 headless 验证器 `XXcheck.gd`(extends SceneTree)** 验关键涌现/守恒 → 落进 `World.gd`/`Geo.gd` → 跑验证器调参直到过 → 接显示(CanvasView/Main 探查面板)→ 提交。**先验证再落地,参数靠验证调,别信先验值。**

跑:
- 语法检查:`Godot..._console.exe --headless --path godot --check-only --script res://X.gd`
- 验证器:`Godot..._console.exe --headless --path godot --script res://XXcheck.gd`(Godot **4.6.1 mono** 在 `D:\Program Files\Godot\`,headless 用带 `_console` 的)
- 开窗口:`Godot..._win64.exe --path godot`
- ⚠ 别同时跑两个 headless(抢 stdout/导入缓存,结果丢)。验证器约 0.5–0.9s/地质年。

**GDScript 坑**(`memory/godot-port.md` 有全列):`class_name` 在裸 `--script` 不解析→用 `preload`;`abs/max/min/clamp/floor` 返回 Variant,`:=` 推断报错→显式 `:float`/用 `floorf/clampf/clampi`;const Array 元素是 Variant,算术要 `float(ARR[e])`;`%` 格式不支持 `%e`(用 `str()`);嵌套 `a[j][i]` 是 Variant。网格已扁平化:索引 `k=j*NLon+i`,场是 `PackedFloat64Array`。

## 4. 已搬完(5 项,全部验证+提交;领先 origin 13 提交,未 push)

| 项 | 内容 | 验证器 | commit |
|---|---|---|---|
| 性能 | 嵌套Array→扁平PackedFloat64Array+复用缓冲,2.4× | validate | `4071cbd` |
| 守恒账本 | 碳4库+O₂(GOE)+氮(前一 agent) | conscheck | `4c356c1`/`7036b0f` |
| #1 食物网 | N→H(食草)→C(食肉)Holling-II,营养级视图 | fwcheck | `f95bb1c` |
| #2 有性+寄生 | rSex 红皇后,parasitesOn 对照 | rqcheck | `2cc0c28` |
| #3 冰川性海平面 | 冰量↔海平面,effSea+coarse_land_at 重算海陆 | slcheck | `0e86ada` |
| #4 逐格地质 | Geo.tectonics() 火山抬升+侵蚀改 elev | tectcheck | `a9c3d33` |
| #5 33元素化学 | disE/depE/subPoolE/rockE,风化→沉淀→埋藏→返还,逐元素守恒 | elemcheck | `a376036` |

关键接口:`World.geo`(注入 Geo,海平面/地质要)。`World.stepGeo()` 每地质年:tectonics→_seaStep(重算 Land)→carbonStep→elementStep→物种/灭绝→事件。`World.effSea()` 当前海平面。`Geo.coarse_land_at(nlat,nlon,sea)` 按海平面降采样海陆。视图:terrain/life/trophic/adapt/species/temp/prec/sst。探查面板已显示 营养级/有性/寄生/富集矿。

## 5. 剩余 4 项(按建议顺序)

### #6 史前有机化学 → 生命起源 + 闪电固氮(依赖 #5 元素底物)
world.html 参考:`_world_ref.html` 约 559–640 行(史前化学/cradle)、543 行(闪电固氮 `sFixPerStrike`)、415 行 `cradleIndex`。
- 机制:生命**之前**的有机分子(用 disE 里碳/磷/硫等 + 能量[闪电/火山喷口]+催化[黏土]+浓缩[干涸/高盐]+无氧)按合成↔水解张弛**累积**;某格累积量(cradle 评分)跨阈 → 确定性点燃生命(替代现在的 `Hab>IGNITE` 直接点燃,或作为前置门)。
- 闪电固氮:闪电(可由风暴/对流代理)把 atmN2→availN(已有氮库)。
- Godot 现状:生命起源是 `stepLife` 里 `Hab>IGNITE and N<SEED → N=SEED`。改成"先攒 organic 汤,够浓+无氧+有能量才点燃"。
- 验证 `prebiocheck.gd`:无氧早期才点燃(GOE 后氧高的地方更难)、cradle 高的格先出现生命、有机物守恒(碳来自 disE/CO₂)。

### #7 天文:多恒星/卫星/日月食/环/潮汐/辐射 + 米兰科维奇
world.html 参考:110–206 行(sunF/moonLight/eclipse/ringShadow/ringShine/tide)、222 行(`ecc/milankFlux`)。
- **默认地球态下多数退化**(单恒星单卫星无环)→ 真正有价值、最该先做的是**米兰科维奇轨道强迫**:偏心率/倾角周期(几万年)缓慢调制日照 → 调制冰期强度。Godot 现在冰期是固定 `climCool=ICE_AMP*sin(2π·geoT/ICE_PERIOD)`;加一个慢周期 milankovitch 因子乘到日照/climCool 上,让冰期有强弱节律。
- 机器(多 SUNS/MOONS/RING 数组、日月食几何、潮汐)可选搬成"可配置但默认退化",价值低、工作量大,**建议放最后或跳过**,除非要做非地球世界。
- 验证 `milankcheck.gd`:日照/冰期幅度随长周期调制,确定性。

### #8 水文气象 + 撞击
world.html 参考:485–537 行(stepMinute 里 wind/storm/wave/lightning/aquifer)、250 行(impact)、404 行(albedo 雪冰)。
- 逐格:含水层/地下水(土壤饱和→深渗→旱季基流泉)、雪/冰川积累(<冰点累积,接 #3 海平面的冰量)、海浪(风²弛豫)、风暴/闪电(电荷阈值→放电,喂 #6 固氮)。
- 撞击:轨道交点确定性事件(`geoT % impactPeriod`)→ 注尘遮日(撞击冬天,骤冷)+ 注碳 → 低 fit → 灭绝脉冲(走现有 massExtinctionCheck)。这个**最易做、戏剧性强**,可先挑出来做。
- 雪/冰川接 #3:现在 #3 的 iceVol 是用 climCool 代理;#8 做了真雪冰后,可把 iceVol 改成真实雪冰求和(更物理)。
- 验证:撞击冬天触发降温脉冲+灭绝;含水层旱季缓释;守恒。

### #9 局部生存层:地点/玩家/旅行(独立大阶段 = 生存游戏本体)
world.html 参考:444–479 行(mkLocs/setupWorld/neighbors)、696–704 行(travelTo/step)。
- 这是**生存游戏本身**:从全球行星某(纬,经)开一个高分辨率局部地点图,全球态(气候/海温/季节/海平面)按 `PushBoundary` 每天喂边界(见 `design_overview.md`)。玩家是一个人(人体生理模型 `design_food_water.md`:水/糖原/脂肪/体温),在地点间旅行求生。
- 核心体验已定(见 `GAME_NOTES.md` 第四节):**B 从赤手到掌控打底 + D 理解即进展精神,A 世系存续/C 旅程后期**。
- 这不是给全球行星加机制,是**新一层 + 玩家交互**,体量最大,建议作为独立里程碑、先做"最小可玩切片"(一个人+一个地点+身体模型接活气候,熬过一季)。

## 6. 收尾提醒
- 13 个本地提交**未 push**(`git push origin main`;注意 remote URL 里嵌了 PAT,建议提醒用户吊销重置)。
- 每搬一项:验证器过 → 窗口 smoke(`grep -i "script error"` 日志)→ 提交 → 更新 `memory/godot-port.md` 进度。
- 用户偏好:回复短、口语、纯文字;有副作用动作先经同意;**先 headless 验证再落地**。
