@tool
extends RefCounted
## 首批真实树种的形态约束；只保存文字事实，不携带第三方素材。

static func definitions() -> Dictionary:
	return {
		"camphor": {
			"name": "香樟",
			"latin": "Cinnamomum camphora",
			"description": "常绿宽圆冠，主枝舒展，互生椭圆全缘叶，树干与枝条在冠内可见；参数为幼树景观与夸张叶片尺度，并非生理模拟。",
			"leaf_shape": "oval", "phyllotaxis": "alternate",
			"leaf_subdivisions": 2, "leaf_tip": 1.0, "leaf_cup": 0.75,
			"crown_form": "broad_round", "twig_droop": 0.12,
			"leaf_width_ratio": 0.42, "leaf_length_ratio": 1.45,
			"sources": [
				"https://plants.ces.ncsu.edu/plants/cinnamomum-camphora/",
				"docs/features/plant_editor/spec.md"
			]
		},
		"maple": {
			"name": "鸡爪槭",
			"latin": "Acer palmatum",
			"description": "层状舒展冠，枝条横向展开，对生掌裂叶，叶簇轻薄而有空隙；参数为幼树景观与夸张叶片尺度，并非生理模拟。",
			"leaf_shape": "palmate", "phyllotaxis": "opposite",
			"leaf_subdivisions": 2, "leaf_tip": 1.28, "leaf_cup": 0.48,
			"crown_form": "layered_spreading", "twig_droop": 0.18,
			"leaf_width_ratio": 0.80, "leaf_length_ratio": 1.05,
			"sources": [
				"https://plants.ces.ncsu.edu/plants/acer-palmatum/",
				"docs/features/plant_editor/spec.md"
			]
		},
		"birch": {
			"name": "垂枝桦",
			"latin": "Betula pendula",
			"description": "直立主干与上扬主枝，细枝末端下垂，互生三角锯齿叶；参数为幼树景观与夸张叶片尺度，并非生理模拟。",
			"leaf_shape": "triangular", "phyllotaxis": "alternate",
			"leaf_subdivisions": 2, "leaf_tip": 1.0, "leaf_cup": 1.0,
			"crown_form": "upright_pendulous", "twig_droop": 0.90,
			"leaf_width_ratio": 0.58, "leaf_length_ratio": 1.15,
			"sources": [
				"https://plants.ces.ncsu.edu/plants/betula-pendula/",
				"docs/features/plant_editor/spec.md"
			]
		}
	}
