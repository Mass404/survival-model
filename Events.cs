// ============================================================================
//  生存模拟 · 属性/动作/事件 框架 + 日出日落 + 光照属性 v0.1
//  约定（与时间系统一致）：
//   · 属性 = 一个数，存在 World 里；增减只能走 World.Add（唯一入口，便于审计）。
//   · 动作(GameAction) = 对 World 的一次改动，增减量可由其它属性算出。
//   · 事件(GameEvent) = 触发条件 + 一组动作；条件成立的每分钟执行其全部动作。
//   · 由 GameClock.MinuteTick 驱动：每游戏分钟，EventSystem 评估所有事件一次。
//  纯 C#，可 xUnit 直接测。
// ============================================================================
using System;
using System.Collections.Generic;

namespace SurvivalSim
{
    /// <summary>世界状态：一张"属性表"。增减只走 Add。</summary>
    public sealed class World
    {
        public GameClock Clock;
        public readonly Terrain Terrain;        // 本地点的地形参数（单点/平地时为 Terrain.Flat）
        readonly Dictionary<string, double> _attr = new();

        public World(GameClock clock, Terrain terrain = null) { Clock = clock; Terrain = terrain ?? Terrain.Flat; }

        readonly Dictionary<string, List<GameAction>> _reactions = new();
        readonly Dictionary<string, (double min, double max)> _range = new();   // 基础值：起点/终点
        int _depth = 0;

        /// <summary>用基础值约定属性范围（min=起点/下限，max=终点/上限）并给初值；之后增减自动夹在范围内。</summary>
        public void Define(string key, double min, double max, double initial)
        {
            _range[key] = (min, max);
            Set(key, initial);
        }
        public (double min, double max) RangeOf(string key)
            => _range.TryGetValue(key, out var r) ? r : (double.NegativeInfinity, double.PositiveInfinity);

        public double Get(string key) => _attr.TryGetValue(key, out var v) ? v : 0.0;

        /// <summary>设值；先按基础值范围夹紧；若值真的变了，触发"变动反应"（连锁）。</summary>
        public void Set(string key, double v)
        {
            if (_range.TryGetValue(key, out var r)) v = v < r.min ? r.min : v > r.max ? r.max : v;
            double old = Get(key);
            _attr[key] = v;
            if (v != old) Fire(key);
        }
        /// <summary>增减——走 Set，使其同样触发反应。运行期改属性的唯一入口。</summary>
        public void Add(string key, double d) => Set(key, Get(key) + d);

        /// <summary>把属性夹在区间内（动作里常用，防溢出）。</summary>
        public void Clamp(string key, double lo, double hi)
        {
            double v = Get(key);
            Set(key, v < lo ? lo : v > hi ? hi : v);
        }

        /// <summary>注册"当某属性变动时要执行的动作"（派生属性 / 连锁反应）。</summary>
        public void OnChange(string key, GameAction reaction)
        {
            if (!_reactions.TryGetValue(key, out var l)) { l = new List<GameAction>(); _reactions[key] = l; }
            l.Add(reaction);
        }
        void Fire(string key)
        {
            if (!_reactions.TryGetValue(key, out var list)) return;
            if (_depth > 32) return;   // 防连锁死循环
            _depth++;
            foreach (var r in list) r(this);
            _depth--;
        }

        public int MinuteOfDay => (int)(Clock.TotalMinutes % 1440);
        public int Day         => (int)(Clock.TotalMinutes / 1440);              // 第几天（从0起）
        public int DayOfYear   => ((Day % YearCycle.YearLength) + YearCycle.YearLength) % YearCycle.YearLength; // 0..YearLength-1
    }

    /// <summary>动作：读 World，做一次改动。</summary>
    public delegate void GameAction(World w);

    /// <summary>事件 = 触发条件 + 复杂动作集合。条件成立的每分钟执行全部动作。</summary>
    public sealed class GameEvent
    {
        public string Name;
        public Func<World, bool> Active;          // 触发/持续条件
        public readonly List<GameAction> Actions = new();

        public GameEvent(string name, Func<World, bool> active, params GameAction[] actions)
        { Name = name; Active = active; Actions.AddRange(actions); }

