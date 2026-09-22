import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_run_plan as R

PLAN=Path(sys.argv.pop(1))
OUTPUT=Path(sys.argv.pop(1))


class RunPlanChecks(unittest.TestCase):
    def setUp(self):self.c=json.loads(PLAN.read_text())

    def test_fixed_roster_and_order(self):
        c=self.c
        self.assertEqual(len(c['jobs']),12)
        self.assertEqual(len({j['job_id'] for j in c['jobs']}),12)
        self.assertEqual([j['condition'] for j in c['jobs']],['R0','R1']*6)
        for condition in ['R0','R1']:
            self.assertEqual([j['fold'] for j in c['jobs'] if j['condition']==condition],[None,1,2,3,4,5])

    def test_seeds_and_generation_pair(self):
        c=self.c
        self.assertEqual(len(set(c['seeds'].values())|{j['fit_seed'] for j in c['jobs']}),15)
        a,b=[json.loads((Path(c['inputs'][x]['directory'])/'truth.json').read_text()) for x in ['R0','R1']]
        self.assertEqual(a['raw'][:100],b['raw'][:100])
        self.assertEqual(a['raw'][100:109],b['raw'][100:109])
        self.assertEqual(a['raw'][111:],b['raw'][111:])
        self.assertNotEqual(a['raw'][109:111],b['raw'][109:111])
        for x in ['R0','R1']:
            g=json.loads((Path(c['inputs'][x]['directory'])/'generation.json').read_text())
            self.assertEqual((g['person_seed'],g['score_seed'],g['redraws']),(9270101,9270102,0))

    def test_budget_arithmetic(self):
        c=self.c;r=c['resources']
        self.assertEqual(c['complete_data_fits']+c['cv_refits'],12)
        self.assertEqual(12*(r['fit_wall_seconds']+r['score_wall_seconds']),25200)
        self.assertLessEqual(25200+r['prepare_wall_seconds']+r['collection_wall_seconds'],r['batch_wall_seconds'])
        self.assertEqual(r['shared_output_bytes'],4*2**30)
        self.assertEqual(r['parallel_jobs'],1)

    def test_no_scientific_promotion(self):
        c=self.c
        self.assertFalse(c['execution_allowed'] or c['protocol_frozen'] or c['scientific_acceptance'])
        self.assertEqual(c['review'],dict(scientific='open',execution='open'))
        self.assertEqual([k for k,v in c['claims'].items() if v],['feasibility_and_cost'])
        self.assertEqual(c['uncertainty']['independent_replications_per_condition'],1)
        self.assertEqual(c['uncertainty']['coverage_all_success_95_two_sided_exact_lower'],.025)
        self.assertEqual(c['uncertainty']['zero_failure_95_one_sided_upper'],.95)

    def test_input_and_prospective_identity(self):
        c=self.c
        self.assertEqual(R.P.digest(PLAN.parent/'proposal.json'),c['proposal_sha256'])
        proposal=json.loads((PLAN.parent/'proposal.json').read_text())
        self.assertEqual({k:c[k] for k in proposal},proposal)
        for x in ['R0','R1']:
            p=c['inputs'][x]
            for k,n in R.FILES.items():self.assertEqual(R.P.digest(Path(p['directory'])/n),p['hashes'][k])

    def test_seed_inventory_scope(self):
        with tempfile.TemporaryDirectory(dir=OUTPUT.parent) as tmp:
            p=Path(tmp)/'records.json';bad=Path(tmp)/'broken.json'
            p.write_text(json.dumps(dict(seed=1,rng=dict(chain_seeds=[2,3]),seeds=dict(fit=4),score=5)))
            bad.write_text('{')
            found,unreadable=R.seed_inventory([p,bad])
            self.assertEqual(set(found),{1,2,3,4})
            self.assertEqual(unreadable,[str(bad)])


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RunPlanChecks))
    R.F.publish(OUTPUT,dict(tests=result.testsRun,errors=len(result.errors),failures=len(result.failures),new_sampler_runs=0))
    raise SystemExit(0 if result.wasSuccessful() else 1)
