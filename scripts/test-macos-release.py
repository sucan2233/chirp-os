#!/usr/bin/env python3
"""Test release preflight without accessing real keys or submitting software."""
import os
import pty
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    tools = tmp / 'bin'
    tools.mkdir()
    for name, body in {
        'security': 'printf \'%s\\n\' "${TEST_IDENTITIES:-}"\n',
        'xcrun': 'exit "${TEST_NOTARY_STATUS:-0}"\n',
    }.items():
        p = tools / name
        p.write_text('#!/bin/bash\n' + body)
        p.chmod(0o755)
    config = tmp / 'release.env'
    config.write_text("CHIRPOS_SIGNING_IDENTITY='Developer ID Application: Example (TEST)'\nCHIRPOS_NOTARY_PROFILE='test-profile'\n")
    env = {k:v for k,v in os.environ.items() if not k.startswith('CHIRPOS_')}
    env.update(PATH=str(tools)+os.pathsep+env['PATH'], CHIRPOS_RELEASE_CONFIG=str(config),
               TEST_IDENTITIES='  1) ABC "Developer ID Application: Example (TEST)"', CI='true')
    def check(name, changes, args, expected):
        result = subprocess.run(['/bin/bash',str(root/'scripts/release-macos.sh'),*args],
            env={**env,**changes},stdin=subprocess.DEVNULL,capture_output=True,text=True)
        assert result.returncode == expected, (name,result.stdout,result.stderr)
        print('PASS',name)
    check('valid local configuration',{},['--check'],0)
    check('missing config fails without build',{'CHIRPOS_RELEASE_CONFIG':str(tmp/'missing')},[],1)
    check('missing identity fails',{'TEST_IDENTITIES':''},['--check'],1)
    check('notary failure fails closed',{'TEST_NOTARY_STATUS':'1'},[],1)
    check('environment overrides local configuration',{'CHIRPOS_SIGNING_IDENTITY':'Developer ID Application: Other (OTHER)'},['--check'],1)
    check('reject non-Developer-ID identity',{'CHIRPOS_SIGNING_IDENTITY':'-'},['--check'],1)
    check('explicit ad-hoc skips credentials',{'CHIRPOS_RELEASE_CONFIG':str(tmp/'missing')},['--ad-hoc','--check'],0)
    check('unknown options fail',{},['--unknown'],2)
    fake_bash = tools / 'bash'
    fake_bash.write_text('#!/bin/bash\n[ -z "$CHIRPOS_SIGNING_IDENTITY" ] || exit 74\n[ "$CHIRPOS_DEVELOPMENT_BUILD" = 0 ] || exit 75\n[ "$CHIRPOS_PRO_BUILD" = 0 ] || exit 76\necho ADHOC_BUILD_REQUESTED\nexit 73\n')
    fake_bash.chmod(0o755)
    for reply, expected in [('n',1),('',1),('y',73)]:
        master, slave = pty.openpty()
        try:
            proc = subprocess.Popen(['/bin/bash',str(root/'scripts/release-macos.sh')],
                env={**env,'CI':'','CHIRPOS_RELEASE_CONFIG':str(tmp/'missing'),'CHIRPOS_DEVELOPMENT_BUILD':'1','CHIRPOS_PRO_BUILD':'1'},
                stdin=slave,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            os.write(master,(reply+'\n').encode())
            out, err = proc.communicate(timeout=10)
            assert proc.returncode == expected, (reply,out,err)
            assert '[y/N]' in err
            assert ('ADHOC_BUILD_REQUESTED' in out) == (reply=='y')
            print('PASS interactive fallback',repr(reply))
        finally:
            os.close(master)
            os.close(slave)
print('11 release preflight and fallback checks passed.')