        public void Tick(World w)
        {
            if (Active(w)) foreach (var a in Actions) a(w);
        }
    }

    /// <summary>事件系统：挂在时间心跳上，每分钟评估所有事件。</summary>
    public sealed class EventSystem
    {
        public readonly World World;
        public readonly List<GameEvent> Events = new();

        public EventSystem(GameClock clock, Terrain terrain = null) { World = new World(clock, terrain); }

        /// <summary>绑定到时间心跳（单点用法）；多地点由 WorldMap 统一驱动，改调 RunEvents。</summary>
        public void Bind() { World.Clock.MinuteTick += _ => RunEvents(); }

        /// <summary>跑一轮事件（一分钟）。多地点时由 WorldMap 按上游→下游次序调用。</summary>
        public void RunEvents() { foreach (var e in Events) e.Tick(World); }
    }

    /// <summary>
    /// 年/季：把"年"做成"分钟→太阳"的慢一圈版本——不引入新存量，季节只由"一年中第几天"推导。
    ///  · 赤纬 δ 随一年正弦摆动（地轴倾角 ±23.44°），春分附近为 0；
    ///  · 太阳高度因子 = max(0, sinφ·sinδ + cosφ·cosδ·cosH)，φ=纬度、H=时角(随分钟)；
    ///  · 于是 日长 与 正午强度 一并随季节涌现：夏长冬短、夏高冬低；日出/日落不再写死，成涌现量。
    ///  · 纬度 Latitude 即"生物群系"旋钮：~5°近赤道几乎无四季；~40°温带四季；~62°高纬近极昼极夜。
    /// </summary>
    public static class YearCycle
    {
        public static int    YearLength   = 365;    // 一年游戏天
        public static double Latitude     = 40.0;   // 纬度°（生物群系旋钮）
        public static double AxialTilt     = 23.44;  // 地轴倾角°
        public static int    EquinoxDay    = 80;     // 春分约在第几天（δ=0 上行）
        public static double SynodicMonth  = 29.53;  // 朔望月（天）：月相一轮

        /// <summary>赤纬 δ（弧度）：夏至最大、冬至最小。接受小数日，便于算月亮的黄道位置。</summary>
        public static double Declination(double dayOfYear)
            => AxialTilt * Math.PI / 180.0 * Math.Sin(2 * Math.PI * (dayOfYear - EquinoxDay) / YearLength);

        /// <summary>季节名（北半球口径，按日序四等分）。</summary>
        public static string SeasonName(int dayOfYear)
        {
            int q = (dayOfYear - EquinoxDay + YearLength) % YearLength * 4 / YearLength; // 0春1夏2秋3冬
            return q == 0 ? "🌱 春" : q == 1 ? "☀️ 夏" : q == 2 ? "🍂 秋" : "❄️ 冬";
        }
    }

    /// <summary>
    /// 昼夜：依赖链 时间 → 太阳 → 光照。
    ///  · "太阳"(sun) 是高度因子 0..1，只由时间修改（现含季节：见 YearCycle）；
    ///  · 太阳每次变动 → 连锁动作把"光照"(light) 设为 峰值 × 太阳 × 云遮挡；
    ///  · 于是白天光照是以正午为顶的穹顶，且穹顶随季节升降、白昼随季节伸缩。
    /// </summary>
    public static class SunCycle
    {
        public const string Sun   = "sun";    // 太阳高度因子 0..1（仅由时间改）
        public const string Moon  = "moon";   // 月光因子 0..1 = 月相 × 月亮高度（仅由时间改）
        public const string Light = "light";  // 光照（由太阳 + 月亮 推导）

        public static double LightPeak = 100;  // 正午峰值光照（太阳=1 时）
        public static double MoonPeak  = 4;    // 满月·晴·当顶时的夜间光照（远小于白昼，但够"看得见"）

        /// <summary>太阳高度因子：天文式 sinElev，地平线下取 0。日长/强度随季节(赤纬)自动变化。</summary>
        public static double SunFactor(int minuteOfDay, int dayOfYear)
        {
            double phi = YearCycle.Latitude * Math.PI / 180.0;
            double dec = YearCycle.Declination(dayOfYear);
            double H   = 2 * Math.PI * (minuteOfDay / 1440.0) - Math.PI;   // 正午(720)→H=0
            double sinElev = Math.Sin(phi) * Math.Sin(dec) + Math.Cos(phi) * Math.Cos(dec) * Math.Cos(H);
            return sinElev > 0 ? sinElev : 0;
        }

