// ============================================================================
//  生存模拟 · 人体数据模型 v0.1 —— 食物(能量) + 水(水合)
//  纯 C#，无引擎依赖，可用 xUnit 直接测。所有常量集中在 BodyParams，便于标定。
//  单位：水 mL，能量 kcal，质量 g，温度 °C，时间 小时(h)，溶质 mOsm。
//  默认基准：70kg 成年人。
// ============================================================================
using System;

namespace SurvivalSim
{
    /// <summary>环境/行为输入（每个 Step 传入当前状况）。</summary>
    public struct EnvInput
    {
        public double AmbientC;       // 环境温度
        public double ActivityMult;   // 活动代谢倍率：1=静息, 2=步行, 4=重体力, 6+=冲刺
        public static EnvInput Rest(double tempC = 22) => new EnvInput { AmbientC = tempC, ActivityMult = 1.0 };
    }

    /// <summary>一份食物/饮品。按每克的属性描述，便于配方化。</summary>
    public struct FoodItem
    {
        public double MassG;        // 总克数
        public double KcalPerG;     // 能量密度
        public double WaterMlPerG;  // 含水量
        public double ProteinFrac;  // 蛋白质质量占比 0..1
        public double SaltGPerG;    // 含盐(钠盐) g/g

        // 几个示例食材（数值粗略，可改）
        public static FoodItem Water(double ml) => new FoodItem { MassG = ml, KcalPerG = 0, WaterMlPerG = 1, ProteinFrac = 0, SaltGPerG = 0 };
        public static FoodItem Jerky(double g)  => new FoodItem { MassG = g, KcalPerG = 4.1, WaterMlPerG = 0.05, ProteinFrac = 0.33, SaltGPerG = 0.04 }; // 牛肉干：高蛋白高盐低水 → 脱水陷阱
        public static FoodItem Coconut(double g)=> new FoodItem { MassG = g, KcalPerG = 1.6, WaterMlPerG = 0.50, ProteinFrac = 0.03, SaltGPerG = 0.0 };  // 椰肉：能量+大量水
        public static FoodItem Fish(double g)   => new FoodItem { MassG = g, KcalPerG = 2.0, WaterMlPerG = 0.65, ProteinFrac = 0.20, SaltGPerG = 0.002 };
    }

    /// <summary>可标定常量（默认值附带现实依据，调参主要改这里）。</summary>
    public class BodyParams
    {
        public double BodyMassG       = 70000;  // 体重
        public double WaterRefMl      = 42000;  // 正常体水量 ≈ 60% 体重
        public double GlycogenCapKcal = 1800;   // 肝+肌糖原容量 ≈ 静息约一天
        public double BmrKcalPerHour  = 70;     // 基础代谢 ≈ 1680 kcal/天
        public double FatStorageEff   = 0.8;    // 盈余转脂肪的效率
        public double FatKcalPerG     = 9.0;    // 脂肪能量密度
        public double FatCriticalG    = 3000;   // 脂肪低于此 → 瘦死(临界)

        public double MetWaterMlPerKcal = 0.13; // 代谢水：每消耗 1kcal 产生的水
        public double InsensibleMlPerHour = 40; // 不感蒸发(呼吸+皮肤) ≈ 960/天
        public double BaseUrineMlPerHour  = 45; // 基础尿量 ≈ 1080/天
        public double FecesWaterMlPerHour = 8;  // 粪含水 ≈ 192/天
        public double MaxUrineConc        = 1200; // 尿最大浓缩 mOsm/L → 决定"排溶质必带多少水"
        public double DiuresisFrac        = 0.3;  // 超出参考体水时的利尿强度/小时

        // 出汗：超过阈值温度 + 活动产热 → 排水(后续接体温系统后可替换)
        public double SweatThreshC          = 28;
        public double SweatPerDegPerHour     = 60;   // 每高于阈值1°C·每小时的汗(mL)
        public double SweatPerActivityPerHour= 120;  // 每多1个活动倍率·每小时的汗(mL)

        // 溶质负荷（强制排水的来源）
        public double SoluteMOsmPerProteinG = 4.0;   // 蛋白→尿素等
        public double SoluteMOsmPerSaltG    = 35.0;  // 盐(钠氯)
        public double SoluteClearPerHour    = 0.5;   // 每小时清除的待排溶质比例

        // 消化
        public double GastricEmptyPerHour   = 0.6;   // 胃排空比例/小时(水/溶质随之进入)
        public double MaxAbsorbKcalPerHour  = 300;   // 能量吸收上限(吃撑也不能瞬间回满)
    }

    public class HumanBody
    {
        public readonly BodyParams P;
        // —— 存量 ——
        public double WaterMl;       // 当前体水
        public double GlycogenKcal;  // 糖原储备
        public double FatG;          // 脂肪储备(g)
        // —— 胃内待消化缓冲 ——
        double _gKcal, _gWaterMl, _gProteinG, _gSaltG;
        double _pendingSoluteMOsm;   // 待肾脏排出的溶质

        public HumanBody(BodyParams p = null)
        {
            P = p ?? new BodyParams();
            WaterMl = P.WaterRefMl;
            GlycogenKcal = P.GlycogenCapKcal * 0.8;
            FatG = 12000; // ≈17% 体脂
        }

