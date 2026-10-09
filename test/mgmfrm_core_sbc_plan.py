"""Execution setting checks, including missing attempts and wrong precision."""
import copy,json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_sbc_plan as P
from mgmfrm_core_rank_review import rank_bands


class SBCPlan(unittest.TestCase):
    def setUp(self):
        self.plan=P.proposal([f'x{i}' for i in range(150)],{'source.py':'0'*64})

    def test_manifest_and_changed_controls(self):
        checked=P.validate(self.plan)
        self.assertEqual(checked['total_draws_per_fit'],16000)
        self.assertEqual(checked['planned'],274)
        self.assertFalse(checked['bounds_verified_for_mgmfrm'])
        for key,value in [('planned_datasets',262),('band_multiplier',4.),('scientific_acceptance',True)]:
            changed=copy.deepcopy(self.plan);changed[key]=value
            with self.assertRaises(ValueError):P.validate(changed)
        for change in ('duplicate_name','missing_id','duplicate_seed','bool_seed','bad_path','unknown_field'):
            p=copy.deepcopy(self.plan)
            if change=='duplicate_name':p['names'][0]=p['names'][1]
            elif change=='missing_id':p['jobs'].pop()
            elif change=='duplicate_seed':p['jobs'][0]['truth_seed']=p['jobs'][1]['truth_seed']
            elif change=='bool_seed':p['jobs'][0]['truth_seed']=True
            elif change=='bad_path':p['source_sha256']={'../outside':'0'*64}
            else:p['unused']='ignored?'
            with self.assertRaises(ValueError):P.validate(p)
        self.assertEqual(P.validate(json.loads(json.dumps(self.plan))),checked)

    def test_source_change_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'source.py';source.write_text('x=1\n')
            self.plan['source_sha256']={'source.py':P.digest(source)}
            P.validate(self.plan,repository=tmp)
            source.write_text('x=2\n')
            with self.assertRaises(ValueError):P.validate(self.plan,repository=tmp)

    def test_full_roster_collection_and_bound_bands(self):
        bands=rank_bands(range(16000),quantile_ess={p:800. for p in (.05,.5,.95)})
        rows=[dict(parameter=name,truth=-1.,rank_bands=bands) for name in self.plan['names']]
        identity=P.identity(self.plan)
        record=dict(id='joint-001',plan_identity=identity,qualified=True,rows=rows)
        failed=dict(id='joint-002',plan_identity=identity,qualified=False,rows=None)
        report=P.collect(self.plan,[record,failed])
        summary=report['nominal_reference']
        self.assertEqual(summary['planned'],274)
        self.assertEqual(len(summary['absent_ids']),272)
        self.assertEqual(summary['rows'][0]['tests']['below_median_high']['unresolved'],273)
        self.assertFalse(report['scientific_acceptance'])
        for change in ('identity','width','draw_count','ess','sentinel','duplicate','unplanned'):
            bad=copy.deepcopy(record)
            if change=='identity':bad['plan_identity']='0'*64
            elif change=='width':bad['rows'][0]['rank_bands'][0]['multiplier']=4.
            elif change=='draw_count':bad['rows'][0]['rank_bands'][0]['total_draws']=4000
            elif change=='ess':bad['rows'][0]['rank_bands'][0]['ess']=12.
            elif change=='sentinel':bad['rows'][0]['rank_bands'][0]['lower']=None
            elif change=='unplanned':bad['id']='foreign'
            with self.assertRaises(ValueError):P.collect(self.plan,[bad,bad] if change=='duplicate' else [bad])
        unavailable=rank_bands(range(16000),quantile_ess={p:None for p in (.05,.5,.95)})
        record['rows']=[dict(parameter=name,truth=1.,rank_bands=unavailable) for name in self.plan['names']]
        unknown=P.collect(self.plan,[record])['nominal_reference']
        self.assertEqual(unknown['rows'][0]['tests']['below_median_high']['unresolved'],274)


if __name__=='__main__':unittest.main()
