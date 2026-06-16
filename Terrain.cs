// ============================================================================
//  生存模拟 · 地形空间层 v0.1 —— 地点图 + 跨地点守恒水循环
//  把世界从「一个 0 维的点」升级为「一张地点图」：
//   · 节点 Region = 一份完整气候栈(复用 Events.cs) + 一组地形参数 Terrain；
//   · 边 = 流向(径流往低处 down) + 水汽扩散邻接；
//   · 全局天空(时间/太阳/月亮/季节)所有地点共享；局部状态各地点独立。
//  地形不是新物理，只是叠在已有气候模型上的一层「修正」(见 design_terrain.md)。
//  纯 C#，可 xUnit 直接测。
// ============================================================================
using System;
using System.Collections.Generic;
using System.Linq;

namespace SurvivalSim
{
    /// <summary>地点的静态地形参数。几个数就调制了整套已有气候。</summary>
    public sealed class Terrain
    {
        public string Name     = "平地";
        public double Elev     = 0;      // 海拔 m —— 决定年均温(慢层基准 −6.5°C/km)
        public double Sky      = 1.0;    // 天空开度 0..1 —— 只乘白天日照与光照(峡谷<1, 洞穴=0)
        public double SoilCap  = 100;    // 土壤持水量 —— 陡坡薄(小)→快饱和产流；盆地小→易蓄湖
        public double Oro      = 1.0;    // 抬升因子 —— 乘成云速率(迎风/高地>1 多降, 背风<1 雨影)
        public double LakeEvap = 0.0;    // 湖面蒸发倍率(0=不蓄湖；盆地>0 使湖位有进有出；海>0 作水汽源)
        public bool   IsCave   = false;  // 洞穴：无日照/月光/雨雪，温度跟随地表深层(年均)
        public bool   IsSea    = false;  // 海边：气温锚定海温(冬暖夏凉)，海作近乎无限水汽源
        public bool   Salty    = false;  // 海水/咸水：不能直接饮用(生存机制，供 BodyModel 用)
        public Lithology Lith  = Lithology.Sandstone;  // 岩性：决定风化出什么矿物/快慢(见 WaterChemistry)

        public static Terrain Flat => new Terrain();

        // —— 已验证的地形原型（数值见 design_terrain.md / Python hub3）——
        public static Terrain Coast   (string n="海边") => new Terrain{ Name=n, Elev=   0, Sky=1.00, SoilCap=30, Oro=0.80, LakeEvap=0.32, IsSea=true, Salty=true, Lith=Lithology.Sandstone };
        public static Terrain Forest  (string n="森林") => new Terrain{ Name=n, Elev= 300, Sky=0.85, SoilCap=60, Oro=1.00, LakeEvap=0.0,  Lith=Lithology.Clay };
        public static Terrain Wetland (string n="湿地") => new Terrain{ Name=n, Elev=  50, Sky=1.00, SoilCap=20, Oro=0.90, LakeEvap=0.50, Lith=Lithology.Clay };
        public static Terrain Foothill(string n="山脚") => new Terrain{ Name=n, Elev= 600, Sky=1.00, SoilCap=35, Oro=1.00, LakeEvap=0.0,  Lith=Lithology.Basalt };
        public static Terrain Mountain(string n="山顶") => new Terrain{ Name=n, Elev=1050, Sky=1.05, SoilCap=25, Oro=1.15, LakeEvap=0.0,  Lith=Lithology.Granite };
        public static Terrain Canyon  (string n="峡谷") => new Terrain{ Name=n, Elev= 500, Sky=0.50, SoilCap=30, Oro=1.00, LakeEvap=0.0,  Lith=Lithology.Limestone };
        public static Terrain Basin   (string n="盆地") => new Terrain{ Name=n, Elev= 150, Sky=1.00, SoilCap=15, Oro=0.85, LakeEvap=0.45, Lith=Lithology.Evaporite };
        public static Terrain Cave    (string n="洞穴") => new Terrain{ Name=n, Sky=0.0, IsCave=true, Lith=Lithology.Limestone };
    }