        /// <summary>月光因子 = 月相照度 × 月亮高度。和太阳同一套天文式，只是月亮时角比太阳滞后一个相位角。
        /// 满月(相位0.5)与太阳相对→整夜高挂；新月(相位0)与太阳同行→白天升起(夜里无月光)。</summary>
        public static double MoonFactor(World w)
        {
            double f = (w.Clock.TotalMinutes / 1440.0 / YearCycle.SynodicMonth) % 1.0;   // 月相相位 0..1
            if (f < 0) f += 1;
            double illum = (1 - Math.Cos(2 * Math.PI * f)) / 2.0;                         // 照度：新月0 → 满月1
            double phi = YearCycle.Latitude * Math.PI / 180.0;
            double dec = YearCycle.Declination(w.DayOfYear + f * YearCycle.YearLength);   // 月亮黄道位置 = 太阳 + 相位
            double H = 2 * Math.PI * (w.MinuteOfDay / 1440.0) - Math.PI - 2 * Math.PI * f; // 月亮时角滞后相位
            double elev = Math.Sin(phi) * Math.Sin(dec) + Math.Cos(phi) * Math.Cos(dec) * Math.Cos(H);
            return illum * (elev > 0 ? elev : 0);
        }

        /// <summary>重算地面光照 = (日照 + 月光) × 云遮挡 × 天空开度；太阳/月亮/云量任一变动时触发。
        /// 天空开度 sky 把峡谷/洞顶的遮蔽算进来（洞穴 sky=0 → 终日无光）。</summary>
        public static void RecomputeLight(World w)
            => w.Set(Light, (LightPeak * w.Get(Sun) + MoonPeak * w.Get(Moon)) * Cloud.SunMultiplier(w) * w.Terrain.Sky);

        public static void Install(EventSystem sys)
        {
            var w = sys.World;
            w.Define(Sun, 0, 1, 0);
            w.Define(Moon, 0, 1, 0);
            w.Define(Light, 0, LightPeak, 0);
            w.OnChange(Sun, RecomputeLight);
            w.OnChange(Moon, RecomputeLight);
            // 时间驱动：每分钟刷新太阳与月亮（二者是仅有的"天体高度"来源）
            sys.Events.Add(new GameEvent("太阳运行", _ => true,
                ww => ww.Set(Sun, SunFactor(ww.MinuteOfDay, ww.DayOfYear))));
            sys.Events.Add(new GameEvent("月亮运行", _ => true,
                ww => ww.Set(Moon, MoonFactor(ww))));
            w.Set(Sun, SunFactor(w.MinuteOfDay, w.DayOfYear));
            w.Set(Moon, MoonFactor(w));
        }
    }

    /// <summary>
    /// 环境气温：双层热惯性（嵌套的"积分滞后"——日内滞后 + 季节滞后）。
    ///  · 慢层 地温(groundTemp)：大地/水体的热库，时间常数≈两周 → 一年内缓慢蓄/放热，
    ///    使最热出现在夏至之后、最冷在冬至之后（季节滞后）。
    ///  · 快层 气温(airTemp)：绕"地温"做日内振荡（加热系数/散热是属性，可被风/云/季节改），
    ///    午后到顶、黎明触底（日内滞后）。
    ///  · 云：挡日照→两层白天升温都减弱；保温→夜间气温散热减弱（压平昼夜温差）。
    ///  · 系数按"晴空"标定（晴天约 -6~30°C@40°）；多云/雨季会自动偏凉，符合现实。
    /// 必须在 SunCycle.Install 之后调用（要读当分钟已刷新的 sun）。
    /// </summary>
    public static class Climate
    {
        public const string AirTemp    = "airTemp";     // 环境气温 °C（快层）
        public const string GroundTemp = "groundTemp";  // 地温 °C（慢层，季节热库）
        public const string HeatGain   = "heatGain";    // 气温加热系数：满日照每分钟升温潜力
        public const string HeatLoss   = "heatLoss";    // 气温散热系数：每分钟每度(气温-地温)的散热

