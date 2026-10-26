#!/usr/bin/env python3
"""Render M8 contact sheets and verify already-exported GIFs (requires Pillow).

Never builds or edits product art. Contact sheets use labeled nearest-neighbor
samples; visual acceptance is separate from file decoding and checksums.
"""
import argparse
import hashlib
import io
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--gifs', type=Path)
    parser.add_argument('--contract', type=Path, default=ROOT/'scripts/m8-art-contract.json')
    parser.add_argument('--batch-prefix', choices=['M8','E','all'], default='M8')
    args = parser.parse_args()
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    contract = json.loads(args.contract.read_text())
    manifest = json.loads((ROOT/'shared/art/manifest.json').read_text())
    baseline = contract['baselineCommit']
    old = json.loads(subprocess.check_output(['git','show',f'{baseline}:shared/art/manifest.json'],cwd=ROOT))
    font = ImageFont.load_default(size=12)
    rows = []
    for batch, spec in contract['batches'].items():
        if args.batch_prefix != 'all' and not batch.startswith(args.batch_prefix):
            continue
        ids = list(spec['signatures'])
        cell, row_height = 156, 174
        sheet = Image.new('RGBA',(cell*9,row_height*len(ids)),(243,239,227,255))
        draw = ImageDraw.Draw(sheet)
        for row, sid in enumerate(ids):
            names = manifest.get('speciesFrames',{}).get(sid,manifest['frames'])
            size = manifest['frameSizes'][sid]
            atlas = Image.open(ROOT/f'shared/art/{sid}.png').convert('RGBA')
            before = Image.open(io.BytesIO(subprocess.check_output(['git','show',f'{baseline}:shared/art/{sid}.png'],cwd=ROOT))).convert('RGBA')
            old_names = old.get('speciesFrames',{}).get(sid,old['frames'])
            draw.text((8,row*row_height+4),sid,fill=(35,38,40,255),font=font)
            selected=['stand','idle0','lookNear']+spec['signatures'][sid]+['restTuck','takeoffPush']
            for col, frame in enumerate(selected):
                source = before if col<2 else atlas
                source_names = old_names if col<2 else names
                index = source_names.index(frame)
                columns=source.width//size
                x,y=(index%columns)*size,(index//columns)*size
                tile = source.crop((x,y,x+size,y+size)).resize((112,112),Image.Resampling.NEAREST)
                origin=(col*cell+22,row*row_height+23)
                line_y=origin[1]+39*112/48
                draw.line((col*cell+8,line_y,(col+1)*cell-8,line_y),fill=(175,173,160,255))
                sheet.alpha_composite(tile,origin)
                draw.text((col*cell+5,row*row_height+144),('old ' if col<2 else '')+frame,fill=(35,38,40,255),font=font)
        path=out/f'{batch.lower()}-contact.png'
        sheet.convert('RGB').save(path)
        rows.append({'batch':batch,'species':ids,'file':path.name,'sha256':digest(path)})
    report={'baseline':baseline,'contactSheets':rows,'visualReviewRequired':True}
    if args.gifs:
        directory=args.gifs.resolve()
        gif_rows=[]
        expected={f'{sid}-{scale:.1f}x-{direction}-loop.gif'
                  for batch in contract['batches'].values() for sid in batch['signatures']
                  for scale in [0.5,1,2] for direction in ['left','right']}
        found={p.name for p in directory.glob('*.gif')}
        if found!=expected:
            raise ValueError(f'GIF coverage mismatch missing={sorted(expected-found)} extra={sorted(found-expected)}')
        for name in sorted(expected):
            path=directory/name
            with Image.open(path) as gif:
                count=gif.n_frames; loop=gif.info.get('loop'); durations=set()
                for index in range(count):
                    gif.seek(index);gif.convert('RGBA').load()
                    durations.add(gif.info.get('duration'))
                if count!=100 or loop!=0 or durations!={50}:
                    raise ValueError(f'Invalid loop {name}: {count}, {loop}, {durations}')
                gif_rows.append({'file':name,'frames':count,'size':list(gif.size),'loop':loop,
                                 'durations':sorted(durations),'sha256':digest(path)})
        report['gifVerification']={'directory':str(directory),'passed':True,'files':gif_rows,
                                   'gifCount':len(gif_rows),'decodedFrames':sum(x['frames'] for x in gif_rows)}
    (out/'preview-evidence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(f'Contact sheets: {len(rows)}; GIFs: {len(report.get("gifVerification",{}).get("files",[]))}')


if __name__=='__main__':
    main()
