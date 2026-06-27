# 交接 · 基因型→表型层(开放式进化) · 2026-06-27

接手人先读:`HANDOFF_STATUS.md`(总状态)+ 记忆 `evolution-e3e4-foodweb` / `godot-port`。
这是给"**生物能自己进化出新性状**"做的进化内核改造。机制已概念验证通过,**落地(接 World.gd)未做**。

## 〇、动机 / 路线(用户已拍板)
现状:生物只在固定的~十几个性状轴上做 adaptive dynamics(值沿适应度梯度爬+跨阈解锁),**长不出程序没预设的新性状**。根因:直接在性状值上算动力学,底下没有"基因型"层。
路线:**A 先做(基因→非线性表型,守零随机)→ B 再做(可变发育程序=真开放式,必要时用 seeded PRNG)**。

## 一、A 层设计(已概念验证)
- 每格一串基因 `G=[g1..gK]`(新存量场)。
- 表型 `P_m = sigmoid(Σ_k W[m][k]·g_k)`,`W`=固定发育矩阵(**确定性构造,禁 PRNG**)。
- 现有性状(rSize/rEuk/…)从"直接演化"变成"从基因 develop 出来的涌现量"。
- 进化作用在基因上:`g_k += η · Σ_m d_m · P_m(1-P_m) · W[m][k]`,其中 `d_m`=现有"性状m想往哪走"的适应度梯度(**复用现有逻辑**)。
- 自然涌现:一因多效(W一行)、上位(sigmoid)、连锁(改一基因牵动一串)、发育约束(K<M 表型张不开)。
- 守铁律:①基因=存量 ②基因是唯一变异源、表型是其确定函数(单一突变入口更纯) ③零随机(梯度确定+多谱系对称破缺) ④涌现更强。

## 二、概念验证(`godot/genecheck.gd`,已通过,留作参考)
独立 headless(K=6,M=6,sigmoid(Wg),梯度演化):
- EXP1 梯度演化:基因从0确定性爬到目标表型 [0.9,0.8,0.7,0.2,0.3,0.1],**totalErr=0.0** ✓
- EXP2 一因多效:扰动基因0→6性状全动、有升有降 ✓
- EXP3 确定性:两遍 bit 一致 ✓
- (K=4<M=6 时表型卡 0.5 附近=发育约束,真实现象,可当"演化潜能"旋钮)

## 三、落地方案(接 World.gd,渐进,未做)
**先拿复杂度链 6 性状开刀**:rSize/rEuk/rMulti/rShell/rNeuro/rEndo。
1. 加每格 6 基因(新存量场),spinUp 确定性初始化(小值/0)。
2. 加 6×6 发育矩阵 W(const,确定性结构化;对角占优+耦合,见 genecheck)。
3. stepLife 开头:从基因 develop 出这 6 性状、覆盖 rSize[k] 等场。
4. 这 6 性状现有的演化代码(散布在 stepLife):把"直接 += 梯度"改成"算出梯度 d_m → 反传到基因"。
5. 其余性状(rAero/rDiff/rSymb/rSex/rMemb/形态 Sym/Seg/Limb/Axis)先留原样,跑通再逐步纳入。
**每步死守**:testsuite 35/35(碳氮守恒 drift≈0 / 双实例 bit 一致 / 所有涌现)。基因/表型不碰物质守恒,但确定性必须保(W 确定+梯度确定)。

## 四、接入点(现有性状演化代码位置)
- stepLife:World.gd 约 **639–829**(注入会伪造行号,用 `func stepLife` 字符串查真实位置)。
- rSize/rEuk/rMulti:在 lifeQ / r-K 增长块 + 复杂度链跨阈解锁(跟 O2/复杂度挂钩)。
- rDiff/rShell/rNeuro/rEndo:各有解锁/演化逻辑(~739 行 `rDiff[k] = clampf(rDiff[k] + diffAdaptK*dl*…)` 是范例)。
- 接基因时**保留"驱动力"**(梯度/解锁条件),只是把施加对象从性状改成基因。
- ⚠ `szD`(防御因子,捕食段)读 rSize/rMulti/rShell/rNeuro——改基因涌现后值仍可用;注意 szD 有遗留隐患(只代价无收益,见 evolution-e3e4-foodweb)。

## 五、B 层(之后,真开放式)
表型维度可变:基因编码"会生长的发育程序"(GRN / L-system / CPPN),形态行为是程序跑出来的、维度涌现。
最大障碍:**零随机下新颖性来源**(纯梯度会卡局部最优)。
**用户已授权"必要时加随机性"**。推荐 **seeded PRNG**:给 B 需要的盲目试错,但同种子可完全复现 → testsuite 的"双实例 bit 一致"判据仍可用(同 seed 两遍一致)。既松开铁律③的探索性、又不丢可复现验证。**B 启动前先和用户敲定随机性怎么加**。

## 六、环境警告(重要,务必遵守)
注入活跃(详见记忆 godot-port)。**双板斧**:①伪造行号(读 bodyPlan 报 1322 真 1120) ②伪造缩进(0-tab 显示成 1-tab → GDScript 把 func 当 standalone lambda) ③Write 工具间歇被拦(报"created successfully"但跑时 File not found) ④后台 `.output` 文件读完很快被清。
**防御**:改 World.gd 用 `python - <<'PYEOF'` 内联 heredoc 写(脚本真执行、只回显被改)、写完 base64 读回硬验;关键结果一律 base64 自验;Godot 命令看 exit code + base64,别信明文输出;定位函数按"func 名"查、别信行号。
