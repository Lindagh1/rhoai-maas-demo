#!/usr/bin/env python3
"""Client MaaS autonome: Python stdlib + curl, aucun droit OpenShift requis."""
import argparse, json, os, pathlib, subprocess, sys, time, socket
from urllib.parse import urlsplit

def request(base, key, path, body=None):
    # Secret on stdin, never in argv or output. TLS validation remains enabled.
    if any(c in key for c in '\r\n"\\'):
        raise ValueError('Invalid API key file')
    cmd = ['curl','--silent','--show-error','--http1.1',
           '--connect-timeout','10','--max-time','120','--config','-',
           '-w','\n%{http_code}',base.rstrip('/')+path]
    if body is not None:
        cmd += ['-H','Content-Type: application/json','--data-binary',json.dumps(body)]
    p = subprocess.run(cmd,input='header = "Authorization: Bearer '+key+'"\n',
                       text=True,capture_output=True)
    # A single-node sandbox can have an unhealthy LB zone. Retry only TLS
    # handshake failures (no HTTP request was sent), against resolved addresses.
    if p.returncode == 35:
        host=urlsplit(base).hostname
        for address in dict.fromkeys(i[4][0] for i in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)):
            p=subprocess.run(cmd+['--resolve',f'{host}:443:{address}'],
                input='header = "Authorization: Bearer '+key+'"\n',text=True,capture_output=True)
            if p.returncode != 35: break
    if p.returncode:
        raise RuntimeError(p.stderr.strip())
    body, code = p.stdout.rsplit('\n',1)
    try: body = json.loads(body)
    except json.JSONDecodeError: body = {'message':body[:300]}
    return int(code), body

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url',default=os.getenv('MAAS_URL'))
    p.add_argument('--key-file',default='secrets/demo-user.apikey')
    p.add_argument('--model',help='Exact model ID; by default require exactly one model in maas-demo')
    p.add_argument('--count',type=int,default=1)
    p.add_argument('--expect-429',action='store_true')
    p.add_argument('--output',default='evidence/last-call.json')
    args=p.parse_args()
    if not args.url or not args.url.startswith('https://'): p.error('--url https://... or MAAS_URL is required')
    if not 1 <= args.count <= 30: p.error('--count must be between 1 and 30')
    key=pathlib.Path(args.key_file).read_text().strip()
    code, models=request(args.url,key,'/v1/models')
    if code!=200: raise RuntimeError(f'Model discovery HTTP {code}: {models}')
    ids=[m['id'] for m in models.get('data',[])]
    if not args.model:
        candidates=[i for i in ids if i.startswith('publishers/maas-demo/models/')]
        if len(candidates)!=1: raise RuntimeError(f'Specify --model explicitly; demo candidates: {candidates}')
        args.model=candidates[0]
    if args.model not in ids: raise RuntimeError(f'Model {args.model} not accessible; discovered {ids}')
    results=[]
    for i in range(args.count):
        code, body=request(args.url,key,'/v1/chat/completions',{
            'model':args.model,'messages':[{'role':'user','content':'En une phrase simple, explique à quoi sert une API.'}],
            'temperature':0,'max_tokens':64})
        results.append({'http':code,'usage':body.get('usage'),
            'answer':body.get('choices',[{}])[0].get('message',{}).get('content','')})
        print(json.dumps({'call':i+1,**results[-1]},ensure_ascii=False))
        if code==429 and args.expect_429:break
        if code!=200:break
        if i+1<args.count:time.sleep(1)
    out=pathlib.Path(args.output);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps({'time':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'model':args.model,'results':results},indent=2,ensure_ascii=False)+'\n')
    if args.expect_429: return 0 if any(r['http']==429 for r in results) else 1
    return 0 if all(r['http']==200 and r['usage'] and r['usage'].get('total_tokens',0)>0 for r in results) else 1
if __name__=='__main__':
    try: sys.exit(main())
    except (RuntimeError,ValueError,OSError) as e: print(str(e),file=sys.stderr);sys.exit(1)
