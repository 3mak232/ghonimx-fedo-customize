"""Concurrency test for the v5 roll ledger. Destructive: only on database fedo_roll_v5_race.

Two sessions race for the same 40-unit roll through the public RPC
factory_issue_roll: 30 must succeed, the competing order must be rejected,
and both the roll remaining and FEDO stock must end at 10.

Usage (local PostgreSQL owner):
    createdb fedo_roll_v5_race
    psql -d fedo_roll_v5_race -f <migrations...>       # see run_all_local.sh
    python3 factory_roll_v5_race_test.py [--psql PATH] [--host H --port P --user U]
"""
import argparse
import concurrent.futures
import pathlib
import subprocess
import sys

DB = 'fedo_roll_v5_race'
HERE = pathlib.Path(__file__).resolve().parent
PRODUCT = 'c5200000-0000-4000-8000-000000000001'
ADMIN = 'c5000000-0000-4000-8000-000000000001'
ROLL = "(SELECT id FROM factory_rolls WHERE roll_code='V5RACE-ROLL')"

ap = argparse.ArgumentParser()
ap.add_argument('--psql', default='psql')
ap.add_argument('--host'); ap.add_argument('--port'); ap.add_argument('--user')
ap.add_argument('--sudo-postgres', action='store_true', help=argparse.SUPPRESS)
args = ap.parse_args()

cmd = ['sudo', '-u', 'postgres'] if args.sudo_postgres else []
cmd += [args.psql, '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', DB]
for flag, val in (('-h', args.host), ('-p', args.port), ('-U', args.user)):
    if val:
        cmd += [flag, val]


def run(*sql):
    return subprocess.run(cmd + list(sql), text=True, capture_output=True)


setup = run('-f', str(HERE / 'factory_roll_v5_race_setup.sql'))
if setup.returncode:
    print(setup.stderr)
    sys.exit('FAIL setup')

PREAMBLE = (
    "SELECT set_config('erp.factory_ledger','on',true); "
    "SELECT set_config('request.jwt.claims','{\"iat\":4102444800,\"aal\":\"aal2\"}',true); "
    f"SELECT set_config('request.jwt.claim.sub','{ADMIN}',true); ")


def issue(idx: int, qty: int):
    """Each session asks for a different work order, so one must lose the race."""
    wo = f"(SELECT id FROM work_orders WHERE number='V5RACE-WO-{idx}')"
    sql = ("BEGIN; " + PREAMBLE +
           f"SELECT factory_issue_roll('c5800000-0000-4000-8000-00000000000{idx}',{ROLL},{wo},{qty},'consumption',null); "
           "SELECT pg_sleep(0.6); COMMIT;")
    return run('-c', sql)


with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda a: issue(*a), ((1, 30), (2, 30))))

wins = [r for r in results if r.returncode == 0]
losses = [r for r in results if r.returncode != 0]
if len(wins) != 1:
    print([r.stdout + r.stderr for r in results])
    sys.exit('FAIL expected exactly one successful issue')
if 'المتبقي بالرول لا يكفي' not in losses[0].stderr:
    print(losses[0].stderr)
    sys.exit('FAIL unexpected rejection reason')

check = run('-Atc', f"""
SELECT b.remaining_qty::text || '|' || s.qty::text || '|' ||
       (SELECT count(*)::text FROM factory_roll_moves WHERE movement_type='consumption') || '|' ||
       (SELECT coalesce(sum(consumed_qty),0)::text FROM factory_roll_moves WHERE movement_type='consumption')
FROM factory_roll_balances b
JOIN stock_balances s ON s.product_id=b.product_id AND s.warehouse_id=b.warehouse_id
WHERE b.roll_code='V5RACE-ROLL';
""")
got = check.stdout.strip()
if check.returncode or got != '10.000|10.000|1|30.000':
    print(check.stdout, check.stderr)
    sys.exit(f'FAIL final consistency: {got!r}')

print('PASS two concurrent work orders on one roll: one issue of 30 succeeds, the other is rejected, '
      'roll remaining and FEDO stock both 10, single ledger row with 30 consumed')
