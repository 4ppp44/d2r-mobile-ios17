#!/usr/bin/env python3
"""Native opaque PNG icons for the unsigned direct-install build, not App Store.
Apple CFBundleIconFiles: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleicons/cfbundleprimaryicon/cfbundleiconfiles
The upstream catalog and all game resources/sources remain unchanged.
"""
from pathlib import Path
import subprocess,struct,json,sys,re,hashlib

def png_icons(source, destination):
    source=Path(source);destination=Path(destination);destination.mkdir(parents=True,exist_ok=True)
    variants=[]
    for point in [20,29,40,60]:
        for scale in [2,3]:variants.append((f'AppIcon{point}x{point}@{scale}x.png',point*scale))
    for point in [20,29,40,76]:
        for scale in [1,2]:variants.append((f'AppIcon{point}x{point}'+(f'@{scale}x' if scale>1 else '')+'~ipad.png',point*scale))
    variants.append(('AppIcon83.5x83.5@2x~ipad.png',167));records=[]
    for name,size in variants:
        p=destination/name
        subprocess.run(['sips','-z',str(size),str(size),str(source),'--out',str(p)],check=True,stdout=subprocess.DEVNULL)
        b=p.read_bytes();assert b[:8]==b'\x89PNG\r\n\x1a\n';w,h=struct.unpack('>II',b[16:24]);assert (w,h)==(size,size);assert b[25] in (0,2),'Icons must be opaque PNG'
        records.append(dict(file=name,width=w,height=h,opaque=True,sha256=hashlib.sha256(b).hexdigest()))
    (destination.parent/'png-icons-verification.json').write_text(json.dumps(records,indent=2));return records

def project(src,dst,source,out):
    records=png_icons(source,out);text=Path(src).read_text();needle=next(l for l in text.splitlines(True) if l.startswith('      - Assets.xcassets'))
    text=text.replace(needle,''.join('      - '+str(Path(out)/r['file'])+'\n' for r in records),1)
    text,n=re.subn(r'^      ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon[^\n]*\n','',text,count=1,flags=re.M);assert n==1
    needle='        CFBundleDisplayName: D2R Mobile\n';assert text.count(needle)==1;extra=''
    for key,stems in [('CFBundleIcons',['20','29','40','60']),('CFBundleIcons~ipad',['20','29','40','76','83.5'])]:
        extra+='        '+key+':\n          CFBundlePrimaryIcon:\n            UIPrerenderedIcon: false\n            CFBundleIconFiles:\n'
        extra+=''.join('              - AppIcon'+s+'x'+s+'\n' for s in stems)
    Path(dst).write_text(text.replace(needle,needle+extra))

if __name__=='__main__':
    assert len(sys.argv)==5,'usage: ios17_png_icons.py input.yml output.yml source.png Gen/AppIcons'
    project(*sys.argv[1:])
