#!/usr/bin/env python3
"""Exercise real native packet copy, tags, cancellation and corrupt input."""
import ctypes
import json
from pathlib import Path
import subprocess
import sys

lib=ctypes.CDLL(sys.argv[1])
root=Path(sys.argv[2]);root.mkdir(parents=True,exist_ok=True)
remux=lib.zero_remux
remux.argtypes=[ctypes.c_char_p]*5+[ctypes.POINTER(ctypes.c_int),ctypes.c_char_p,ctypes.c_size_t]
remux.restype=ctypes.c_int

def run(args):
    return subprocess.check_output(args,stderr=subprocess.PIPE)

def native(source, target, cancelled=False):
    cancel=ctypes.c_int(int(cancelled));error=ctypes.create_string_buffer(256)
    code=remux(str(source).encode(),str(target).encode(), '零拍标题'.encode(), '测试艺人'.encode(), '测试专辑'.encode(),ctypes.byref(cancel),error,len(error))
    return code,error.value.decode()

def probe(path):
    return json.loads(run(['ffprobe','-v','error','-select_streams','a:0','-show_format','-show_streams','-show_packets','-show_data_hash','sha256','-of','json',str(path)]))

for codec,ext in [('aac','m4a'),('libmp3lame','mp3'),('flac','flac'),('libopus','opus')]:
    source=root/f'in.{ext}';target=root/f'out.{ext}'
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','lavfi','-i','sine=frequency=440:duration=0.3','-c:a',codec,str(source)])
    code,error=native(source,target)
    assert code==0,(ext,code,error)
    before,after=probe(source),probe(target)
    tags={k.lower():v for part in [after['format'],*after['streams']] for k,v in part.get('tags',{}).items()}
    assert tags['title']=='零拍标题' and tags['artist']=='测试艺人' and tags['album']=='测试专辑',tags
    assert [p['data_hash'] for p in before['packets']]==[p['data_hash'] for p in after['packets']],ext
    assert native(source,root/f'cancelled.{ext}',True)[0]<0
    print(f'PASS {ext}: tags, identical compressed packets, cancelled remux rejected')
corrupt=root/'broken.m4a';corrupt.write_bytes(b'not audio')
assert native(corrupt,root/'broken-output.m4a')[0]<0
print('PASS corrupt input rejected; host-native execution only, Android device validation remains separate')