    /// <summary>岩性：风化速度 Speed × 各元素相对产率 Rate[Na,Ca,Mg,K,Fe]。决定本地水里溶出什么矿物。</summary>
    public sealed class Lithology
    {
        public string Name; public double Speed; public double[] Rate;
        // 元素序：Na Ca Mg K Fe | Cl SO4 HCO3 SiO2 Cu | I Zn
        public static Lithology Granite   => new Lithology{ Name="花岗岩", Speed=0.4, Rate=new[]{0.02,0.05,0.02,0.15,0.02, 0.01,0.02,0.05,0.40,0.005, 0.0,0.02} }; // 难溶·极淡·富硅(石英→燧石)
        public static Lithology Limestone => new Lithology{ Name="石灰岩", Speed=1.0, Rate=new[]{0.03,0.80,0.15,0.02,0.01, 0.02,0.10,0.90,0.05,0.005, 0.0,0.02} }; // 富钙·高碳酸盐(碱度/水垢)·成溶洞
        public static Lithology Basalt    => new Lithology{ Name="玄武岩", Speed=0.8, Rate=new[]{0.05,0.30,0.40,0.05,0.35, 0.02,0.08,0.15,0.20,0.30,  0.0,0.15} }; // 富镁铁·含铜(矿)·锌
        public static Lithology Sandstone => new Lithology{ Name="砂岩",   Speed=0.5, Rate=new[]{0.05,0.05,0.03,0.03,0.03, 0.03,0.03,0.04,0.50,0.01,  0.0,0.02} }; // 惰性·石英砂(硅)
        public static Lithology Evaporite => new Lithology{ Name="蒸发岩", Speed=1.5, Rate=new[]{1.50,0.50,0.20,0.10,0.00, 1.40,0.80,0.10,0.02,0.0,   0.0,0.05} }; // 岩盐(Na+Cl)·石膏(Ca+SO4)·成盐滩
        public static Lithology Clay      => new Lithology{ Name="黏土",   Speed=0.7, Rate=new[]{0.10,0.20,0.20,0.15,0.10, 0.08,0.10,0.20,0.15,0.05,  0.0,0.20} }; // 中等·吸附锌
    }

    /// <summary>本地点的矿物账本：溶解(在水里) / 沉积(盐壳固态) / 上游来矿(在途)。5 元素：Na Ca Mg K Fe。</summary>
    public sealed class MineralState
    {
        public readonly double[] Dissolved = new double[WaterChemistry.N];
        public readonly double[] Deposit   = new double[WaterChemistry.N];
        public readonly double[] Inflow    = new double[WaterChemistry.N];
    }

    /// <summary>水化学：矿物盐搭乘水循环。风化(岩石→溶解) · 蒸发浓缩 · 超溶解度析出盐壳 · 随径流搬运。
    /// 守恒：Σ(溶解+沉积) 只随风化(慢源)增长；蒸发只走纯水把矿物留下，是咸海/盐滩的成因。</summary>
    public static class WaterChemistry
    {
        // 元素序：Na Ca Mg K Fe | Cl SO4 HCO3 SiO2 Cu | I Zn
        public static readonly string[] Names = { "钠", "钙", "镁", "钾", "铁", "氯", "硫酸盐", "碳酸盐", "硅", "铜", "碘", "锌" };
        public static readonly double[]  Sol  = { 8.0, 0.4, 2.0, 3.0, 0.05, 9.0, 1.2, 0.6, 0.08, 0.03, 12.0, 0.2 };  // 溶解度上限：SiO2/Cu/Fe/Ca 易析出，Na/Cl/I 极难
        public const int N = 12;            // 元素个数
        public static double WeatherK = 0.0006;

        static double Water(Region r) => r.W.Get(WaterCycle.GroundWater) + r.W.Get(WaterCycle.Lake);

