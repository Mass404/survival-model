// ============================================================================
//  生存模拟 · 全局时间 GameClock v0.1
//  设计原则：
//   1) 时间不可干扰——除了它自身的递进，外部只能"读"，不能加减。
//   2) 唯一权威量 = TotalMinutes（总分钟数，单调递增）。
//      日历(分/时/天/...)全部由它 除/取模 推导，不单独存 → 永不存在进位丢时间。
//   3) 节拍：1 现实秒 = 1 游戏分钟。用累加器驱动，掉帧/长帧也精确补足，不丢分钟。
//   4) 每过 1 游戏分钟发一次 MinuteTick —— 这是全模拟唯一的心跳。
//  纯 C#，无引擎依赖，可 xUnit 直接测。
// ============================================================================
using System;

namespace SurvivalSim
{
    public sealed class GameClock
    {
        // —— 唯一权威量：只有本类的递进能改它，外部只读 ——
        public long TotalMinutes { get; private set; }

        // —— 节拍配置 ——
        public double RealSecondsPerGameMinute = 1.0; // 1 现实秒 = 1 游戏分钟
        public double TimeScale = 1.0;                // 时钟自身的快进/慢放（0=暂停）。属于时钟控制，不是游戏实体在改时间。
        public bool Paused = false;

        double _acc; // 现实时间累加器（不足 1 分钟的余量留着，保证不丢时间）

        /// <summary>每过 1 游戏分钟回调一次，参数为推进后的总分钟数。全模拟的心跳。</summary>
        public event Action<long> MinuteTick;
        /// <summary>整点回调（可选粗粒度钩子）。</summary>
        public event Action<long> HourTick;
        /// <summary>跨天回调（可选）。</summary>
        public event Action<long> DayTick;

        /// <summary>由现实时间驱动。在每帧调用，传入真实经过的秒数。</summary>
        public void Update(double realDeltaSeconds)
        {
            if (Paused || realDeltaSeconds <= 0) return;
            _acc += realDeltaSeconds * TimeScale;
            // 长帧/快进可能一次跨过多分钟，逐分钟补足，绝不丢
            while (_acc >= RealSecondsPerGameMinute)
            {
                _acc -= RealSecondsPerGameMinute;
                AdvanceOneMinute();
            }
        }

        /// <summary>时间的自我递进——唯一的改时间入口。</summary>
        void AdvanceOneMinute()
        {
            long before = TotalMinutes;
            TotalMinutes++;
            MinuteTick?.Invoke(TotalMinutes);
            if (TotalMinutes % 60 == 0) HourTick?.Invoke(TotalMinutes);
            if (TotalMinutes % 1440 == 0) DayTick?.Invoke(TotalMinutes);
        }

        /// <summary>批量推进 N 游戏分钟（旅行/快进用：逐分钟触发心跳，世界照常模拟）。</summary>
        public void Advance(int minutes) { for (int i = 0; i < minutes && i >= 0; i++) AdvanceOneMinute(); }

        // —— 派生的只读日历视图（都是算出来的，不存储）——
        public int  Minute  => (int)(TotalMinutes % 60);
        public int  Hour    => (int)(TotalMinutes / 60 % 24);
        public int  Day     => (int)(TotalMinutes / 1440);     // 第几天（从0起）
        public int  DayOfWeek => (int)(TotalMinutes / 1440 % 7);
        public double Hours => TotalMinutes / 60.0;            // 连续小时数，给生理模型当 dt 用

        /// <summary>HH:MM 显示。</summary>
        public string Clock24 => $"{Hour:00}:{Minute:00}";
        public string Full    => $"第{Day + 1}天 {Clock24}";

        /// <summary>仅供存档/测试设置初始时刻（例如从早上8点开局）。</summary>
        public void SetStart(int day, int hour, int minute)
            => TotalMinutes = (long)day * 1440 + hour * 60 + minute;

        // ====================================================================
        //  集成示意（不在本类内做，写给你看接法）：
        //
        //    var clock = new GameClock();
        //    var body  = new HumanBody();
        //    clock.MinuteTick += _ => body.Step(1.0 / 60.0, EnvInput.Rest(22)); // 每游戏分钟推进 1/60 小时
        //    // 引擎每帧：clock.Update(delta);   // delta = 真实帧秒数
        //
        //  时间是节拍器，body 等所有"属性+动作"系统都挂在 MinuteTick 上按分钟推进。
        // ====================================================================
    }
}
