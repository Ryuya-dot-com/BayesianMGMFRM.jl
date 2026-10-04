from pathlib import Path
from fractions import Fraction
import math,sys,unittest
from scipy.stats import norm
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from mgmfrm_core_rank_review import rank_band_indices,rank_bands,classify_rank_bands
from mgmfrm_core_classifier_review import rank_classification_error_mass
from mgmfrm_core_sbc_review import summarize

class RankBoundary(unittest.TestCase):
    def test_iid_tails_and_tight_indices_by_rational_sums(self):
        for n in (1,2,5,10,40,100):
            for p in (Fraction(1,20),Fraction(1,2),Fraction(19,20)):
                masses=[math.comb(n,k)*p**k*(1-p)**(n-k) for k in range(n+1)]
                for z in (2.,4.):
                    r=rank_band_indices(n,float(p),ess=n,multiplier=z)
                    lo,hi=r['lower_index'],r['upper_index'];tail=float(norm.sf(z))
                    self.assertLessEqual(float(sum(masses[:lo])),tail)
                    self.assertLessEqual(float(sum(masses[hi:])),tail)
                    if lo<n:self.assertGreater(float(sum(masses[:lo+1])),tail)
                    if hi>1:self.assertGreater(float(sum(masses[hi-1:])),tail)

    def test_ess_expansion_contains_iid_band(self):
        for n in (1,7,100):
            for p in (.05,.5,.95):
                base=rank_band_indices(n,p,ess=n)
                for ess in [*range(1,n+1),n*2,n-.1,.5,None,float('nan')]:
                    r=rank_band_indices(n,p,ess=ess)
                    self.assertLessEqual(r['lower_index'],base['lower_index'])
                    self.assertGreaterEqual(r['upper_index'],base['upper_index'])
                    self.assertFalse(r['finite_mcmc_coverage_verified'])
        r=rank_band_indices(100,.5,ess=None)
        self.assertEqual((r['lower_index'],r['upper_index']),(0,101))

    def test_monotone_transformation_and_boundary_ties(self):
        x=[(j-200)/100 for j in range(401)];ess={.05:200.,.5:300.,.95:220.}
        bands=rank_bands(x,quantile_ess=ess)
        transformed=rank_bands([math.exp(v) for v in x],quantile_ess=ess)
        for q,t in zip(bands,transformed):
            self.assertEqual(q['lower_index'],t['lower_index'])
            self.assertEqual(q['upper_index'],t['upper_index'])
            for side in ('lower','upper'):
                self.assertEqual(math.exp(q[side]),t[side])
        for truth in [-3.,-1.,0.,1.,3.,*[q[s] for q in bands for s in ('lower','upper')]]:
            self.assertEqual(classify_rank_bands(dict(truth=truth,rank_bands=bands)),
                classify_rank_bands(dict(truth=math.exp(truth),rank_bands=transformed)))
        for side in ('lower','upper'):
            self.assertIsNone(classify_rank_bands(dict(truth=bands[1][side],rank_bands=bands))['below_median'])

    def test_partial_information_can_prove_exclusion(self):
        bands=[dict(probability=p,lower=None,upper=None) for p in (.05,.5,.95)]
        self.assertEqual(classify_rank_bands(dict(truth=0.,rank_bands=bands)),dict(below_median=None,covered_90=None))
        bands[2].update(lower=1.,upper=2.)
        self.assertFalse(classify_rank_bands(dict(truth=3.,rank_bands=bands))['covered_90'])
        self.assertIsNone(classify_rank_bands(dict(truth=0.,rank_bands=bands))['covered_90'])

    def test_reference_integration_closed_form(self):
        ref={p:float(norm.ppf(p)) for p in (.05,.5,.95)}
        bands=[dict(probability=p,lower=q-.1,upper=q+.1) for p,q in ref.items()]
        r=rank_classification_error_mass(bands,reference_quantiles=ref,cdf=norm.cdf)
        self.assertEqual(r['below_median']['resolved_wrong'],0)
        self.assertEqual(r['covered_90']['resolved_wrong'],0)
        self.assertAlmostEqual(r['below_median']['unresolved'],norm.cdf(.1)-norm.cdf(-.1))
        self.assertAlmostEqual(r['covered_90']['unresolved'],sum(norm.cdf(ref[p]+.1)-norm.cdf(ref[p]-.1) for p in (.05,.95)))

    def test_input_validation(self):
        for n,p,ess,z in ((True,.5,100,2),(0,.5,100,2),(10,0,10,2),(10,.5,True,2),
                           (10,.5,10,0),(10,.5,10,100),(10,.5,10,float('nan'))):
            with self.assertRaises(ValueError):rank_band_indices(n,p,ess=ess,multiplier=z)
        for draws in ([],[True],[float('inf')]):
            with self.assertRaises(ValueError):rank_bands(draws,quantile_ess={.05:10,.5:10,.95:10})
        bands=rank_bands(list(range(20)),quantile_ess={.05:10,.5:10,.95:10})
        for truth in (True,None,float('nan')):
            with self.assertRaises(ValueError):classify_rank_bands(dict(truth=truth,rank_bands=bands))
        impossible=[dict(probability=.05,lower=10.,upper=20.),dict(probability=.5,lower=0.,upper=1.),
                    dict(probability=.95,lower=30.,upper=40.)]
        with self.assertRaises(ValueError):classify_rank_bands(dict(truth=5.,rank_bands=impossible))

    def test_opt_in_summary_keeps_missing_and_failed_attempts(self):
        bands=rank_bands([j/100-2 for j in range(401)],quantile_ess={p:400 for p in (.05,.5,.95)})
        row=dict(parameter='x',truth=-3.,rank_bands=bands)
        records=[dict(id=str(i),qualified=True,rows=[row]) for i in range(40)]
        records.append(dict(id='failed',qualified=False,rows=None))
        result=summarize(records,ids=[r['id'] for r in records]+['absent'],names=['x'],classification_method='rank_band')
        self.assertEqual(result['planned'],42)
        self.assertEqual(result['absent_ids'],['absent'])
        self.assertEqual(result['classification_method'],'rank_band')
        self.assertEqual(result['rows'][0]['tests']['below_median_high']['unresolved'],2)
        self.assertTrue(result['rows'][0]['tests']['below_median_high']['detected_departure'])
        self.assertTrue(result['rows'][0]['tests']['covered_90_low']['detected_departure'])
        self.assertFalse(result['scientific_acceptance'])
        self.assertFalse(result['finite_mcmc_error_control_verified'])
        with self.assertRaises(ValueError):summarize(records,ids=['0'],names=['x'],classification_method='unknown')

if __name__=='__main__':unittest.main()
