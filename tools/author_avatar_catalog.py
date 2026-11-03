"""Author the original procedural avatar catalogue; stable IDs are save contracts."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
groups = [
    ('body', '体型', ['body_type']),
    ('skin', '肤色', ['skin']), ('hair', '头发', ['hair_style', 'hair_color', 'fringe', 'hair_accessory']),
    ('eyes', '眼睛', ['eyes', 'eye_color', 'brows']),
    ('face', '五官', ['nose', 'mouth', 'blush', 'beard', 'beard_color']),
    ('top', '上装', ['top', 'top_color']), ('bottom', '下装', ['bottom', 'bottom_color']),
    ('shoes', '鞋子', ['shoes', 'shoe_color']), ('extras', '配饰', ['hat', 'hat_color', 'glasses']),
]
slots = []

def add(key, label, values, default=None):
    options = []
    for value in values:
        row = dict(zip(['id', 'label', 'color'], value))
        options.append(row)
    slots.append(dict(id=key, label=label, default=default or options[0]['id'], options=options))

add('skin', '海风亲吻的肤色', [('porcelain','瓷白','#ffe5d0'),('peach','蜜桃','#f5cbaa'),('honey','蜜糖','#dfaa7b'),('tan','小麦','#bb825c'),('umber','可可','#895a43'),('deep','深棕','#593d34')], 'peach')
add('body_type', '身体的轮廓', [('balanced','匀称'),('pear','梨形'),('athletic','健朗'),('soft','柔和')])
add('hair_style', '选一个喜欢的发型', [('crop','清爽短发'),('side','侧分短发'),('bob','圆圆波波头'),('wave','柔软卷发'),('bun','高高丸子头'),('twin','双团子'),('ponytail','轻盈马尾'),('high_ponytail','高马尾'),('low_ponytail','低马尾'),('long','披肩长发'),('curly','蓬松卷发'),('braid','麻花辫'),('undercut','两侧清爽'),('pixie','精灵短发')], 'bob')
hair = [('chestnut','栗棕','#664432'),('black','墨黑','#302d35'),('cocoa','可可','#8d6145'),('gold','麦金','#d9b565'),('silver','银灰','#c4c5c0'),('rose','莓粉','#ca8490'),('ocean','海蓝','#648eab'),('mint','薄荷','#91b59a')]
add('hair_color','头发的颜色',hair)
add('fringe','刘海',[('auto','随发型'),('side','侧扫刘海'),('straight','齐刘海'),('open','露额头')])
add('hair_accessory','发饰',[('none','不加发饰'),('ribbon','小蝴蝶结'),('band','发带')])
add('eyes','眼睛的形状',[('round','圆亮眼'),('oval','椭圆眼'),('sleepy','悠闲眼'),('smile','笑眯眯'),('almond','细杏眼'),('wide','惊喜眼'),('soft','温柔眼'),('cat','猫咪眼'),('sparkle','粗线亮眼'),('dot','豆豆眼'),('lidded','半睁眼'),('bright','明亮眼')])
add('eye_color','眼睛的颜色',[('brown','栗子','#654634'),('black','深墨','#33303b'),('blue','湖蓝','#548aa0'),('green','苔绿','#71895a'),('amber','琥珀','#b78d4a'),('violet','紫藤','#927da8')])
add('brows','眉毛',[('soft','柔和'),('straight','平直'),('arch','弯弯')])
add('nose','鼻子',[('button','小圆鼻'),('oval','椭圆鼻'),('tiny','小巧鼻')])
add('mouth','嘴巴',[('smile','弯弯微笑'),('wide','大大微笑'),('calm','平静横线'),('oh','惊讶圆嘴'),('open','开怀笑'),('grin','露齿笑'),('frown','小烦恼'),('smirk','俏皮歪笑'),('cat','弯弯W嘴'),('joy','欢呼'),('laugh','哈哈笑'),('pout','抿嘴'),('fang','小虎牙'),('tongue','吐舌'),('kiss','嘟嘟嘴'),('zigzag','紧张波浪')])
add('blush','脸颊',[('peach','蜜桃腮红'),('freckles','小雀斑'),('none','清清爽爽')])
add('beard','胡子',[('none','清爽无胡'),('stubble','淡淡胡茬'),('moustache','小八字胡'),('goatee','山羊胡'),('full','环脸胡')])
add('beard_color','胡子的颜色',hair)
add('top','上装款式',[('tee','日常短袖'),('stripe','海风条纹'),('sailor','水手领'),('vest','衬衫马甲')], 'stripe')
palette = [('seafoam','海沫绿','#72b8a6'),('sunset','落日橙','#e6a068'),('cream','奶油白','#f5e5ba'),('blue','晴空蓝','#7daaca'),('rose','珊瑚粉','#d9929b'),('lilac','丁香紫','#afa0c6'),('navy','海军蓝','#486879'),('sage','鼠尾草','#9eae81'),('plum','烟紫','#635b6d')]
add('top_color','上装的颜色',palette)
add('bottom','下装款式',[('shorts','轻便短裤'),('trousers','休闲长裤')])
add('bottom_color','下装的颜色',palette,'navy')
add('shoes','鞋子款式',[('sneakers','帆布鞋'),('boots','软软短靴'),('dress','小皮鞋')])
add('shoe_color','鞋子的颜色',palette,'cream')
add('hat','帽子',[('none','不戴帽子'),('bucket','渔夫帽'),('beanie','针织帽'),('fedora','窄边礼帽')])
add('hat_color','帽子的颜色',palette,'sunset')
add('glasses','眼镜',[('none','不戴眼镜'),('round','圆框眼镜'),('square','方圆眼镜')])

target = ROOT / 'godot/assets/data/avatar_catalog.json'
morphs = [
    ('body_build','胖瘦','body','纤细','圆润'), ('head_size','头部大小','body','小巧','饱满'),
    ('head_width','头部横向比例','body','收窄','展开'),
    ('arm_girth','手臂粗细','body','纤细','饱满'),
    ('leg_length','腿长与胯位','body','短腿低胯','修长高胯'),
    ('eye_spacing','眼睛距离','eyes','靠近','分开'),
    ('hair_length','头发长度','hair','短一些','长一些'),
    ('hair_volume','头发蓬松度','hair','服帖','蓬松'),
    ('hair_sweep','发丝方向','hair','向左','向右'),
]
target.write_text(json.dumps(dict(version=1, groups=[dict(id=i,label=l,slots=s) for i,l,s in groups], slots=slots,
    morphs=[dict(id=i,label=l,group=g,min=0,max=1,default=0.5,low_label=a,high_label=b) for i,l,g,a,b in morphs]), ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
print(target)
