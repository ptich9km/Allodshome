# ============================================================================
# WorldFeed — короткая лента системных и мировых событий для F3-панели.
#
# Задел под будущее общение игроков: тот же post()/tail() будет принимать
# сообщения чата, а панель уже умеет их показывать. Пока живёт в памяти и не
# сохраняется: это диагностика, а не журнал мира.
# ============================================================================
extends RefCounted

const LIMIT := 100

static var _lines: Array = []


static func post(kind: String, text: String) -> void:
	_lines.append({"kind": kind, "text": text, "at": Time.get_ticks_msec()})
	while _lines.size() > LIMIT:
		_lines.pop_front()


static func tail(count: int = 6) -> Array:
	var out: Array = []
	var from := maxi(0, _lines.size() - count)
	for i in range(from, _lines.size()):
		out.append(_lines[i])
	return out


static func clear() -> void:
	_lines.clear()
