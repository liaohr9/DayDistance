#!/usr/bin/env python3
"""Independent CLI/MCP end-to-end client. Writes are restricted to the disposable QA identity."""
import argparse,json,plistlib,subprocess,uuid,select
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('app',type=Path);ap.add_argument('--mode',choices=['disabled','full','busy','readonly','open'],default='full');args=ap.parse_args()
app=args.app.resolve();info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
identity=info['CFBundleIdentifier']
assert identity=='local.dd.agentqa' or (identity.startswith('local.dd.mcplaunch') and identity.endswith('qa')), 'Only the explicitly disposable QA app may be mutated'
cmd=[str(app/'Contents/MacOS/DayDistance'),'--cli']
def cli(*arguments,code=0,stdin=None):
 r=subprocess.run(cmd+list(arguments),input=stdin,text=True,capture_output=True,timeout=40)
 assert r.returncode==code,(r.returncode,r.stdout,r.stderr)
 return json.loads(r.stdout)
def error(r,name):assert r['ok'] is False and r['error']['code']==name,r
if args.mode=='open':
 e=cli('events','list')['data']['events'][0]
 r=cli('events','open',e['id']);assert r['data']['opening'] is True
 error(cli('events','create','--title','must not save','--date','2027-03-01','--request-id','open-editor-busy',code=75),'BUSY')
 print('CLIENT_OPEN_ACK_PASS',e['id'],e['title']);raise SystemExit
if args.mode=='disabled':
 error(cli('events','list',code=77),'DISABLED');print('CLIENT_DISABLED_PASS');raise SystemExit
if args.mode=='readonly':
 assert cli('events','list')['ok'];error(cli('events','create','--title','forbidden','--date','2027-03-01','--request-id','read-only-test',code=77),'READ_ONLY');print('CLIENT_READONLY_PASS');raise SystemExit
if args.mode=='busy':
 error(cli('events','create','--title','Busy','--date','2027-03-01','--request-id','draft-test',code=75),'BUSY');print('CLIENT_BUSY_PASS');raise SystemExit
key=str(uuid.uuid4())
r=cli('events','create','--title','Agent Demo','--date','2027-03-01','--request-id',key,'--tag','Agent')
e=r['data']['event'];assert r['ok'] and r['data']['replayed'] is False
repeat=cli('events','create','--title','Agent Demo','--date','2027-03-01','--request-id',key,'--tag','Agent')
assert repeat['data']['event']['id']==e['id'] and repeat['data']['replayed'] is True
error(cli('events','create','--title','Different','--date','2027-03-01','--request-id',key,code=75),'CONFLICT')
error(cli('events','trash',e['id'],'--if-revision','stale',code=75),'CONFLICT')
assert cli('events','countdown',e['id'])['data']['days']>=0
p=subprocess.Popen(cmd+['mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def rpc(i,method,params=None):
 p.stdin.write(json.dumps({'jsonrpc':'2.0','id':i,'method':method,'params':params or {}})+'\n');p.stdin.flush()
 if not select.select([p.stdout],[],[],8)[0]:
  p.terminate();p.wait(timeout=5);raise AssertionError("MCP response timed out before stdin EOF")
 value=json.loads(p.stdout.readline());assert value['id']==i;return value
assert rpc(1,'initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'independent-python-client','version':'1'}})['result']['protocolVersion']=='2025-11-25'
p.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');p.stdin.flush()
assert len(rpc(2,'tools/list')['result']['tools'])==10
r=rpc(3,'tools/call',{'name':'daydistance_update','arguments':{'id':e['id'],'revision':e['revision'],'title':'Agent Demo · MCP'}})['result']
assert not r['isError'];e=r['structuredContent']['data']['event']
assert json.loads(r['content'][0]['text'])==r['structuredContent']
assert rpc(4,'tools/call',{'name':'unknown'})['error']['code']==-32602
for i,op in enumerate(['archive','trash','restore','restore'],5):
 r=rpc(i,'tools/call',{'name':'daydistance_'+op,'arguments':{'id':e['id'],'revision':e['revision']}})['result'];assert not r['isError'],r;e=r['structuredContent']['data']['event']
assert e['state']=='active'
p.stdin.close();p.wait(timeout=10);assert p.returncode==0,p.stderr.read()
assert cli('events','get',e['id'])['data']['event']['title']=='Agent Demo · MCP'
r=cli('--stdin',stdin=json.dumps({'apiVersion':1,'operation':'get','arguments':{'id':e['id']}}));assert r['ok']
print('CLIENT_FULL_PASS: CLI create/retry/conflict/countdown/stdin; MCP initialize/notification/tools/update/archive/trash/restore; persisted readback')
