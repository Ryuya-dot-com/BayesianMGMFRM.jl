using Test, Statistics
include(joinpath(@__DIR__,"..","scripts","mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
output=only(ARGS)
records=NamedTuple[]
@testset "Finite predictive sensitivity without a bias guarantee" begin
    ps=[.1 .2 .5 .8; .2 .3 .6 .9; .3 .4 .7 .8; .4 .5 .8 .9]
    blocks=zeros(4,4,1,4)
    for c in 1:4,b in 1:4
        blocks[c,b,1,:]=log.([ps[c,b];fill((1-ps[c,b])/3,3)])
    end
    truth=permutedims(log.([.5,1/6,1/6,1/6]))
    r=E.predictive_resolution(blocks,truth;categories=[1],weights=[.2])
    @test [p.draws_per_chain for p in r.prefixes]==[250,500,1000]
    @test [p.n_draws for p in r.prefixes]==[1000,2000,4000]
    @test r.rows[1].prefix_losses≈[-.2log(mean(ps[:,1:k])) for k in [1,2,4]]
    @test r.rows[2].prefix_losses≈[.2*(4/3)*(mean(ps[:,1:k])-.5)^2 for k in [1,2,4]]
    @test r.rows[3].prefix_losses≈[.8*(mean(ps[:,1:k])-.5)^2 for k in [1,2,4]]
    @test r.rows[1].early_half_loss≈-.2log(mean(ps[:,1:2]))
    @test r.rows[1].late_half_loss≈-.2log(mean(ps[:,3:4]))
    @test r.rows[1].late_minus_early≈.2log(mean(ps[:,1:2])/mean(ps[:,3:4]))
    @test r.rows[1].prefix_minus_full[end]==0
    @test all(x -> x.status===:observed_sensitivity_only,r.rows)
    @test !r.nested_prefixes_independent && !r.halves_independent && !r.bias_bound_available
    @test !r.numerical_precision_accepted && !r.scientific_acceptance && !r.automatic_extension
    # Permuting chains preserves every result; reversing time preserves only full means.
    perm=E.predictive_resolution(blocks[[4,2,1,3],:,:,:],truth;categories=[1],weights=[.2])
    rev=E.predictive_resolution(blocks[:,4:-1:1,:,:],truth;categories=[1],weights=[.2])
    @test perm.rows[1].prefix_losses≈r.rows[1].prefix_losses
    @test rev.rows[1].full_loss≈r.rows[1].full_loss
    @test rev.rows[1].late_minus_early≈-r.rows[1].late_minus_early
    @test rev.rows[1].prefix_losses[1]!=r.rows[1].prefix_losses[1]
    # Equal observed blocks do not detect an unvisited rare high-probability state.
    constant=copy(blocks)
    for c in 1:4,b in 1:4;constant[c,b,1,:]=log.([.00001;fill(.99999/3,3)]);end
    unseen=E.predictive_resolution(constant,truth;categories=[1],weights=[1.])
    @test maximum(abs,unseen.rows[1].prefix_minus_full)<1e-12
    @test abs(unseen.rows[1].late_minus_early)<1e-12
    @test unseen.rows[1].full_loss-(-log(.001*.9+.999*.00001))>4
    @test !unseen.bias_bound_available
    wrong=copy(blocks);wrong[1,1,1,:].=log(.5)
    @test_throws ArgumentError E.predictive_resolution(wrong,truth;categories=[1],weights=[.2])
    @test_throws ArgumentError E.predictive_resolution(blocks[1:3,:,:,:],truth;categories=[1],weights=[.2])
    zero=copy(blocks);zero[:,1,1,1].=-Inf
    zero[:,1,1,2:4].=-log(3)
    z=E.predictive_resolution(zero,truth;categories=[1],weights=[.2])
    @test z.rows[1].status===:nonfinite_sensitivity && isfinite(z.rows[1].full_loss)
    @test_throws ArgumentError E.predictive_blocks(nothing,zeros(1000,1);
        chain_ids=repeat(1:4;inner=250),iterations=repeat(1:250,4))
    @test_throws ArgumentError E.predictive_blocks(nothing,zeros(4000,1);
        chain_ids=repeat(1:4;inner=1000),iterations=ones(Int,4000))
    push!(records,(;sensitivity=r,unvisited_tail=unseen))
end
E.P.writejson(output,(;tests_passed=true,records,new_sampler_runs=0,cv_refits=0,scientific_acceptance=false))
