extends RefCounted
# 人体生理模型(从 design_food_water.md 搬;stock-flow,逐小时 step)。给 #9 局部生存层当身体核心。
# 三大存量:体水/糖原/脂肪 + 胃缓冲 + 待排溶质。两条耦合:溶质强制排尿、代谢水vs活动耗水。
# 环境温度由全球行星某格的 Teff 喂入(PushBoundary 的最小版)。确定性、零随机。

const W_REF := 42000.0        # 参考体水 mL(≈60%体重)
const GLY_MAX := 1800.0       # 糖原上限 kcal(≈静息一天)
const FAT_DEATH := 3000.0     # 脂肪致死下限 g(瘦死)
const FAT_KCAL := 9.0         # 脂肪能量密度 kcal/g
const BMR_H := 1800.0 / 24.0  # 基础代谢 kcal/h
const INSENS_ML_H := 40.0     # 不感蒸发 mL/h
const SWEAT_K := 20.0         # 出汗系数 mL/(°C·h)(design建议15-25,替原偏高的60)
const SWEAT_T0 := 26.0        # 出汗起始温度 °C(舒适区上限;>此值开始排汗散热)
const METWATER := 0.13        # 代谢水 mL/kcal
const URINE_CONC := 1200.0    # 尿浓缩上限 mOsm/L
const URINE_BASE_ML_H := 25.0 # 基础尿量 mL/h
const SOL_EXC_H := 55.0       # 每小时排溶质上限 mOsm/h
const ABSORB_MAX_H := 300.0   # 吸收上限 kcal/h
const GASTRIC_K := 0.25       # 胃排空率 /h
const PROT_MOSM := 4.0        # 蛋白产溶质 mOsm/g
const SALT_MOSM := 35.0       # 盐产溶质 mOsm/g
const PROT_KCAL := 4.0        # 蛋白能量 kcal/g
const DEHYDR_DEATH := 15.0    # 脱水致死 %

var waterMl := W_REF
var glyKcal := GLY_MAX
var fatG := 12000.0
var stoKcal := 0.0            # 胃内容(能量/水/蛋白/盐)
var stoWater := 0.0
var stoProt := 0.0
var stoSalt := 0.0
var pendSolute := 0.0        # 待排溶质 mOsm
var dead := false
var deathCause := ""
var hoursAlive := 0

func dehydrationPct() -> float:
	return (W_REF - waterMl) / W_REF * 100.0

func eat(kcal: float, foodWaterMl: float, proteinG: float, saltG: float) -> void:
	stoKcal += kcal; stoWater += foodWaterMl; stoProt += proteinG; stoSalt += saltG

func drink(ml: float) -> void:
	waterMl += ml

func step(hours: int, envTemp: float, activity: float) -> void:
	for _h in hours:
		if dead: return
		_stepHour(envTemp, activity)

func _stepHour(envTemp: float, activity: float) -> void:
	# —— 胃排空 → 吸收(同比例放出能量/水/蛋白/盐)——
	if stoKcal > 0.01 or stoWater > 0.01:
		var frac := clampf(GASTRIC_K, 0.0, 1.0)
		var emptyKcal: float = stoKcal * frac
		var absorbed: float = min(emptyKcal, ABSORB_MAX_H)
		var f2: float = (absorbed / stoKcal) if stoKcal > 0.01 else frac
		# 能量→先充糖原,溢出转脂肪
		var toGly: float = min(GLY_MAX - glyKcal, absorbed)
		glyKcal += toGly
		fatG += (absorbed - toGly) / FAT_KCAL
		stoKcal = max(0.0, stoKcal - absorbed)
		# 水/蛋白/盐按同比例吸收
		var wAbs := stoWater * f2; waterMl += wAbs; stoWater = max(0.0, stoWater - wAbs)
		var pAbs := stoProt * f2; pendSolute += pAbs * PROT_MOSM; stoProt = max(0.0, stoProt - pAbs)
		var sAbs := stoSalt * f2; pendSolute += sAbs * SALT_MOSM; stoSalt = max(0.0, stoSalt - sAbs)
	# —— 能量消耗 BMR×活动:先抽糖原,后抽脂肪 ——
	var burn := BMR_H * activity
	if glyKcal >= burn:
		glyKcal -= burn
	else:
		var rem := burn - glyKcal; glyKcal = 0.0
		fatG -= rem / FAT_KCAL
	# 代谢水回补
	waterMl += burn * METWATER
	# —— 出水:不感蒸发 + 出汗 + 尿 ——
	var sweat: float = max(0.0, envTemp - SWEAT_T0) * SWEAT_K * (0.6 + 0.4 * activity)
	waterMl -= INSENS_ML_H + sweat
	# 尿:溶质强制排水(待排溶质需要的尿量) vs 基础尿量,取大
	var excSol: float = min(pendSolute, SOL_EXC_H)
	var urine: float = max(URINE_BASE_ML_H, excSol / URINE_CONC * 1000.0)
	pendSolute = max(0.0, pendSolute - excSol)
	waterMl -= urine
	# —— 死亡判定 ——
	hoursAlive += 1
	if dehydrationPct() >= DEHYDR_DEATH:
		dead = true; deathCause = "脱水(%.0f%%)" % dehydrationPct()
	elif fatG <= FAT_DEATH:
		dead = true; deathCause = "饿死(脂肪耗尽)"