        /// <summary>风化：岩石→溶解矿物（暖+湿更快；海/洞不风化）。</summary>
        public static void Weather(Region r)
        {
            var t = r.Terrain; if (t.IsSea || t.IsCave) return;
            double wet = t.SoilCap > 0 ? r.W.Get(WaterCycle.GroundWater) / t.SoilCap : 0;
            double tf = Math.Max(0, Math.Min(1.5, (r.W.Get(Climate.AirTemp) + 5) / 25));
            for (int e = 0; e < WaterChemistry.N; e++)
                r.Minerals.Dissolved[e] += WeatherK * t.Lith.Speed * t.Lith.Rate[e] * wet * tf;
        }

        /// <summary>消化上游来矿（与水的 Inflow 同样 1 分钟/跳）。</summary>
        public static void IntakeInflow(Region r)
        { for (int e = 0; e < WaterChemistry.N; e++) { r.Minerals.Dissolved[e] += r.Minerals.Inflow[e]; r.Minerals.Inflow[e] = 0; } }

        /// <summary>析出/回溶：超溶解度→盐壳；不足且有盐壳→溶回。蒸发使水量变小→cap 变小→析出。</summary>
        public static void Precipitate(Region r)
        {
            double w = Math.Max(Water(r), 0.01); var M = r.Minerals;
            for (int e = 0; e < WaterChemistry.N; e++)
            {
                double cap = Sol[e] * w;
                if (M.Dissolved[e] > cap) { M.Deposit[e] += M.Dissolved[e] - cap; M.Dissolved[e] = cap; }
                else if (M.Deposit[e] > 0) { double x = Math.Min(M.Deposit[e], cap - M.Dissolved[e]); M.Deposit[e] -= x; M.Dissolved[e] += x; }
            }
        }

        // —— 读出（供 UI / 体力模型）——
        public static double Concentration(Region r, int e) { double w = Water(r); return w > 0.01 ? r.Minerals.Dissolved[e] / w : 0; }
        public static double Salinity(Region r) => Concentration(r, 0) + Concentration(r, 5);   // Na+Cl = 食盐
        public static double Tds(Region r) { double s = 0; for (int e = 0; e < WaterChemistry.N; e++) s += Concentration(r, e); return s; }  // 总溶解固体
        public static bool   Drinkable(Region r) => !r.Terrain.Salty && Salinity(r) < 0.3 && Tds(r) < 0.8;
        public static bool   HasSaltCrust(Region r) { for (int e = 0; e < WaterChemistry.N; e++) if (r.Minerals.Deposit[e] > 0.3) return true; return false; }
    }

    /// <summary>海洋气候：气温锚定一条温和的海温曲线(夏末最暖、冬末最冷)，而非自算 → 冬暖夏凉。
    /// 海本身(大湖)按 WaterCycle 蒸发作水汽源，经 WorldMap 扩散滋养内陆。</summary>
    public static class SeaClimate
    {
        public static double Base = 13, Amp = 6, PeakLag = 110, Follow = 0.02;  // 海温 = 13 ± 6°C，峰值滞后

        public static double SeaTempOf(int dayOfYear)
            => Base + Amp * Math.Sin(2 * Math.PI * (dayOfYear - PeakLag) / YearCycle.YearLength);

        public static void Install(EventSystem sys)
        {
            var w = sys.World;
            w.Define(Climate.GroundTemp, Climate.TempMin, Climate.TempMax, Base);
            w.Define(Climate.AirTemp,    Climate.TempMin, Climate.TempMax, Base);
            sys.Events.Add(new GameEvent("海洋调温", _ => true, ww =>
            {
                double st = SeaTempOf(ww.DayOfYear);
                ww.Set(Climate.GroundTemp, st);
                ww.Add(Climate.AirTemp, Follow * (st - ww.Get(Climate.AirTemp)));   // 缓慢趋近海温 → 稳、温和
            }));
        }
    }

