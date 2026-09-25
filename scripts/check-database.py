#!/usr/bin/env python3
"""Run migrations and RLS tests in a disposable, isolated Supabase Postgres image."""
import pathlib
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
name = 'pulselab-test-' + uuid.uuid4().hex[:10]
image = 'public.ecr.aws/supabase/postgres:17.6.1.147'

def sql(path):
    result = subprocess.run(['docker','exec','-i',name,'psql','-U','supabase_admin','-d','pulselab_test','-v','ON_ERROR_STOP=1','-At'], input=path.read_text(), text=True, capture_output=True)
    if result.returncode or 'not ok ' in result.stdout:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout

try:
    subprocess.run(['docker','run','-d','--name',name,'--network','none','-e','POSTGRES_PASSWORD=local-test-only','-e','POSTGRES_DB=pulselab_test','--tmpfs','/var/lib/postgresql/data',image],check=True,capture_output=True)
    for _ in range(50):
        check = subprocess.run(['docker','exec',name,'pg_isready','-U','supabase_admin','-d','pulselab_test'],capture_output=True)
        if check.returncode == 0:
            time.sleep(2)
            break
        time.sleep(.5)
    sql(ROOT/'supabase/tests/bootstrap.sql')
    for path in sorted((ROOT/'supabase/migrations').glob('*.sql')):
        sql(path)
    print(sql(ROOT/'supabase/tests/research_access.sql'))
finally:
    # Exact uniquely-created container; no shared DB or named volume is touched.
    subprocess.run(['docker','rm','-f',name],capture_output=True)
