#!/usr/bin/env python3
"""仅用本地 Pillow 处理已授权的四块苔藓图集，不调用生成服务或 Godot。"""
from collections import defaultdict, deque
from hashlib import md5, sha256
import argparse
from pathlib import Path
import ast
import json
import statistics

from PIL import Image, ImageDraw, ImageFilter, PngImagePlugin

ROOT = Path('/Users/zyq/work/sea')
SOURCE = ROOT / 'art_source/surface_paint/v001/Production_game_texture_atlas__2026-11-17T23-36-25.png'
OUT = SOURCE.parent / '处理记录'
RUNTIME = ROOT / 'godot/assets/textures/vegetation/surface_moss_atlas_512.png'
REGIONS = [(0, 0, 512, 450), (512, 0, 1024, 450),
           (0, 450, 512, 1024), (512, 450, 1024, 1024)]
# 右下白色文字与植物有效轮廓不相交；采用半开像素边界。
EXCLUDED = (864, 944, 1024, 1024)
NAMES = ['round_moss', 'radial_moss', 'hanging_moss', 'moss_ivy']
PARAMS = dict(chroma_background_max=10, chroma_seed_min=45,
              seed_erode_size=5, donor_radius_source_px=20,
              alpha_cutoff=0.06, source_crop_padding_px=8,
              cell_size=256, content_limit=224, rgb_dilation_px=8,
              checker_period_px=32, excluded_source_rect=list(EXCLUDED))


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def save_json(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def dilate_rgb(image, radius):
    """仅扩展零 alpha 像素的 RGB，不扩张有效轮廓，也不跨图集格子。"""
    pixels = list(image.get_flattened_data())
    w, h = image.size
    distance = [-1] * (w * h)
    queue = deque()
    for i, pixel in enumerate(pixels):
        if pixel[3]:
            distance[i] = 0
            queue.append(i)
    while queue:
        i = queue.popleft()
        if distance[i] >= radius:
            continue
        x, y = i % w, i // w
        for xx, yy in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
            if 0 <= xx < w and 0 <= yy < h:
                j = yy * w + xx
                if distance[j] == -1:
                    distance[j] = distance[i] + 1
                    pixels[j] = (*pixels[i][:3], pixels[j][3])
                    queue.append(j)
    result = Image.new('RGBA', image.size)
    result.putdata(pixels)
    return result


def premult_resize(image, size):
    # RGBa 为 Pillow 预乘模式；重采样后恢复标准直通 alpha RGBA PNG。
    result = image.convert('RGBa').resize(size, Image.Resampling.LANCZOS).convert('RGBA')
    values = list(result.get_flattened_data())
    width,height = size
    fixed = values.copy()
    for i,(r,g,b,a) in enumerate(values):
        if a and max(r,g,b)-min(r,g,b) < 24:
            x,y = i % width,i // width
            neighbors = [values[yy*width+xx] for yy in range(max(0,y-3),min(height,y+4))
                         for xx in range(max(0,x-3),min(width,x+4))
                         if values[yy*width+xx][3] >= 32 and values[yy*width+xx][1]-values[yy*width+xx][2] >= 30]
            if neighbors:
                donor = max(neighbors,key=lambda p:p[3])
                fixed[i] = (*donor[:3],a)
    result.putdata(fixed)
    return result


def main():
    parser = argparse.ArgumentParser(description='本地四patch贴图处理及静态验收，不启动Godot')
    parser.add_argument('--write-runtime',action='store_true',help='仅静态通过且已目检后写指定运行贴图及import')
    args = parser.parse_args()
    ast.parse(Path(__file__).read_text(encoding='utf-8'))
    original = Image.open(SOURCE)
    assert original.size == (1024, 1024)
    rgb = original.convert('RGB')
    pixels = list(rgb.get_flattened_data())
    w, h = rgb.size
    n = w * h
    chroma = [max(r, g) - b for r, g, b in pixels]
    neutral_phase = defaultdict(list)
    neutral_parity = defaultdict(list)
    for i, (r, g, b) in enumerate(pixels):
        x, y = i % w, i // w
        if min(r, g, b) >= 210 and max(r, g, b) - min(r, g, b) <= 10 and not (x >= 864 and y >= 944):
            neutral_phase[(x % 32, y % 32)].append((r, g, b))
            neutral_parity[((x // 16) + (y // 16)) % 2].append((r+g+b)/3)
    # 以相同32像素棋盘相位的真实中性像素中位数估计背景，不依赖白色亮度阈值抠植物。
    bg = {}
    for key, samples in neutral_phase.items():
        bg[key] = tuple(statistics.median(p[c] for p in samples) for c in range(3))
    assert len(bg) == 1024
    interior_seed = Image.new('L', rgb.size)
    interior_seed.putdata([255 if chroma[i] >= 45 and p[1] >= p[0] else 0 for i,p in enumerate(pixels)])
    trusted = interior_seed.filter(ImageFilter.MinFilter(5))
    trusted_values = list(trusted.get_flattened_data())
    owner = [-1] * n
    distances = [-1] * n
    queue = deque()
    for i, value in enumerate(trusted_values):
        if value:
            owner[i] = i
            distances[i] = 0
            queue.append(i)
    while queue:
        i = queue.popleft()
        if distances[i] >= 20:
            continue
        x, y = i % w, i // w
        for xx, yy in ((x-1,y), (x+1,y), (x,y-1), (x,y+1),
                       (x-1,y-1), (x+1,y-1), (x-1,y+1), (x+1,y+1)):
            if 0 <= xx < w and 0 <= yy < h:
                j = yy*w+xx
                if owner[j] == -1:
                    owner[j], distances[j] = owner[i], distances[i]+1
                    queue.append(j)
    cleaned_pixels = []
    edge_recovered = 0
    for i, observed in enumerate(pixels):
        x, y = i % w, i // w
        if x >= EXCLUDED[0] and y >= EXCLUDED[1]:
            cleaned_pixels.append((0,0,0,0))
        elif trusted_values[i] or (chroma[i] >= 26 and max(observed) < 210):
            cleaned_pixels.append((*observed,255))
        elif chroma[i] <= 10 or observed[1] < observed[0] - 2:
            cleaned_pixels.append((0,0,0,0))
        else:
            # 极细叶尖可没有腐蚀后的内部种子：保留有色像素，不因亮度删除浅苔藓。
            donor = pixels[owner[i]] if owner[i] >= 0 else observed
            background = bg[(x % 32, y % 32)]
            background_chroma = max(background[0],background[1])-background[2]
            donor_chroma = max(donor[0],donor[1])-donor[2]
            alpha = min(1.0, max(0.0, (chroma[i]-background_chroma)/max(donor_chroma-background_chroma,1)))
            if alpha < 0.06:
                cleaned_pixels.append((0,0,0,0))
            else:
                color = tuple(round(min(255,max(0,(observed[c]-(1-alpha)*background[c])/alpha))) for c in range(3))
                # 低覆盖率边缘用邻近可信植物RGB，避免反解噪声放大为白/灰边；不改变alpha轮廓。
                if alpha < 0.9 or max(color)-min(color) < 24:
                    color = donor
                cleaned_pixels.append((*color,round(alpha*255)))
                edge_recovered += 1
    cleaned = Image.new('RGBA', rgb.size)
    cleaned.putdata(cleaned_pixels)
    cleaned.getchannel('A').save(OUT / 'source_alpha_mask.png')
    cleaned.save(OUT / 'source_cleaned_rgba.png')
    atlas = Image.new('RGBA', (512,512))
    crop_report = []
    source_annotated = rgb.copy()
    draw = ImageDraw.Draw(source_annotated)
    draw.rectangle((864,944,1023,1023), outline='#ff3030', width=3)
    draw.line((0,450,1023,450), fill='#ff3030', width=2)
    draw.line((512,0,512,1023), fill='#ff3030', width=2)
    for index, region in enumerate(REGIONS):
        patch = cleaned.crop(region)
        bbox = patch.getchannel('A').getbbox()
        assert bbox is not None
        x0,y0,x1,y1 = region
        global_bbox = [bbox[0]+x0,bbox[1]+y0,bbox[2]+x0,bbox[3]+y0]
        draw.rectangle((global_bbox[0],global_bbox[1],global_bbox[2]-1,global_bbox[3]-1), outline='#ff5d00', width=2)
        patch = patch.crop((bbox[0]-8,bbox[1]-8,bbox[2]+8,bbox[3]+8))
        scale = min(224 / patch.width, 224 / patch.height)
        scaled_size = (max(1,round(patch.width*scale)), max(1,round(patch.height*scale)))
        patch = premult_resize(patch,scaled_size)
        cell = Image.new('RGBA',(256,256))
        position = ((256-patch.width)//2,(256-patch.height)//2)
        cell.paste(patch,position)
        cell = dilate_rgb(cell,8)
        atlas.paste(cell,((index%2)*256,(index//2)*256))
        crop_report.append(dict(id=NAMES[index],index=index,source_region=list(region),
                                source_effective_bbox=global_bbox,source_crop_padding_px=8,
                                scaled_size=list(scaled_size),cell_content_bbox=list(cell.getchannel('A').getbbox()),
                                cell_origin=[(index%2)*256,(index//2)*256],
                                uv_rect=[(index%2)*0.5,(index//2)*0.5,0.5,0.5]))
    source_annotated.save(OUT / 'source_boundaries.png')
    png_info = PngImagePlugin.PngInfo()
    png_info.add_text('Origin','AI-generated RGB source; locally processed, not a new generation')
    png_info.add_text('ReleaseStatus','PENDING provenance and license review; Godot not executed')
    atlas.save(OUT / 'surface_moss_atlas_512_candidate.png',pnginfo=png_info)
    # 输出两个极端底色和小尺寸预览，揭示白边及细枝损失。
    preview = Image.new('RGB',(1024,768),'#343b47')
    for x,color in ((0,'#19242b'),(512,'#f6efda')):
        background = Image.new('RGBA',atlas.size,color)
        preview.paste(Image.alpha_composite(background,atlas).convert('RGB'),(x,0))
        for level,size in enumerate((256,128,64)):
            small = premult_resize(atlas,(size,size))
            tile = Image.new('RGBA',(size,size),color)
            tile.alpha_composite(small)
            preview.paste(tile.convert('RGB'),(x+(0,272,416)[level],512))
    preview.save(OUT / 'atlas_visual_report.png')
    checks = dict(source_is_rgb_without_alpha=original.mode=='RGB',output_mode=atlas.mode,
                  output_size=list(atlas.size),strict_2x2=len(crop_report)==4,
                  neutral_visible_pixels=sum(1 for r,g,b,a in atlas.get_flattened_data() if a>=32 and max(r,g,b)-min(r,g,b)<=10),
                  excluded_rect_alpha_max=cleaned.crop(EXCLUDED).getchannel('A').getextrema()[1],
                  trusted_pixels_changed=sum(1 for i,v in enumerate(trusted_values) if v and cleaned_pixels[i] != (*pixels[i],255)),
                  colorful_seed_pixels_lost=sum(1 for i,p in enumerate(pixels) if chroma[i]>=26 and p[1]>=p[0] and cleaned_pixels[i][3]==0),
                  edge_recovered_pixels=edge_recovered,alpha_extrema=list(atlas.getchannel('A').getextrema()),
                  partial_alpha_pixels=sum(1 for *_,a in atlas.get_flattened_data() if 0<a<255),
                  safe_cell_margin_px=min(min(p['cell_content_bbox'][0],p['cell_content_bbox'][1],256-p['cell_content_bbox'][2],256-p['cell_content_bbox'][3]) for p in crop_report),
                  godot_executed=False)
    checks['static_pass'] = all((atlas.mode=='RGBA',atlas.size==(512,512),checks['neutral_visible_pixels']==0,
                                 checks['excluded_rect_alpha_max']==0,checks['trusted_pixels_changed']==0,
                                 checks['colorful_seed_pixels_lost']==0,checks['safe_cell_margin_px']>=16))
    runtime_written = False
    import_hash = None
    if args.write_runtime:
        assert checks['static_pass'], '静态检查未通过，不写生产路径'
        candidate = OUT / 'surface_moss_atlas_512_candidate.png'
        if RUNTIME.exists() and RUNTIME.read_bytes() != candidate.read_bytes():
            raise RuntimeError('运行贴图已存在且内容不同，停止以避免覆盖其他线程修改')
        source_res = 'res://assets/textures/vegetation/surface_moss_atlas_512.png'
        imported = f'res://.godot/imported/{RUNTIME.name}-{md5(source_res.encode()).hexdigest()}.bptc.ctex'
        config = ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
                  f'path.bptc="{imported}"\nmetadata={{\n"imported_formats": ["s3tc_bptc"],\n"vram_texture": true\n}}\n\n'
                  f'[deps]\n\nsource_file="{source_res}"\ndest_files=["{imported}"]\n\n[params]\n\n'
                  'compress/mode=2\ncompress/high_quality=true\ncompress/lossy_quality=0.7\n'
                  'compress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n'
                  'compress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n'
                  'roughness/mode=0\nroughness/src_normal=""\nprocess/channel_remap/red=0\n'
                  'process/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n'
                  'process/fix_alpha_border=true\nprocess/premult_alpha=false\n'
                  'process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n'
                  'process/hdr_clamp_exposure=false\nprocess/size_limit=512\ndetect_3d/compress_to=0\n')
        import_file = Path(str(RUNTIME)+'.import')
        if import_file.exists() and import_file.read_text(encoding='utf-8') != config:
            raise RuntimeError('import已存在且配置不同，停止以避免覆盖其他线程修改')
        RUNTIME.write_bytes(candidate.read_bytes())
        import_file.write_text(config,encoding='utf-8')
        import_hash = digest(import_file)
        runtime_written = True
    checks['import_configuration_written'] = runtime_written
    checks['vram_compression_executed'] = False
    save_json('static_image_checks.json',checks)
    save_json('patch_layout.json',crop_report)
    save_json('source_manifest.json',dict(
        status=('STATIC_PROCESSED_RUNTIME_PENDING_RELEASE' if runtime_written else 'STATIC_CANDIDATE_PENDING_VISUAL_REVIEW') if checks['static_pass'] else 'SOURCE_NOT_DIRECTLY_USABLE',
        source_path=str(SOURCE),source_sha256=digest(SOURCE),source_mode=original.mode,source_size=list(original.size),
        source_contains_baked_checker=True,source_direct_runtime_usable=False,
        checker_detection=dict(period_px=32,square_px=16,phase_count=len(bg),
                               neutral_sample_count=sum(len(v) for v in neutral_phase.values()),
                               parity_luma_medians=[statistics.median(neutral_parity[i]) for i in (0,1)]),
        generation_model=None,generation_model_status='unknown_not_embedded_or_supplied',
        generation_output_path=str(SOURCE),original_prompt=None,prompt_hash=None,
        prompt_hash_status='pending_original_prompt_not_available_do_not_invent',
        processing_script=str(Path(__file__).resolve()),processing_hash=digest(Path(__file__)),
        processing_parameters=PARAMS,processing_parameters_sha256=sha256(json.dumps(PARAMS,sort_keys=True).encode()).hexdigest(),
        authorization=dict(local_processing='user_authorized_current_request',asset_license='pending',release='pending'),
        watermark_cleanup=dict(rect_half_open=list(EXCLUDED),method='alpha_zero',intersects_green_seed=False),
        candidate_output_path=str(OUT / 'surface_moss_atlas_512_candidate.png'),
        candidate_sha256=digest(OUT / 'surface_moss_atlas_512_candidate.png'),
        intended_runtime_path=str(RUNTIME),runtime_written=runtime_written,
        runtime_sha256=digest(RUNTIME) if runtime_written else None,import_sha256=import_hash,godot_executed=False,
        alpha_method='color-difference seed + eroded interior + phase-median background unmatting; premultiplied Lanczos; straight-alpha output',
        limitations=['原始alpha不可逆恢复；边缘alpha为保守估计。','生成模型及原始prompt缺失，来源与授权pending。',
                     '16像素以上格内留白及8像素RGB扩边不保证最深mipmap层无串格，需主线程shader按格钳制或限制LOD。',
                     '尚未运行Godot，未验证VRAM实际压缩、材质采样或引擎渲染。']))
    print(json.dumps(checks,ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
