"""Author the original procedural avatar catalogue; stable IDs are save contracts."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
groups = [
    ('body', '身形', ['body_type']),
    ('skin', '肤色', ['skin']), ('hair', '发型', ['hair_style', 'hair_color', 'fringe', 'hair_accessory']),
    ('eyes', '神态', ['eyes', 'eye_color', 'brows']),
    ('face', '面庞', ['nose', 'mouth', 'blush', 'beard', 'beard_color']),
    ('top', '上装', ['top', 'top_color']), ('bottom', '下装', ['bottom', 'bottom_color']),
    ('shoes', '鞋履', ['shoes', 'shoe_color']), ('extras', '随身', ['hat', 'hat_color', 'glasses']),
]
slots = []

def add(key, label, values, default=None):
    options = []
    for value in values:
        row = dict(zip(['id', 'label', 'color'], value))
        options.append(row)
    slots.append(dict(id=key, label=label, default=default or options[0]['id'], options=options))

add('skin', '海风与日光的肤色', [('porcelain','白瓷','#fce4cf'),('peach','暖杏','#f2c6a2'),('honey','浅麦','#dca474'),('tan','海盐琥珀','#b87f58'),('umber','深焙可可','#865740'),('deep','礁石深棕','#563b32')], 'peach')
add('body_type', '身形比例', [('balanced','匀称'),('pear','松弛梨形'),('athletic','挺拔健朗'),('soft','温润柔和')])
add('hair_style', '发型款式', [('crop','清爽利落短发'),('side','海风侧分'),('bob','内扣波波'),('wave','微卷中发'),('bun','随性丸子头'),('twin','双丸发髻'),('ponytail','轻快马尾'),('high_ponytail','高束马尾'),('low_ponytail','低束马尾'),('long','垂肩长发'),('curly','蓬松自然卷'),('braid','编织麻花辫'),('undercut','干净利落铲青'),('pixie','精灵碎发')], 'bob')
hair = [('chestnut','焦糖栗棕','#5e3e2e'),('black','乌木墨黑','#2c2930'),('cocoa','暖焙可可','#84593f'),('gold','日晒麦金','#cfa95c'),('silver','海雾银灰','#b9bcb6'),('rose','落日灰粉','#c27c87'),('ocean','深海石青','#547c96'),('mint','海苔灰绿','#7ea388')]
add('hair_color','发色',hair)
add('fringe','额前刘海',[('auto','随发型自然垂落'),('side','斜分微扫'),('straight','整齐平刘海'),('open','清爽露额')])
add('hair_accessory','发间点缀',[('none','无点缀'),('ribbon','布艺发结'),('band','编织发带')])
add('eyes','眼型与目光',[('round','澄澈圆眼'),('oval','温和椭圆'),('sleepy','慵懒微垂'),('smile','弯月笑眼'),('almond','修长杏眼'),('wide','好奇睁大'),('soft','柔和目光'),('cat','微挑猫眼'),('sparkle','神采奕奕'),('dot','质朴豆眼'),('lidded','沉静半敛'),('bright','清亮有神')])
add('eye_color','瞳色',[('brown','琥珀栗','#5b3f2f'),('black','深邃墨','#2d2a34'),('blue','远海蓝','#4c7e94'),('green','海藻绿','#667e52'),('amber','落日金','#ad8342'),('violet','暮色紫','#85719a')])
add('brows','眉形',[('soft','自然柔和'),('straight','平直干净'),('arch','舒展微挑')])
add('nose','鼻型',[('button','圆润短鼻'),('oval','立体椭圆'),('tiny','秀气微翘')])
add('mouth','唇形与神情',[('smile','浅浅微笑'),('wide','舒展笑意'),('calm','沉静抿唇'),('oh','轻叹微张'),('open','朗声开怀'),('grin','爽朗露齿'),('frown','若有所思'),('smirk','嘴角微扬'),('cat','轻巧弧线'),('joy','欣喜雀跃'),('laugh','畅快大笑'),('pout','微微嘟起'),('fang','单侧虎牙'),('tongue','轻松吐舌'),('kiss','吹海风哨'),('zigzag','略显局促')])
add('blush','面颊气色',[('peach','海风微醺'),('freckles','日晒雀斑'),('none','干净素颜')])
add('beard','胡须造型',[('none','清爽无须'),('stubble','浅浅青茬'),('moustache','复古八字须'),('goatee','修剪山羊胡'),('full','浓密络腮胡')])
add('beard_color','胡须颜色',hair)
add('top','上装款式',[('tee','纯棉圆领衫'),('stripe','海魂条纹衫'),('sailor','远航水手衫'),('vest','工装衬衫马甲')], 'stripe')
palette = [('seafoam','海沫青绿','#5ba08f'),('sunset','陶土暖橙','#dc8d56'),('cream','帆布米白','#f2e2b6'),('blue','海湾雾蓝','#6b98b8'),('rose','晚霞灰粉','#cf858e'),('lilac','暮云灰紫','#9f90b8'),('navy','深海藏青','#3d5a6c'),('sage','海岛鼠尾草','#8fa174'),('plum','礁石烟紫','#5d5466')]
add('top_color','上装配色',palette)
add('bottom','下装款式',[('shorts','挽边工装短裤'),('trousers','直筒休闲长裤')])
add('bottom_color','下装配色',palette,'navy')
add('shoes','鞋履款式',[('sneakers','胶底帆布鞋'),('boots','防水工装短靴'),('dress','复古搭扣皮鞋')])
add('shoe_color','鞋履配色',palette,'cream')
add('hat','帽饰',[('none','不戴帽子'),('bucket','海岛遮阳渔夫帽'),('beanie','水手针织冷帽'),('fedora','旅人窄檐礼帽')])
add('hat_color','帽饰配色',palette,'sunset')
add('glasses','眼镜',[('none','不戴眼镜'),('round','复古圆框镜'),('square','文艺方圆镜')])

target = ROOT / 'godot/assets/data/avatar_catalog.json'
morphs = [
    ('body_build','身形丰满度','body','清瘦','敦实'), ('head_size','头部比例','body','精巧','饱满'),
    ('head_width','面颊宽窄','body','收拢','舒展'),
    ('arm_girth','手臂围度','body','修长','厚实'),
    ('leg_length','腰线与腿长','body','低腰短腿','高腰修长'),
    ('eye_spacing','眼距宽窄','eyes','聚拢','舒展'),
    ('hair_length','发梢长度','hair','利落','垂坠'),
    ('hair_volume','发丝蓬松度','hair','服帖','蓬松'),
    ('hair_sweep','发流偏分','hair','左偏','右偏'),
]
target.write_text(json.dumps(dict(version=1, groups=[dict(id=i,label=l,slots=s) for i,l,s in groups], slots=slots,
    morphs=[dict(id=i,label=l,group=g,min=0,max=1,default=0.5,low_label=a,high_label=b) for i,l,g,a,b in morphs]), ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
print(target)