        public static double TempMin = -40, TempMax = 55;
        public static double BaseHeatGain = 0.10;   // 调定(40°温带)：晴天日温差夏≈12°C
        public static double BaseHeatLoss = 0.007;
        // 慢层（地温）系数：吸热慢、漏热更慢 → 季节滞后≈夏至后~10天
        public static double GroundGain = 0.0065;
        public static double GroundLoss = 0.00007;
        public static double GroundFloor = -16;     // 海平面慢层基准；各地点再按海拔降温
        public static double Lapse = 6.5 / 1000.0;   // 气温直减率 °C/m（海拔每升高定年均温）

        /// <summary>本地点的慢层基准 = 海平面基准 − 直减率×海拔。</summary>
        public static double GroundBaseOf(Terrain t) => GroundFloor - Lapse * t.Elev;

        public static void Install(EventSystem sys)
        {
            var w = sys.World;
            double init = 8 - Lapse * w.Terrain.Elev;   // 按海拔给个就近初值（慢层会自行收敛）
            w.Define(HeatGain, 0, 5, BaseHeatGain);
            w.Define(HeatLoss, 0, 1, BaseHeatLoss);
            w.Define(GroundTemp, TempMin, TempMax, init);
            w.Define(AirTemp,    TempMin, TempMax, init);
            // 每分钟积分：先推慢层(地温)，再推快层(气温，绕地温振荡)
            sys.Events.Add(new GameEvent("气温积分", _ => true, ww =>
            {
                var ter = ww.Terrain;
                double sunGround = ww.Get(SunCycle.Sun) * Cloud.SunMultiplier(ww);   // 地温：全日照（海拔定年均，不受遮荫）
                double sunAir    = sunGround * ter.Sky;                              // 气温白天增益：再乘天空开度（峡谷少晒）
                double gBase = GroundFloor - Lapse * ter.Elev;
                ww.Add(GroundTemp, GroundGain * sunGround - GroundLoss * (ww.Get(GroundTemp) - gBase));
                ww.Add(AirTemp, ww.Get(HeatGain) * sunAir                            // 白天升温（云挡+遮荫→减弱）
                              - ww.Get(HeatLoss) * Cloud.CoolMultiplier(ww) * (ww.Get(AirTemp) - ww.Get(GroundTemp))); // 向地温回落（云保温）
            }));
        }
    }

    /// <summary>
    /// 湿度：相对湿度与气温反相。
    ///  · 绝对湿度(absHumidity) 是水汽量，属性（可被下雨/蒸发/风改）；
    ///  · 饱和容量 SatCap(气温)：气温越高能容纳的水汽越多；
    ///  · 相对湿度 = 绝对湿度 / 饱和容量 ×100 —— 气温或绝对湿度任一变动即重算；
    ///  · 结果：午后最干、黎明最潮（接近饱和→结露/雾）。
    /// 必须在 Climate.Install 之后调用。
    /// </summary>
    public static class Humidity
    {
        public const string AbsH = "absHumidity";  // 绝对湿度 g/m³（水汽量）
        public const string RH   = "humidity";      // 相对湿度 %（推导）

        public static double BaseAbs = 8;            // 默认水汽量（调定：黎明≈97%、午后≈20%）
        public static double AbsMax = 50;

        /// <summary>饱和绝对湿度 g/m³（Magnus 公式）。</summary>
        public static double SatCap(double tempC)
        {
            double es = 6.112 * Math.Exp(17.62 * tempC / (243.12 + tempC)); // 饱和水汽压 hPa
            return 216.7 * es / (273.15 + tempC);
        }

        public static void Install(EventSystem sys)
        {
            var w = sys.World;
            w.Define(AbsH, 0, AbsMax, BaseAbs);
            w.Define(RH, 0, 100, 50);
            // 重算相对湿度：绝对湿度 或 气温 任一变动都触发
            GameAction recompute = ww =>
            {
                double cap = SatCap(ww.Get(Climate.AirTemp));
                ww.Set(RH, cap > 0 ? ww.Get(AbsH) / cap * 100.0 : 100);
            };
            w.OnChange(Climate.AirTemp, recompute);
            w.OnChange(AbsH, recompute);
            recompute(w); // 初值
        }
    }

