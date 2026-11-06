#!/usr/bin/env python3
"""Read real Limitador counters through an authenticated oc port-forward."""
import json,pathlib,re,socket,subprocess,time,urllib.request
with socket.socket() as s:
 s.bind(('127.0.0.1',0));port=s.getsockname()[1]
p=subprocess.Popen(['oc','port-forward','-n','kuadrant-system','svc/limitador-limitador',f'{port}:8080'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
 for _ in range(40):
  if p.poll() is not None:raise RuntimeError('oc port-forward failed')
  try:
   with urllib.request.urlopen(f'http://127.0.0.1:{port}/metrics',timeout=2) as r: metrics=r.read().decode()
   break
  except OSError:time.sleep(.25)
 else:raise RuntimeError('Limitador metrics unavailable')
 rows=[]
 for line in metrics.splitlines():
  if not re.match(r'^(authorized_hits|authorized_calls|limited_calls)\{',line):continue
  if 'limitador_namespace="maas-demo/demo-llm-kserve-route"' not in line:continue
  name,labels,value=re.match(r'(\w+)\{(.*)\} (\S+)',line).groups()
  rows.append({'metric':name,'labels':dict(re.findall(r'(\w+)="([^"]*)"',labels)),'value':float(value)})
 if not rows:raise RuntimeError('No demo traffic measured yet. Run make call first.')
 result={'time':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'source':'Limitador /metrics','scope':'Counters since process start; not a billing ledger','series':rows}
 out=pathlib.Path('evidence/usage.json');out.parent.mkdir(exist_ok=True);out.write_text(json.dumps(result,indent=2)+'\n')
 for r in rows:print(f"{r['labels'].get('subscription','?')}: {r['metric']} = {r['value']:g}")
finally:
 p.terminate()
 try:p.wait(timeout=5)
 except subprocess.TimeoutExpired:p.kill();p.wait()
