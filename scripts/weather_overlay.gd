extends Node2D
class_name PixelWeatherOverlay

# Bounded, sparse pixel-sized streaks only. No particles, shaders, textures,
# new world entities or simulation RNG consumption.
var view := Rect2()
var clock := 0.0
var rain := 0.0
var wind := Vector2.RIGHT
var world_seed := 0

func update_weather(bounds: Rect2, seconds: float, rain_amount: float,
        wind_direction: Vector2, seed: int) -> void:
    view = bounds
    clock = seconds
    rain = rain_amount
    wind = wind_direction
    world_seed = seed
    queue_redraw()

func _draw() -> void:
    if rain < 0.03 or view.size.x <= 1.0 or view.size.y <= 1.0:
        return
    var count := mini(110, ceili(rain * 105.0))
    var velocity := 58.0 + 46.0 * rain
    var slant := wind.x * (2.0 + 5.0 * rain)
    var color := Color(0.76, 0.87, 0.94, 0.11 + rain * 0.13)
    for i in range(count):
        var h := posmod(i * 1103515245 + world_seed * 97, 2147483647)
        var x := view.position.x + fposmod(float(posmod(h, 10007)) * 0.137 +
                clock * slant * 3.0, view.size.x)
        var y := view.position.y + fposmod(float(posmod(floori(float(h) / 97.0), 10009)) * 0.111 +
                clock * velocity * (0.8 + float(i % 5) * 0.08), view.size.y)
        var start := Vector2(roundf(x), roundf(y))
        draw_line(start, start + Vector2(slant, 5.0 + rain * 5.0), color, 1.0, false)