    /// <summary>
    /// 云层 = 大气(高空)水汽含量 / 云量（区别于地面相对湿度）。
    ///  · 挡日照 → 阴天白天升温减弱（也压低地面光照）；
    ///  · 盖夜间散热 → 阴天夜里更暖；合起来=压平昼夜温差；
    ///  · 攒够将来可触发下雨（下一步）。
    /// 现阶段云量是可调基准（可由蒸发/天气事件驱动）。
    /// </summary>
    public static class Cloud
    {
        public const string Cover = "cloud";   // 云量 / 大气水汽 0..100
        public static double ShadeK = 0.8;       // 满云遮挡日照比例
        public static double GreenhouseK = 0.6;  // 满云减少夜间散热比例
        public static double BaseCover = 20;

        public static double Frac(World w) => w.Get(Cover) / 100.0;
        public static double SunMultiplier(World w)  => 1.0 - ShadeK * Frac(w);       // 到地面的日照系数（云未定义时=1，无影响）
        public static double CoolMultiplier(World w) => 1.0 - GreenhouseK * Frac(w);  // 夜间散热系数

        public static void Install(EventSystem sys)
        {
            var w = sys.World;
            w.Define(Cover, 0, 100, BaseCover);
            // 云量变动 → 重算地面光照（气温每分钟积分会自动读云量，无需额外反应）
            w.OnChange(Cover, SunCycle.RecomputeLight);
        }
    }

    /// <summary>
    /// 本地点水文：土壤含水 / 积雪 / 湖，加与相邻地点的耦合接口（径流 Inflow/Runoff，水汽由 WorldMap 扩散）。
    ///  · 土壤含水(GroundWater)：喂蒸发的本地蓄水，0..地形.SoilCap（陡坡薄、易饱和产流）。
    ///  · 蒸发：土壤+湖面 → 水汽；成云×地形.Oro（迎风抬升多降）；降水按气温分流雨/雪；度日融雪。
    ///  · 地表水（本地雨+融雪 + 上游 Inflow）先下渗补土壤，超出田间持水量即为 Runoff（交 WorldMap 路由下游/入湖）。
    /// 守恒跨整张图：Σ各地点(土壤+积雪+水汽+云+湖) = 常量（路由/扩散都是转移）。
    /// </summary>
    public static class WaterCycle
    {
        public const string GroundWater = "groundWater";  // 土壤含水 0..SoilCap（喂蒸发）
        public const string Snow        = "snow";          // 积雪（雪水当量）——降水的低温分支
        public const string Lake        = "lake";          // 地表积水/湖（终端汇水点蓄成）
        public const string Raining     = "raining";       // 是否降水 0/1（雪/雨由气温区分）
        public const string Inflow      = "inflow";        // 本分钟上游来水（WorldMap 填、本事件读、WorldMap 末清零）
        public const string Runoff      = "runoff";        // 本分钟产出径流（本事件填、WorldMap 读去路由）
        public static double BaseWater = 70;
        public static double SnowCap   = 600;   // 抬高上限：高山多雪不会顶到上限被截（截断=毁水，会破坏守恒）
        public static double LakeCap   = 100000;   // 湖几乎不设上限（守恒由转移保证）

        // 调定参数（Python 验证：总量守恒、约 3 天一场阵雨）
        public static double EvapK    = 0.035;  // 蒸发系数
        public static double VaporMax = 45;     // 低空水汽“容量”（趋满则蒸发变慢）
        public static double CondK    = 0.0045; // 成云（低空→云）系数
        public static double DispK    = 0.001;  // 云消散（云→低空）系数
        public static double RainK    = 0.015;  // 降水强度系数
        public static double RainHi   = 42;     // 云量超此 → 起雨
        public static double RainLo   = 12;     // 云量降至此 → 停雨（滞回，形成阵雨）
        // 雪/融雪（Python 验证：温带40° 冬积雪、开春融光、涌现春汛）
        public static double SnowTemp = 1.0;    // 气温≤此 → 降水落雪而非落雨
        public static double MeltTemp = 0.0;    // 度日融雪起始温度
        public static double MeltK    = 0.006;  // 度日融雪系数：每分钟每度(气温-起始)融雪量

