"""Destructive test fixture: use ONLY disposable database named fedo_roll_race.
Run as a local PostgreSQL owner after loading factory migrations. Needs psql.
"""
import concurrent.futures, os, pathlib, subprocess, sys
DB = 'fedo_roll_race'
HERE = pathlib.Path(os.path.relpath(__file__)).parent
PSQL = (['sudo','-u','postgres'] if '--sudo-postgres' in sys.argv else []) + ['psql','-X','-q','-v','ON_ERROR_STOP=1','-d',DB]
def run(*args):
    return subprocess.run(PSQL+list(args), text=True, capture_output=True)
setup = run('-f',str(HERE/'factory_roll_race_setup.sql'))
if setup.returncode:
    print(setup.stderr); sys.exit('FAIL setup')

def consume(idx):
    req=f'95000000-0000-4000-8000-00000000002{idx}'
    wo=f'95000000-0000-4000-8000-00000000001{idx}'
    sql=("BEGIN; "
         "SELECT set_config('request.jwt.claims','{\"iat\":4102444800,\"aal\":\"aal2\"}',true); "
         "SELECT set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000001',true); "
         f"SELECT factory_consume_roll_internal('{req}',(SELECT id FROM factory_rolls WHERE roll_code='RACE-ROLL'),'{wo}',30,'consumption'); "
         "SELECT pg_sleep(0.5); COMMIT;")
    return run('-c',sql)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results=list(pool.map(consume,(1,2)))
if sum(r.returncode==0 for r in results)!=1:
    print([r.stderr for r in results]); sys.exit('FAIL expected one success and one rejection')
failed=next(r for r in results if r.returncode!=0)
if 'المتبقي بالرول' not in failed.stderr:
    print(failed.stderr); sys.exit('FAIL unexpected rejection')
check=run('-Atc',"SELECT b.remaining_qty::text || '|' || s.qty::text || '|' || (SELECT count(*) FROM factory_roll_moves WHERE movement_type='consumption')::text FROM factory_roll_balances b JOIN stock_balances s ON s.product_id=b.product_id AND s.warehouse_id=b.warehouse_id WHERE b.roll_code='RACE-ROLL';")
if check.returncode or check.stdout.strip()!='10.000|10.000|1':
    print(check.stdout,check.stderr); sys.exit('FAIL final consistency')
print('PASS two concurrent orders: one issue of 30 succeeds, one rejects, roll and stock remain 10')