    /// <summary>洞穴气候：无太阳项，温度钉在「所在地表地点的地温慢层」(≈年均温) → 冬暖夏凉、几近恒温。复用已有 GroundTemp。</summary>
    public static class CaveClimate
    {
        public static double Follow   = 0.02;  // 气温趋近深层的速率（小→更稳）
        public static double CaveRH    = 95;    // 洞内常年高湿

        public static void Install(EventSystem sys, World surface)
        {
            var w = sys.World;
            w.Define(Climate.GroundTemp, Climate.TempMin, Climate.TempMax, 8);
            w.Define(Climate.AirTemp,    Climate.TempMin, Climate.TempMax, 8);
            w.Define(SunCycle.Light, 0, SunCycle.LightPeak, 0);   // 终日无光
            w.Define(Humidity.RH, 0, 100, CaveRH);
            sys.Events.Add(new GameEvent("洞穴恒温", _ => true, ww =>
            {
                double deep = surface.Get(Climate.GroundTemp);     // 跟随地表深层（年均，季节滞后很大）
                ww.Set(Climate.GroundTemp, deep);
                ww.Add(Climate.AirTemp, Follow * (deep - ww.Get(Climate.AirTemp)));
            }));
        }
    }

    /// <summary>一个地点：一份气候栈(EventSystem+World) + 地形 + 流向。</summary>
    public sealed class Region
    {
        public readonly Terrain Terrain;
        public readonly EventSystem Sys;
        public readonly MineralState Minerals = new();   // 本地矿物账本（溶解/沉积/来矿）
        public Region Down;       // 径流去向（null = 终端，径流蓄成湖）
        public Region Parent;     // 洞穴所在的地表地点
        public World W => Sys.World;
        public string Name => Terrain.Name;

        public Region(GameClock clock, Terrain terrain, Region parent = null)
        {
            Terrain = terrain; Parent = parent;
            Sys = new EventSystem(clock, terrain);
            if (terrain.IsCave)
                CaveClimate.Install(Sys, (parent ?? throw new ArgumentException("洞穴需指定 parent 地表地点")).W);
            else
            {
                SunCycle.Install(Sys);                              // 时间(+季节)→太阳/月亮→光照(×天空开度)
                if (terrain.IsSea) SeaClimate.Install(Sys);         // 海边：气温锚定海温(冬暖夏凉)
                else Climate.Install(Sys);                          // 陆地：双层热惯性(海拔降基准 + 遮荫)
                Humidity.Install(Sys);    // 气温→相对湿度
                Cloud.Install(Sys);       // 云→挡日照/夜保温
                WaterCycle.Install(Sys);  // 本地水文 + 产径流（海=大湖蒸发作水汽源）
            }
        }

        public void Step() => Sys.RunEvents();

        // —— 本地点持有的水量（用于守恒核算）——
        public double WaterStock =>
            W.Get(WaterCycle.GroundWater) + W.Get(WaterCycle.Snow) +
            W.Get(Humidity.AbsH) + W.Get(Cloud.Cover) +
            W.Get(WaterCycle.Lake) + W.Get(WaterCycle.Inflow);   // Inflow=在途；不计 Runoff(报告量)
    }

    /// <summary>地点图：持有所有 Region + 边，由同一时钟驱动，每分钟跑三步并维持跨地点守恒。</summary>
    public sealed class WorldMap
    {
        public readonly GameClock Clock;
        public readonly List<Region> Regions = new();              // 须按 上游→下游 拓扑序加入
        public readonly List<(Region a, Region b)> DiffuseEdges = new();
        public double VaporDiffusion = 0.015;                      // 相邻地点水汽抹平速率
        // —— 玩家与固定路线（与水流 down / 水汽扩散 是不同的边：这是“能走的路”）——
        public Region Player;                                       // 玩家当前所在地点
        public readonly List<(Region a, Region b, int minutes)> Routes = new();

        public WorldMap(GameClock clock) { Clock = clock; }

