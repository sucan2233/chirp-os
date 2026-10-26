#!/usr/bin/env python3
"""Offline Pro signing/provenance checks; uses disposable keys and repositories."""
from pathlib import Path
import os, shutil, stat, subprocess, tempfile

ROOT = Path(__file__).resolve().parent.parent
checks = 0

def run(args, *, cwd=ROOT, env=None, success=True):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    if (result.returncode == 0) != success:
        raise AssertionError((args, result.returncode, result.stdout, result.stderr))
    return result

def check(name, condition=True):
    global checks
    assert condition, name
    checks += 1
    print('PASS', name)

for script in ['build.sh', 'package-pro-macos.sh', 'release-pro-macos.sh']:
    run(['bash', '-n', str(ROOT/'scripts'/script)])
    check('shell syntax: '+script)
workflow=(ROOT/'.github/workflows/release-pro.yml').read_text()
publisher=(ROOT/'scripts/publish-pro-release.py').read_text()
for marker in ['persist-credentials: false','CHIRPOS_UPDATE_PRIVATE_KEY','refs/tags/$RELEASE_TAG^{commit}', 'publish-pro-release.py']:
    check('workflow contract: '+marker,marker in workflow)
for marker in ["'draft': True", "'make_latest': 'false'", "asset['digest'] != want['digest']", "endpoint = f'{base}/releases/{release_id}'"]:
    check('publisher contract: '+marker,marker in publisher)
check('draft verification never uses published-tag endpoint', '/releases/tags/' not in publisher.replace('# /releases/tags/{tag} only returns published releases. Drafts must use ID.', ''))
# Validate each literal shell block without executing CI/network operations.
lines=workflow.splitlines();i=0
while i<len(lines):
    if lines[i].strip()=='run: |':
        indent=len(lines[i])-len(lines[i].lstrip());block=[];i+=1
        while i<len(lines) and (not lines[i].strip() or len(lines[i])-len(lines[i].lstrip())>indent):
            block.append(lines[i][indent+2:]);i+=1
        parsed=subprocess.run(['bash','-n'],input='\n'.join(block)+'\n',text=True,capture_output=True)
        check('workflow shell block',parsed.returncode==0)
    else:i+=1
with tempfile.TemporaryDirectory(prefix='chirpos-pro-release-') as tmp:
    temp=Path(tmp);sign=temp/'sign'
    run(['swiftc','-O',str(ROOT/'scripts/pro-update-sign.swift'),'-o',str(sign)])
    private=temp/'private';public=temp/'public'
    run([str(sign),'init',str(private),str(public)])
    check('private file permissions',stat.S_IMODE(private.stat().st_mode)==0o600)
    run([str(sign),'init',str(private),str(public)],success=False);check('init refuses overwrite')
    run([str(sign),'check-key',str(private),str(public)]);check('key pair matches')
    other_private=temp/'other-private';other_public=temp/'other-public'
    run([str(sign),'init',str(other_private),str(other_public)])
    run([str(sign),'check-key',str(private),str(other_public)],success=False);check('wrong key pair rejected')
    archive=temp/'ChirpOS-Pro-0.8.0-macOS-arm64.zip';original=b'fixed fixture archive bytes';archive.write_bytes(original)
    run([str(sign),'sign',str(archive),'0.8.0',str(private),str(public)])
    run([str(sign),'verify',str(archive),'0.8.0',str(public)]);check('valid detached signature')
    run([str(sign),'verify',str(archive),'0.8.1',str(public)],success=False);check('version tamper rejected')
    run([str(sign),'verify',str(archive),'0.8.0',str(other_public)],success=False);check('wrong publisher rejected')
    archive.write_bytes(b'X'+original[1:]);run([str(sign),'verify',str(archive),'0.8.0',str(public)],success=False);check('same-size content tamper rejected');archive.write_bytes(original)
    renamed=temp/'other.zip';shutil.copyfile(archive,renamed);shutil.copyfile(str(archive)+'.sig',str(renamed)+'.sig')
    run([str(sign),'verify',str(renamed),'0.8.0',str(public)],success=False);check('filename tamper rejected')
    for version in ['0.8.0-beta','0.8.0\nevil','0.08.0','0.0.0']:
        run([str(sign),'sign',str(archive),version,str(private),str(public)],success=False)
    check('invalid versions rejected')
    repo=temp/'repo';(repo/'scripts').mkdir(parents=True);(repo/'config').mkdir();(repo/'.local').mkdir();(repo/'docs/releases').mkdir(parents=True)
    for name in ['release-pro-macos.sh','pro-update-sign.swift']:
        shutil.copyfile(ROOT/'scripts'/name,repo/'scripts'/name)
    (repo/'scripts/pro-version.txt').write_text('0.8.0\n')
    shutil.copyfile(private,repo/'.local/pro-update-private-key');shutil.copyfile(public,repo/'config/pro-update-public-key.txt')
    (repo/'.gitignore').write_text('.local/\n');(repo/'docs/releases/pro-v0.8.0.md').write_text('Pro 0.8.0 fixture\n')
    run(['git','init','-q'],cwd=repo);run(['git','add','.'],cwd=repo)
    run(['git','-c','user.name=Offline Test','-c','user.email=test@example.invalid','commit','-qm','test(发布): 初始化隔离发布夹具'],cwd=repo)
    env={k:v for k,v in os.environ.items() if not k.startswith('CHIRPOS_') and k!='RELEASE_TAG'}
    run(['bash','scripts/release-pro-macos.sh','--check'],cwd=repo,env=env,success=False);check('missing tag refused')
    run(['git','tag','pro-v0.8.0'],cwd=repo)
    run(['bash','scripts/release-pro-macos.sh','--check'],cwd=repo,env=env);check('clean tagged release passes preflight')
    run(['bash','scripts/release-pro-macos.sh','--check'],cwd=repo,env={**env,'RELEASE_TAG':'pro-v0.8.1'},success=False);check('tag version mismatch refused')
    (repo/'uncommitted.txt').write_text('dirty')
    run(['bash','scripts/release-pro-macos.sh','--check'],cwd=repo,env=env,success=False);check('dirty release refused')
print(f'{checks} Pro release checks passed; no network, publication, or production keys accessed.')
