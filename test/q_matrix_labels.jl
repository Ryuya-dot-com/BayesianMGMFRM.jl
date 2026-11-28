using BayesianMGMFRM, Test

@testset "Labeled Q rows map one-to-one to observed items" begin
    items = Any[1, "1", "A", "B", "C"]
    grid = vec(collect(Iterators.product(1:6, eachindex(items), 1:3)))
    data = FacetData((person=first.(grid), item=[items[i] for (_, i, _) in grid],
        rater=last.(grid), score=[mod(p+i+r, 3) for (p,i,r) in grid]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=0:2)
    expected = Bool[1 0; 0 1; 1 0; 0 1; 1 1]
    spec(q) = mfrm_spec(data; family=:mgmfrm, dimensions=2, q_matrix=q)
    order = [4, 2, 5, 1, 3]
    for as_input in (
            (keys, rows) -> (items=keys, matrix=rows),
            (keys, rows) -> [k => row for (k,row) in zip(keys, eachrow(rows))],
            (keys, rows) -> Dict{Any,Any}(k => row for (k,row) in zip(keys, eachrow(rows))),
        )
        # Symbols remain usable as aliases for unambiguous string IDs.
        labels = Any[1, "1", :A, :B, :C]
        @test spec(as_input(labels[order], expected[order,:])).q_matrix == expected
        labels[2] = "UNOBSERVED"
        @test_throws ArgumentError spec(as_input(labels, expected))
    end
    @test_throws ArgumentError spec((items=[1, 1, "A", "B", "C"], matrix=expected))
end
