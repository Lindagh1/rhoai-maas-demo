import json, subprocess, yaml
cmd=['oc','get','configmap','cluster-monitoring-config','-n','openshift-monitoring','-o','json']
d=json.loads(subprocess.check_output(cmd))
config=yaml.safe_load(d.get('data',{}).get('config.yaml','')) or {}
config['enableUserWorkload']=True
patch={'data':{'config.yaml':yaml.safe_dump(config)}}
subprocess.run(['oc','patch','configmap','cluster-monitoring-config','-n','openshift-monitoring','--type=merge','-p',json.dumps(patch)],check=True)
