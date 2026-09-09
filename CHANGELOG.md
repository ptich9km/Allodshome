# Changelog

Все изменения проекта Allods Home (Godot версия) документируются здесь.

Формат основан на [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Изометрическая карта 17x17 (травяной остров со стенами)
- Персонаж (воин) с click-to-move и click-to-attack
- 3 врага: 2 орка + 1 слизень с AI (idle/chase/attack/flee)
- 3 заклинания: Fireball (1), Heal (2), Lightning (3)
- HP/Mana бары игрока
- HP бары врагов
- Тактическая пауза (пробел)
- UI панель заклинаний
- TileSet с изометрическими тайлами (трава, стена)

### Changed
- Миграция с Unity C# на Godot 4 GDScript
- Упрощённая архитектура: ~300 строк кода вместо 600+

### Fixed
- Пути к тайлам в main.tscn (спрайты → tiles)
- Ошибки парсинга .tscn файлов (SubResource синтаксис)
- Переименование `owner` → `projectile_owner` (конфликт с Node2D)

---
