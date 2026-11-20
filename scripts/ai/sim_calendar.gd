extends RefCounted
# Fixed-step, camera-independent simulation calendar. The design value of
# 2400 ticks/year is intentionally configurable in a future save migration.
const TICKS_PER_DAY := 8
const DAYS_PER_YEAR := 300
const TICKS_PER_YEAR := TICKS_PER_DAY * DAYS_PER_YEAR
const DAYS_PER_SEASON := 75
const SEASON_NAMES := ["Spring", "Summer", "Autumn", "Winter"]
const VERSION := 1

func date_at(tick: int) -> Dictionary:
    var safe_tick: int = maxi(0, tick)
    var year_index: int = safe_tick / TICKS_PER_YEAR
    var day_index: int = (safe_tick % TICKS_PER_YEAR) / TICKS_PER_DAY
    var season_index: int = day_index / DAYS_PER_SEASON
    return {"year": year_index + 1, "day": day_index + 1,
        "season_index": season_index, "season": SEASON_NAMES[season_index],
        "tick_of_day": safe_tick % TICKS_PER_DAY}

func age_years(birth_tick: int, tick: int) -> int:
    return maxi(0, (maxi(0, tick) - birth_tick) / TICKS_PER_YEAR)

func snapshot() -> Dictionary:
    return {"version": VERSION, "ticks_per_day": TICKS_PER_DAY,
        "days_per_year": DAYS_PER_YEAR}

func accepts_snapshot(data: Variant) -> bool:
    if not data is Dictionary:
        return false
    return int(data.get("version", -1)) == VERSION and int(data.get("ticks_per_day", -1)) == TICKS_PER_DAY and int(data.get("days_per_year", -1)) == DAYS_PER_YEAR