        public static void Install(EventSystem sys)
        {
            var w = sys.World;
            double soilCap = w.Terrain.SoilCap;
            w.Define(GroundWater, 0, soilCap, Math.Min(soilCap, BaseWater));
            w.Define(Snow,   0, SnowCap, 0);
            w.Define(Lake,   0, LakeCap, 0);
            w.Define(Raining, 0, 1, 0);
            w.Define(Inflow, 0, LakeCap, 0);
            w.Define(Runoff, 0, LakeCap, 0);
            // 每分钟：本地水文结算 + 产出径流（顺序排在太阳/气温之后，需用本分钟已积分的气温）
            sys.Events.Add(new GameEvent("水循环", _ => true, ww =>
            {
                var ter = ww.Terrain;
                double sunSky = ww.Get(SunCycle.Sun) * ter.Sky;       // 遮荫减弱蒸发/成云
                double airT = ww.Get(Climate.AirTemp);
                double soil = ww.Get(GroundWater), V = ww.Get(Humidity.AbsH), C = ww.Get(Cloud.Cover), lake = ww.Get(Lake);
                double dry = Math.Max(0, 1 - V / VaporMax);
                double Es = Math.Min(EvapK * sunSky * dry, soil);              // 土壤蒸发
                double El = Math.Min(EvapK * sunSky * dry * ter.LakeEvap, lake); // 湖面蒸发
                double F = CondK * ter.Oro * V * (0.3 + 0.7 * sunSky);        // 成云（地形抬升增强）
                double D = DispK * C;
                bool storm = ww.Get(Raining) > 0.5;
                if (!storm && C > RainHi) storm = true;
                double R = storm ? RainK * C : 0;
                if (storm && (C - R) < RainLo) storm = false;
                double toSnow = (R > 0 && airT <= SnowTemp) ? R : 0;          // 冷→雪
                double rainIn = R - toSnow;
                double melt = Math.Min(ww.Get(Snow), MeltK * Math.Max(0, airT - MeltTemp)); // 度日融雪
                // 大气 / 雪 / 湖蒸发 结算
                ww.Add(Snow, toSnow - melt);
                ww.Add(Humidity.AbsH, Es + El - F + D);   // → 自动重算相对湿度
                ww.Add(Cloud.Cover,  F - D - R);          // → 自动重算光照
                ww.Add(Lake, -El);                         // 入湖径流由 WorldMap 处理
                ww.Set(Raining, storm ? 1 : 0);
                // 地表水：蒸发先扣土壤；本地(雨+融雪)+上游来水 下渗补土壤，余为径流
                double inWater = rainIn + melt + ww.Get(Inflow);
                double soilAfterEvap = soil - Es;
                double space = Math.Max(0, ter.SoilCap - soilAfterEvap);
                double infil = Math.Min(space, inWater);
                ww.Set(GroundWater, soilAfterEvap + infil);
                ww.Set(Runoff, inWater - infil);           // 交 WorldMap 路由（下游 Inflow 或 终端入湖）
                ww.Set(Inflow, 0);                          // 上游来水已消化，清零（守恒：其水已进 土壤/径流）
            }));
        }
    }

    // ========================================================================
    //  气候栈安装顺序（每个地点都装这一套；由 Region.Install 调用）：
    //    SunCycle → Climate → Humidity → Cloud → WaterCycle
    //  · 单点用法（平地）：var sys=new EventSystem(clock); 装上面五个; sys.Bind();
    //  · 多地点用法：见 Terrain.cs 的 WorldMap —— 它每分钟按 上游→下游 调 Region.RunEvents()，
    //    再做 径流路由(Runoff→下游Inflow/终端入湖) 与 水汽扩散，实现跨地点守恒水循环。
    //  读取： Light(含月光) / SunCycle.Sun,Moon / Climate.AirTemp,GroundTemp / Humidity.RH /
    //        Cloud.Cover / WaterCycle.GroundWater,Snow,Lake,Raining ；季节 YearCycle.SeasonName(world.DayOfYear)
    // ========================================================================
}
