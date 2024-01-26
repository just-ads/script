import subprocess
import os
import shutil
import time
import math
import datetime

path_main = r'G:/raster/tif';

temp_path = r'G:/raster/tif_3857';

rgb_path = r'G:/raster/tif_rgb';

tiles_path = r'G:/raster/raster'

def format_seconds(seconds):
    '''
    将秒数格式化为时:分:秒的形式
    :param seconds: 秒数
    :return: 时:分:秒的字符串
    '''
    time_delta = datetime.timedelta(seconds=math.ceil(seconds))
    return str(time_delta)


def reproject(input_file, output_file):
    '''
    重投影到EPSG:3857
    '''
    input_file = os.path.normpath(input_file)
    output_file = os.path.normpath(output_file)
    file_name = os.path.basename(input_file)
    if os.path.exists(output_file):
        print(f'reproject {file_name} is exists')
        return output_file
    cmd = f'gdalwarp -t_srs EPSG:3857 \
            -dstnodata None \
            -r bilinear \
            -tr 1000.0 1000.0 \
            -te -20037508.3428 -20000000.0 20037491.6572 20000000.0 \
            -te_srs EPSG:3857 \
            -co TILED=YES \
            -co COMPRESS=DEFLATE \
            -co BIGTIFF=IF_NEEDED \
            {input_file} \
            {output_file}'
    print(f'\n重投影开始')
    start_time = time.time()
    subprocess.check_output(cmd, shell=True)
    t = format_seconds(time.time() - start_time)
    print(f"reproject successfully: {output_file}, 耗时: {t}")
    return output_file


def rgbify(src):
    '''
    rgb编码
    '''
    input_file = os.path.normpath(src)
    file_name = os.path.basename(input_file)
    output_file = f'{rgb_path}/{file_name}'
    if os.path.exists(output_file):
        print(f'rgbify {file_name} is exists')
        return output_file
    cmd = f'rio rgbify -b 0 -i 0.01 {input_file} {output_file}'
    print(f'\nrgb编码开始')
    start_time = time.time()
    subprocess.check_output(cmd, shell=True)
    t = format_seconds(time.time() - start_time)
    print(f"rgbified successfully: {output_file}, 耗时: {t}")
    os.remove(input_file)
    return output_file

def gdal2tiles(src, zoom, clean=True):
    input_file = os.path.normpath(src)
    file_name = os.path.basename(input_file)
    output_path = os.path.splitext(file_name)[0].split('-').pop()
    output_path = os.path.join(tiles_path, output_path)
    if clean and os.path.exists(output_path):
        shutil.rmtree(output_path)
    cmd = f"gdal2tiles.py \
          -p mercator \
          --zoom={zoom} \
          --resampling=near \
          --tilesize=512 \
          --processes=4 \
          --xyz \
          --webviewer=none \
          -n {input_file} \
          {output_path}"
    try:
        print(f'\n{file_name}开始切片')
        start_time = time.time()
        subprocess.check_output(cmd, shell=True)
    except subprocess.CalledProcessError as e:
        if e.returncode != 120:
            print(e)
    t = format_seconds(time.time() - start_time)    
    print(f"created tileset successfully: {output_path}, 耗时: {t}")


def start(zoom = '0-5'):
    if not os.path.exists(path_main):
        return
    if not os.path.exists(temp_path):
        os.makedirs(temp_path)
    if not os.path.exists(rgb_path):
        os.makedirs(rgb_path)
    if not os.path.exists(tiles_path):
        os.makedirs(tiles_path)
    for filename in os.listdir(path_main):
        file = os.path.join(path_main, filename)
        # rgb编码文件
        rgbtif = os.path.join(rgb_path, filename)
        if not os.path.exists(rgbtif):
            # 重投影
            retif = os.path.join(temp_path, filename)
            retif = reproject(file, retif)

            # rgb编码
            rgbtif = rgbify(retif)

        # 切片    
        gdal2tiles(rgbtif, zoom)


if __name__ == '__main__':
    # reproject('./tif/landscan-global-2000.tif', './tif_3857/landscan-global-2000.tif')
    # rgbtif = rgbify('./tif_3857/landscan-global-2000.tif')
    # gdal2tiles(rgbtif, '0-5')
    start('8-9')
    # gdal2tiles('G:/raster/tif_rgb/landscan-global-2022.tif', '0-5')



    
    
