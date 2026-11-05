#!/usr/bin/env python3
"""Temporarily withdraw demo-team from its policy, then restore its exact subjects."""
import json
import os
import pathlib
import subprocess
import time

from client import request


def oc_json(*args):
    return json.loads(subprocess.check_output(['oc', *args, '-o', 'json']))


def wait_for_http(base, key, body, expected):
    deadline = time.monotonic() + 120
    while True:
        code, _ = request(base, key, '/v1/chat/completions', body)
        if code in expected or time.monotonic() >= deadline:
            return code
        time.sleep(3)


def main():
    base = os.environ['MAAS_URL']
    key = pathlib.Path('secrets/demo-user.apikey').read_text().strip()
    target = ['maasauthpolicy', 'demo-access', '-n', 'models-as-a-service']
    policy = oc_json('get', *target)
    policies = oc_json('get', 'maasauthpolicy', '-A')['items']
    for other in policies:
        if other['metadata']['uid'] == policy['metadata']['uid']:
            continue
        if any(m.get('name') == 'demo-llm' and m.get('namespace') == 'maas-demo'
               for m in other.get('spec', {}).get('modelRefs', [])):
            raise RuntimeError('Another policy covers demo-llm. Review it before this test.')

    # Keep the resource present: deleting its final grant did not refresh the
    # generated gateway policy on the tested build. See docs/VALIDATION.md.
    denied_group = 'maas-demo-no-members'
    groups = oc_json('get', 'groups')['items']
    if any(g['metadata']['name'] == denied_group and g.get('users') for g in groups):
        raise RuntimeError(f'{denied_group} must have no members for this test')
    code, models = request(base, key, '/v1/models')
    if code != 200:
        raise RuntimeError(f'Model discovery HTTP {code}')
    ids = [m['id'] for m in models['data'] if m['id'].startswith('publishers/maas-demo/models/')]
    if len(ids) != 1:
        raise RuntimeError(f'Expected one demo model, found {ids}')
    body = {'model': ids[0], 'messages': [{'role': 'user', 'content': 'Bonjour'}], 'max_tokens': 8}
    original = policy['spec']['subjects']
    result = {'method': 'withdraw demo-team from subjects, then restore exact subjects'}
    evidence = pathlib.Path('evidence/access-test.json')
    evidence.parent.mkdir(parents=True, exist_ok=True)

    def patch_subjects(subjects):
        subprocess.run(['oc', 'patch', *target, '--type=json', '-p', json.dumps([
            {'op': 'replace', 'path': '/spec/subjects', 'value': subjects}
        ])], check=True, stdout=subprocess.DEVNULL)

    try:
        patch_subjects({'groups': [{'name': denied_group}], 'users': []})
        result['without_group'] = wait_for_http(base, key, body, {401, 403})
        print('Without demo-team:', result['without_group'], flush=True)
    finally:
        patch_subjects(original)
        result['restored_policy'] = wait_for_http(base, key, body, {200})
        evidence.write_text(json.dumps(result, indent=2) + '\n')
        print('Restored policy:', result['restored_policy'], flush=True)

    if result.get('without_group') not in (401, 403) or result['restored_policy'] != 200:
        raise RuntimeError(f'Authorization test failed: {result}')


if __name__ == '__main__':
    main()
