"""Numerical decisions and bounded primary/follow-up scheduling; no samplers."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import mgmfrm_core_pilot as P

ROSTER=([dict(parameter=f'p{i}',role='primary',kind='parameter') for i in range(59)]
        +[dict(parameter=f's{i}',role='secondary',kind='parameter') for i in range(2)]
        +[dict(parameter=f'prob{i}',role='primary',kind='probability') for i in range(8)])


def fit(shift=0, mcse=.001, qualified=True):
    rows=[]
    for r in ROSTER:
        delta=.2*shift if r['kind']=='probability' else shift
        quantiles=[dict(probability=p,estimate=x+delta,mcse=mcse)
                   for p,x in ((.025,-1.96),(.05,-1.645),(.5,0),(.95,1.645),(.975,1.96))]
        rows.append(dict(parameter=r['parameter'],estimate=(.5 if r['kind']=='probability' else 0)+delta,
                         posterior_sd=1.,mcse=dict(mean_mcse=mcse,quantiles=quantiles,mcse_status='available')))
    return dict(rows=rows,computationally_qualified=qualified)


class CorePilotChecks(unittest.TestCase):
    def test_child_environment_respects_package_build_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            c=dict(directory=tmp)
            with patch.object(P.guard,'run_guarded',return_value=dict(status='completed')) as guard:
                P.launch(c,'compile-only',['julia','check.jl'],seconds=180)
                command=guard.call_args.args[0]
                for name in ('MAKEFLAGS','GNUMAKEFLAGS','MAKEFILES','MFLAGS'):
                    self.assertIn(name+'=',command)
                self.assertNotIn('MAKEFLAGS=-j1',command)
                self.assertTrue(guard.call_args.kwargs['allow_descendant_groups'])

    def test_difference_and_numerical_uncertainty(self):
        agreed=P.compare_rows(ROSTER,[fit(),fit()])
        self.assertEqual(agreed['primary_counts'],dict(agreement=303,discrepancy=0,inconclusive=0))
        self.assertGreater(agreed['z'],3.7)
        self.assertEqual(len(agreed['rows']),313)
        different=P.compare_rows(ROSTER,[fit(),fit(shift=1)])
        self.assertEqual(different['primary_counts']['discrepancy'],303)
        noisy=P.compare_rows(ROSTER,[fit(mcse=.1),fit(mcse=.1)])
        self.assertEqual(noisy['primary_counts']['inconclusive'],303)
        self.assertFalse(agreed['scientific_acceptance'])

    def test_unqualified_missing_and_unavailable_are_inconclusive(self):
        for pair in ([fit(),None],[None,None],[fit(),fit(qualified=False)]):
            result=P.compare_rows(ROSTER,pair)
            self.assertEqual(result['primary_counts']['inconclusive'],303)
        bad=fit();bad['rows'][0]['mcse']['mean_mcse']=None
        result=P.compare_rows(ROSTER,[fit(),bad])
        self.assertEqual(result['rows'][0]['status'],'inconclusive')
        self.assertEqual(result['rows'][0]['reason'],'unavailable_precision')
        self.assertTrue(all(r['status']=='inconclusive' for r in P.compare_rows(ROSTER,[None,None])['rows']))

    def test_distinct_90_and_95_interval_widths(self):
        rows=P.compare_rows(ROSTER,[fit(),fit()])['rows']
        self.assertAlmostEqual(rows[0]['tolerance'],.1)
        self.assertAlmostEqual(rows[1]['tolerance'],.392)
        self.assertAlmostEqual(rows[2]['tolerance'],.329)
        self.assertAlmostEqual(rows[-1]['tolerance'],.01)

    def test_fixed_two_fit_roster_and_no_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);P.write(root/'contract.json',{})
            c=dict(directory=str(root),julia_executable='julia',python_executable=sys.executable,
                   planned_backends=list(P.BACKENDS),maximum_fits=2,resources=dict(batch_wall_seconds=3600))
            with patch.object(P,'inputs',return_value=(c,{})), patch.object(P,'launch',return_value=dict(status='completed',launched=True)) as launch:
                P.run(root)
                self.assertEqual([call.args[1] for call in launch.call_args_list],['advancedhmc','cmdstan','comparison'])
                deadlines=[call.kwargs['deadline'] for call in launch.call_args_list]
                self.assertEqual(len(set(deadlines)),1)
                with self.assertRaises(FileExistsError): P.run(root)
                self.assertEqual(launch.call_count,3)

    def test_observation_failure_stops_the_batch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);P.write(root/'contract.json',{})
            c=dict(directory=str(root),julia_executable='julia',planned_backends=list(P.BACKENDS),
                   maximum_fits=2,resources=dict(batch_wall_seconds=3600))
            with patch.object(P,'inputs',return_value=(c,{})), patch.object(P,'launch',return_value=dict(status='observation_unavailable',launched=False)) as launch:
                P.run(root)
                self.assertEqual(launch.call_count,1)
                result=P.read(root/'batch-result.json')
                self.assertEqual(result['not_started'],['cmdstan'])
                self.assertIsNone(result['comparison_guard'])

    def test_followup_runs_only_cmdstan_once_and_stops_on_monitor_failure(self):
        for status in ('completed','command_failed','observation_unavailable'):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);P.write(root/'contract.json',{})
                c=dict(directory=str(root),julia_executable='julia',python_executable=sys.executable,
                       planned_backends=['cmdstan'],maximum_fits=1,reuse_pilot={},resources=dict(batch_wall_seconds=1860))
                with patch.object(P,'inputs',return_value=(c,{})), patch.object(P,'launch',return_value=dict(status=status)) as launch:
                    P.run(root)
                    expected=['cmdstan'] if status=='observation_unavailable' else ['cmdstan','comparison']
                    self.assertEqual([call.args[1] for call in launch.call_args_list],expected)
                    self.assertEqual(len({call.kwargs['deadline'] for call in launch.call_args_list}),1)
                    with self.assertRaises(FileExistsError):P.run(root)
                    self.assertEqual(launch.call_count,len(expected))

    def test_reuse_rejects_changed_evidence_model_or_recipe(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            c={k: {} for k in ('candidate_id','seeds','rng_policy','initialization','controls','criteria','precision','comparison')}
            c.update(observed_sha256='hash',observed_path='observed',source_sha256={'src/model.jl':'hash'})
            old=copy.deepcopy(c)
            c['reuse_pilot']=dict(directory=str(root),artifact_sha256={name:'hash' for name in P.REUSED_FILES})
            saved=dict(computationally_qualified=True,backend='advancedhmc',cache_sha256='hash',contract_sha256='hash')
            records={'contract.json':old,'checked.json':dict(contract_sha256='hash'),
                     'result.json':saved,'failure.json':dict(error='unsupported_make_environment'),
                     'batch-result.json':dict(not_started=[])}
            with patch.object(P,'digest',return_value='hash'), patch.object(P,'read',side_effect=lambda path:records[Path(path).name]):
                self.assertEqual(P.checked_reuse(c)[1],saved)
                for key,value in [('seeds',{'cmdstan':2}),('precision',{'mean':1.}),
                                  ('source_sha256',{'src/model.jl':'changed'}),('observed_sha256','changed')]:
                    bad=copy.deepcopy(c);bad[key]=value
                    with self.subTest(key=key), self.assertRaises(AssertionError):P.checked_reuse(bad)
                bad=copy.deepcopy(c);bad['reuse_pilot']['artifact_sha256']['advancedhmc/fit.jls']='changed'
                with self.assertRaisesRegex(ValueError,'Reused evidence changed'):P.checked_reuse(bad)

    def test_comparison_uses_original_julia_and_new_cmdstan_contracts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);origin=root/'original';follow=root/'followup'
            origin.mkdir();follow.mkdir();P.write(origin/'contract.json',{'original':True});P.write(follow/'contract.json',{'followup':True})
            for path,backend in ((origin,'advancedhmc'),(follow,'cmdstan')):
                (path/backend).mkdir();(path/backend/'fit.jls').write_bytes(b'cache')
                result=fit();result.update(backend=backend,contract_sha256=P.digest(path/'contract.json'),cache_sha256=P.digest(path/backend/'fit.jls'))
                P.write(path/backend/'result.json',result)
            c=dict(reuse_pilot=dict(directory=str(origin)))
            with patch.object(P,'inputs',return_value=(c,dict(focal=ROSTER))):P.compare(follow)
            self.assertEqual(P.read(follow/'comparison.json')['primary_counts']['agreement'],303)
            self.assertFalse((origin/'comparison.json').exists())

    def test_changed_contract_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            P.write(root/'contract.json',dict(preflight_path=str(root/'preflight.json')))
            P.write(root/'preflight.json',dict(contract_sha256='not-the-saved-contract'))
            with self.assertRaises(ValueError): P.inputs(root)


if __name__=='__main__':
    unittest.main(verbosity=2)