        /// <summary>加一条固定双向路线，minutes=单程游戏分钟数。</summary>
        public void AddRoute(Region a, Region b, int minutes) => Routes.Add((a, b, minutes));

        /// <summary>从某地点出发能到的相邻地点 + 路程。</summary>
        public IEnumerable<(Region to, int minutes)> RoutesFrom(Region r)
            => Routes.Where(x => x.a == r || x.b == r).Select(x => x.a == r ? (x.b, x.minutes) : (x.a, x.minutes));

        /// <summary>沿路线移动到目的地：推进时钟(世界照常模拟途中天气)，再更新玩家位置。</summary>
        public void TravelTo(Region dest, int minutes) { Clock.Advance(minutes); Player = dest; }

        /// <summary>加入一个地点。down=径流去向；diffuseWith=与之做水汽扩散的邻居(通常即 down)。</summary>
        public Region Add(Terrain t, Region down = null, Region parent = null, Region diffuseWith = null)
        {
            var r = new Region(Clock, t, parent) { Down = down };
            Regions.Add(r);
            var nb = diffuseWith ?? down;
            if (nb != null) DiffuseEdges.Add((r, nb));
            return r;
        }

        public void Bind() => Clock.MinuteTick += _ => Minute();

        /// <summary>每分钟三步：① 逐地点气候(上游→下游) ② 径流路由 ③ 水汽扩散。</summary>
        public void Minute()
        {
            // ① 各地点本地气候/水文（Regions 即拓扑序）
            foreach (var r in Regions) r.Step();
            // ②a 矿物：岩石风化溶出 + 消化上游来矿
            foreach (var r in Regions) { WaterChemistry.Weather(r); WaterChemistry.IntakeInflow(r); }
            // ②b 地表径流路由：Runoff(连同按浓度携带的溶解矿物) → 下游 / 终端入湖（每跳 1 分钟，河道行进时延）
            foreach (var r in Regions)
            {
                double ro = r.W.Get(WaterCycle.Runoff);
                if (ro <= 0) continue;
                if (r.Down != null)
                {
                    double water = r.W.Get(WaterCycle.GroundWater) + r.W.Get(WaterCycle.Lake);
                    double frac = water > 1e-6 ? ro / water : 0;               // 径流带走的水占比 → 同比例带矿
                    for (int e = 0; e < WaterChemistry.N; e++)
                    {
                        double outE = Math.Min(r.Minerals.Dissolved[e], frac * r.Minerals.Dissolved[e]);
                        r.Minerals.Dissolved[e] -= outE; r.Down.Minerals.Inflow[e] += outE;
                    }
                    r.Down.W.Add(WaterCycle.Inflow, ro);
                }
                else r.W.Add(WaterCycle.Lake, ro);                             // 终端：水入湖，矿物留本地
                r.W.Set(WaterCycle.Runoff, 0);
            }
            // ②c 析出/回溶：蒸发浓缩→盐壳；遇水→溶回
            foreach (var r in Regions) WaterChemistry.Precipitate(r);
            // ③ 水汽沿边扩散（大气混合，守恒）→ 盆地湖蒸发的水汽能飘上山凝成雪
            foreach (var (a, b) in DiffuseEdges)
            {
                double f = VaporDiffusion * (a.W.Get(Humidity.AbsH) - b.W.Get(Humidity.AbsH));
                a.W.Add(Humidity.AbsH, -f); b.W.Add(Humidity.AbsH, f);
            }
        }

        /// <summary>全图总水量（守恒核算用，应逐分钟恒定；洞穴/天空不持水）。</summary>
        public double TotalWater() => Regions.Sum(r => r.WaterStock);

        public Region Find(string name) => Regions.FirstOrDefault(r => r.Name == name);

