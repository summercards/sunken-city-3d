@tool
extends RefCounted
## 首批真实树种的形态约束；只保存文字事实，不携带第三方素材。

static func definitions() -> Dictionary:
	return {
		"camphor": {
			"name": "香樟",
			"latin": "Cinnamomum camphora",
			"description": "常绿宽圆冠，主枝舒展，互生椭圆全缘叶，树干与枝条在冠内可见。",
			"sources": [
				"https://plants.ces.ncsu.edu/plants/cinnamomum-camphora/",
				"docs/features/plant_editor/spec.md"
			]
		},
		"maple": {
			"name": "鸡爪槭",
			"latin": "Acer palmatum",
			"description": "层状舒展冠，枝条横向展开，对生掌裂叶，叶簇轻薄而有空隙。",
			"sources": [
				"https://plants.ces.ncsu.edu/plants/acer-palmatum/",
				"docs/features/plant_editor/spec.md"
			]
		},
		"birch": {
			"name": "垂枝桦",
			"latin": "Betula pendula",
			"description": "直立主干与上扬主枝，细枝末端下垂，互生三角锯齿叶。",
			"sources": [
				"https://plants.ces.ncsu.edu/plants/betula-pendula/",
				"docs/features/plant_editor/spec.md"
			]
		}
	}
