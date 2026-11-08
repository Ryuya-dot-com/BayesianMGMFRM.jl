module SingleItemDesignRankChecks
using BayesianMGMFRM, Test, LinearAlgebra
const B=BayesianMGMFRM

function exact_rank(A)
    M=Rational{BigInt}.(Int.(A));r=0
    for j in axes(M,2)
        pivot=0
        for i in (r+1):size(M,1)
            if !iszero(M[i,j]);pivot=i;break;end
        end
        pivot==0 && continue
        r+=1;M[[r,pivot],:]=M[[pivot,r],:];M[r,:]./=M[r,j]
        for i in (r+1):size(M,1);M[i,:].-=M[i,j].*M[r,:];end
        r==size(M,1) && break
    end
    r
end

function data(edges;items=fill("overall",length(edges)))
    B.FacetData((;person=["p$(e[1])" for e in edges],rater=["r$(e[2])" for e in edges],
        item=items,score=[mod(n,3) for n in eachindex(edges)]);person=:person,rater=:rater,item=:item,score=:score,category_levels=0:2)
end

function check_rank(d;single=true)
    matrix=B._minimal_location_matrix(d);r=exact_rank(matrix);ncol=size(matrix,2)
    @test rank(matrix)==r
    single && (@test B._single_item_location_rank(d)==r)
    issues=B.ValidationIssue[];B._validate_minimal_location_rank!(issues,d)
    if r==ncol
        @test isempty(issues)
    else
        @test length(issues)==1 && only(issues).code===:rank_deficient_design
        @test only(issues).context==Dict(:rank=>r,:parameters=>ncol,:deficiency=>ncol-r)
    end
end

function checks()
    @testset "Exact one-item incidence rank" begin
        edges=collect(Iterators.product(1:3,1:3))[:]
        for mask in 1:511
            selected=[edges[j] for j in eachindex(edges) if mask & (1<<(j-1)) != 0]
            check_rank(data(selected))
        end
        for selected in ([(1,1),(2,2)],[(1,1),(2,1),(3,1)],[(1,1),(1,2),(1,3)])
            check_rank(data(vcat(selected,reverse(selected))))
        end
        disconnected=data([(1,1),(2,2)])
        @test length(B._connected_components(disconnected))==1
        report=B.validate_design(disconnected)
        @test !report.passed && any(x->x.code===:rank_deficient_design,report.issues)
        for (edges,items) in (([(1,1),(2,2)],["a","b"]),
                ([(1,1),(2,2),(1,2),(2,1)],["a","a","b","b"]))
            check_rank(data(edges;items);single=false)
        end
    end
end
end