        // ====================================================================
        /// <summary>示例：一条 山顶→山坡→峡谷→盆地 的山谷 + 一个旁挂峡谷的洞穴（参数已 Python 验证）。</summary>
        public static WorldMap SampleValley(GameClock clock)
        {
            var map = new WorldMap(clock);
            // 自下游往上游建，便于把 down 指过去；但 Regions 需上游在前 → 建完后排序
            var basin  = map.Add(Terrain.Basin());                 // 终端：蓄湖
            var canyon = map.Add(Terrain.Canyon(), down: basin);
            var slope  = map.Add(Terrain.Slope(),  down: canyon);
            var mtn    = map.Add(Terrain.Mountain(), down: slope);
            var cave   = map.Add(Terrain.Cave(), parent: canyon);  // 洞穴挂在峡谷，温度跟随其地温
            // 重新按海拔从高到低排（上游→下游）确保每分钟先算上游、径流当回合下传
            map.Regions.Sort((x, y) => y.Terrain.Elev.CompareTo(x.Terrain.Elev));
            // 种子水预算（Python 验证：总水≈289 才够养出盆地季节湖）：预置盆地湖 + 抬高各地初始水汽
            basin.W.Set(WaterCycle.Lake, 40);
            foreach (var r in new[] { mtn, slope, canyon, basin }) r.W.Set(Humidity.AbsH, 16);
            return map;
        }

        /// <summary>示例世界：以海边为枢纽的放射状地图（玩家起点=海边），固定路线连接，海作水汽源。
        /// 三条边各不相同：down=水往低处流；DiffuseEdges=水汽扩散；Routes=玩家能走的固定路线。</summary>
        public static WorldMap SampleWorld(GameClock clock)
        {
            var map = new WorldMap(clock);
            // 地点（水流 down 按海拔：山顶→山脚→森林→海；峡谷→盆地蓄湖；湿地→海）
            var coast   = map.Add(Terrain.Coast());                    // 起点·终端汇水(海)
            var wetland = map.Add(Terrain.Wetland(),  down: coast);
            var forest  = map.Add(Terrain.Forest(),   down: coast);
            var foothill= map.Add(Terrain.Foothill(), down: forest);
            var mountain= map.Add(Terrain.Mountain(), down: foothill);
            var basin   = map.Add(Terrain.Basin());                   // 盆地蓄湖(终端)
            var canyon  = map.Add(Terrain.Canyon(),   down: basin);
            var cave    = map.Add(Terrain.Cave(), parent: canyon);
            // 水汽扩散边（海作源，向内陆渗）
            void Diff(Region a, Region b) => map.DiffuseEdges.Add((a, b));
            Diff(coast, forest); Diff(coast, wetland); Diff(coast, foothill);
            Diff(forest, canyon); Diff(canyon, basin); Diff(foothill, mountain);
            // 固定路线（玩家能走的路 + 单程分钟）——放射状：海边为枢纽
            map.AddRoute(coast, forest, 90);  map.AddRoute(coast, wetland, 60);  map.AddRoute(coast, foothill, 120);
            map.AddRoute(forest, canyon, 90); map.AddRoute(canyon, basin, 60);   map.AddRoute(canyon, cave, 30);
            map.AddRoute(foothill, mountain, 150);
            // 上游→下游次序（先算上游、径流当回合下传）
            map.Regions.Sort((x, y) => y.Terrain.Elev.CompareTo(x.Terrain.Elev));
            // 海=近乎无限水汽源 + 海水矿物谱(Na 主导 → 咸)
            coast.W.Set(WaterCycle.Lake, 5000);
            // Na Ca Mg K Fe | Cl SO4 HCO3 SiO2 Cu | I Zn —— 海水谱(Na/Cl 主导，富碘)
            double[] seawater = { 3000, 110, 360, 110, 0.5, 5390, 750, 30, 1, 0.1, 20, 0.5 };
            for (int e = 0; e < WaterChemistry.N; e++) coast.Minerals.Dissolved[e] = seawater[e];
            map.Player = coast;                                       // 起点：海边
            return map;
        }
    }
}
