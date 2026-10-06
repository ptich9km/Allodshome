#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Симуляция могущества великого мага: сколько сдачи нужно, чтобы держать фракцию.

Зачем этот скрипт: числа в GDD («2-3 слитка в час») были выбраны на глаз.
Здесь они проверяются прогоном, как того требует AGENTS.md 12 - числа измеряются,
а не подбираются. Игрок просил прогнать и на 100, и на 1000 дней.

Модель повторяет GDD (docs/lore/gdd_archmage.md, раздел 3):
  power: 0..100, старт 60
  спад за тик: decay_base + decay_threat * global_threat
  плата: слиток +1.0, золото(100) +1.0, зелье +1.5
  тик = sim_interval секунд реального времени

Запуск: python tests/sim_archmage_stakes.py
"""
from __future__ import annotations

import sys

POWER_MAX = 100.0
POWER_START = 60.0
TIER_THRESHOLDS = [0.0, 35.0, 65.0, 90.0]

DECAY_BASE = 0.0005
DECAY_THREAT = 0.0015

STAKES = {
    "слиток": 1.0,
    "золото(100)": 1.0,
    "зелье": 1.5,
}


def decay(threat: float) -> float:
    return DECAY_BASE + DECAY_THREAT * threat


def tier_of(power: float) -> int:
    tier = 0
    for i, thr in enumerate(TIER_THRESHOLDS):
        if power >= thr:
            tier = i
    return tier


def run(days: int, threat: float, per_day: float, stake: float,
        interval_s: float = 20.0, verbose: bool = False) -> dict:
    """Спрогнать N дней тиков; per_day - сколько сдачи в день (в ед. платы)."""
    power = POWER_START
    ticks_per_day = max(1, int(round(86400.0 / interval_s)))
    d = decay(threat)
    crossed: list[tuple[int, int]] = []
    prev_tier = tier_of(power)
    spent = 0.0

    for day in range(days):
        for _ in range(ticks_per_day):
            power -= d
            if power < 0.0:
                power = 0.0
        power = min(POWER_MAX, power + per_day * stake)
        spent += per_day
        t = tier_of(power)
        if t != prev_tier:
            crossed.append((day + 1, t))
            prev_tier = t

    ticks_total = days * ticks_per_day
    # сколько часов без сдачи до обнуления при power=60
    hours_empty = POWER_START / d * interval_s / 3600.0
    return {
        "days": days,
        "power_end": power,
        "tier_end": tier_of(power),
        "decay_per_tick": d,
        "ticks_total": ticks_total,
        "hours_to_zero_empty": hours_empty,
        "crossed": crossed,
        "spent": spent,
    }


def line(label: str, r: dict) -> None:
    cr = ",".join("%d->t%d" % c for c in r["crossed"]) or "-"
    print("  %-34s power=%5.1f tier=%d  сдано=%7.1f  переходы: %s"
          % (label, r["power_end"], r["tier_end"], r["spent"], cr))


def main() -> int:
    print("=" * 78)
    print("СПАД МОГУЩЕСТВА (сколько живёт фракция без игрока)")
    print("=" * 78)
    print("  decay = %.2f + %.2f * global_threat за тик, тик = 20 с"
          % (DECAY_BASE, DECAY_THREAT))
    print()
    print("  %-14s %-14s %-20s" % ("threat", "спад/тик", "часов без сдачи"))
    for threat in (0.0, 0.25, 0.5, 0.75, 1.0):
        r = run(1, threat, 0.0, 1.0)
        print("  %-14.2f %-14.3f %-20.1f"
              % (threat, r["decay_per_tick"], r["hours_to_zero_empty"]))

    print()
    print("=" * 78)
    print("ПРОГОН 100 ДНЕЙ - разные ставки сдачи в день (threat = 0.5)")
    print("=" * 78)
    for name, stake in STAKES.items():
        for per_day in (0.0, 0.5, 1.0, 2.0, 3.0, 5.0):
            r = run(100, 0.5, per_day, stake)
            print("  %-12s %4.1f/день = %-5.1f power/день  -> power %5.1f tier %d"
                  % (name, per_day, per_day * stake, r["power_end"], r["tier_end"]))
        print()

    print("=" * 78)
    print("ПРОГОН 1000 ДНЕЙ - кто выживает, а кто нет (threat = 0.5)")
    print("=" * 78)
    for per_day in (0.0, 0.5, 1.0, 2.0, 3.0):
        r = run(1000, 0.5, per_day, 1.0)
        print("  слиток %4.1f/день -> power %5.1f tier %d  переходы: %s"
              % (per_day, r["power_end"], r["tier_end"],
                 ",".join("%d->t%d" % c for c in r["crossed"]) or "-"))

    print()
    print("=" * 78)
    print("ТОЧКА БАЛАНСА: сколько платы в день держит power ровно на 60")
    print("=" * 78)
    ticks_per_day = int(round(86400.0 / 20.0))
    for threat in (0.0, 0.5, 1.0):
        d = decay(threat)
        need = d * ticks_per_day
        print("  threat %.2f: нужно %.3f платы/день  = %.1f слитков/день"
              % (threat, need, need / STAKES["слиток"]))

    print()
    print("=" * 78)
    print("ЧТО ЭТО ЗНАЧИТ В РЕАЛЬНОМ ВРЕМЕНИ (threat = 0.5, сдача 2 слитка/день)")
    print("=" * 78)
    r = run(30, 0.5, 2.0, 1.0)
    print("  30 игровых дней при 2 слитках/день: power %5.1f tier %d"
          % (r["power_end"], r["tier_end"]))
    r = run(30, 0.5, 0.5, 1.0)
    print("  30 игровых дней при 0.5 слитка/день: power %5.1f tier %d"
          % (r["power_end"], r["tier_end"]))
    print()
    print("  ВНИМАНИЕ: игровых дней пока НЕТ - сим-мир не тикает (GDD раздел 0).")
    print("  Здесь «день» - виртуальный, чтобы подобрать числа. В игре тик мага")
    print("  пойдёт по реальному времени, и пересчитать надо будет заново.")
    return 0


if __name__ == "__main__":
    sys.exit(main())