        public void Eat(FoodItem f)
        {
            _gKcal     += f.MassG * f.KcalPerG;
            _gWaterMl  += f.MassG * f.WaterMlPerG;
            _gProteinG += f.MassG * f.ProteinFrac;
            _gSaltG    += f.MassG * f.SaltGPerG;
        }
        public void Drink(double ml) => Eat(FoodItem.Water(ml));

        /// <summary>推进 dtH 小时。</summary>
        public void Step(double dtH, EnvInput env)
        {
            // 1) 消化：胃排空，水/溶质进入，能量按吸收上限释放
            double empty = Math.Min(1.0, P.GastricEmptyPerHour * dtH);
            double kcalIn = Math.Min(_gKcal, P.MaxAbsorbKcalPerHour * dtH);
            _gKcal -= kcalIn;
            double wIn = _gWaterMl * empty;   _gWaterMl  -= wIn;
            double pIn = _gProteinG * empty;  _gProteinG -= pIn;
            double sIn = _gSaltG * empty;     _gSaltG    -= sIn;
            WaterMl += wIn;
            _pendingSoluteMOsm += pIn * P.SoluteMOsmPerProteinG + sIn * P.SoluteMOsmPerSaltG;

            // 2) 能量支出 + 代谢水
            double expend = P.BmrKcalPerHour * Math.Max(0.5, env.ActivityMult) * dtH;
            WaterMl += expend * P.MetWaterMlPerKcal;

            // 3) 能量平衡：盈→糖原后转脂肪；亏→先糖原后脂肪
            double net = kcalIn - expend;
            if (net >= 0)
            {
                double space = P.GlycogenCapKcal - GlycogenKcal;
                double toGly = Math.Min(space, net);
                GlycogenKcal += toGly;
                FatG += (net - toGly) * P.FatStorageEff / P.FatKcalPerG;
            }
            else
            {
                double need = -net;
                double fromGly = Math.Min(GlycogenKcal, need);
                GlycogenKcal -= fromGly;
                FatG -= (need - fromGly) / P.FatKcalPerG;
                if (FatG < 0) FatG = 0;
            }

            // 4) 失水：不感蒸发 + 出汗 + 尿 + 粪
            double insensible = P.InsensibleMlPerHour * (1 + (env.ActivityMult - 1) * 0.5) * dtH;
            double sweat = SweatRate(env) * dtH;

            double soluteOut = _pendingSoluteMOsm * Math.Min(1.0, P.SoluteClearPerHour * dtH);
            _pendingSoluteMOsm -= soluteOut;
            double obligatoryUrine = soluteOut / P.MaxUrineConc * 1000.0; // 排这些溶质"必须"带走的水
            double urine = Math.Max(obligatoryUrine, P.BaseUrineMlPerHour * dtH);
            if (WaterMl > P.WaterRefMl) urine += (WaterMl - P.WaterRefMl) * P.DiuresisFrac * dtH; // 利尿
            double feces = P.FecesWaterMlPerHour * dtH;

            WaterMl -= insensible + sweat + urine + feces;
            if (WaterMl < 0) WaterMl = 0;
        }

        double SweatRate(EnvInput env) =>
            Math.Max(0, env.AmbientC - P.SweatThreshC) * P.SweatPerDegPerHour
            + Math.Max(0, env.ActivityMult - 1) * P.SweatPerActivityPerHour;

        // ===================== 派生输出（玩家实际感受到的）=====================
        public double EnergyKcal     => GlycogenKcal + FatG * P.FatKcalPerG;
        /// 失水占体重百分比：脱水严重度的标准口径(2%渴 / 5%乏力 / 10%危险 / 15%致命)
        public double DehydrationPct => (P.WaterRefMl - WaterMl) / P.BodyMassG * 100.0;
        /// 0(饱)..1(空) 的能量空虚度，糖原见底即明显饥饿
        public double Hunger         => 1.0 - Math.Min(1.0, GlycogenKcal / P.GlycogenCapKcal);
        /// 体力上限 0..1：脱水或低能量都会拖低（取较小者，短板决定）
        public double StaminaCapacity
        {
            get
            {
                double hyd = Clamp01(1 - (DehydrationPct - 2) / 8.0);   // 2%起降，10%归零
                double eng = Clamp01(GlycogenKcal / (P.GlycogenCapKcal * 0.3)); // 糖原30%以下开始掉
                return Math.Min(hyd, eng);
            }
        }
        public bool IsDead => DehydrationPct >= 15 || FatG <= P.FatCriticalG;

        public string Status()
        {
            string thirst = DehydrationPct < 2 ? "正常" : DehydrationPct < 5 ? "口渴" : DehydrationPct < 10 ? "脱水" : DehydrationPct < 15 ? "重度脱水" : "致命脱水";
            string food   = Hunger < 0.3 ? "饱足" : Hunger < 0.7 ? "饥饿" : FatG <= P.FatCriticalG * 1.3 ? "濒临饿死" : "极度饥饿";
            return $"水:{WaterMl:F0}mL(脱水{DehydrationPct:F1}% {thirst}) 能量:{EnergyKcal:F0}kcal(糖原{GlycogenKcal:F0} 脂肪{FatG:F0}g {food}) 体力上限{StaminaCapacity:P0}";
        }

        static double Clamp01(double v) => v < 0 ? 0 : v > 1 ? 1 : v;
    }
}
