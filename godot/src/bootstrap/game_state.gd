extends Node
## 玩家 / 船只的全局状态。
##
## 与网页版一致：船是位移主体，人只有「在船上 / 在岸上」两种待机位置；
## 区块切换由船只到站触发，而不是瞬移相机。

signal zone_changed(zone_id: String)
signal mode_changed(mode: int)

enum Mode { ASHORE, ON_BOAT, SAILING, DIVING }

var mode: int = Mode.ON_BOAT
var current_zone: String = "zone1"
var landing_id: String = "main"
var far_sea_unlocked: bool = false
var dive_depth: float = 0.0


func set_mode(next: int) -> void:
	if mode == next:
		return
	mode = next
	mode_changed.emit(mode)


func enter_zone(zone_id: String) -> void:
	if zone_id == current_zone:
		return
	current_zone = zone_id
	zone_changed.emit(zone_id)
