module PosteriorDirectionChecks
using BayesianMGMFRM, Test
const B=BayesianMGMFRM

function checks()
    @testset "Direction frequencies and exact historical cache compatibility" begin
        # Fixed counts, not simulated posterior draws.
        @test 1 - 8/10 - 2/10 < 0
        @test 1 - 1/3 - 2/3 > 0
        for reference in (0.,2.), (positive,negative,ties) in
                ((8,2,0),(1,2,0),(6,3,1),(0,0,3),(1,0,0),(0,1,0),(2,2,2))
            values=[fill(reference+1,positive);fill(reference-1,negative);fill(reference,ties)]
            n=length(values);d=B._posterior_direction_summary(values,reference)
            @test d.probability_positive==positive/n
            @test d.probability_negative==negative/n
            @test d.probability_equal==ties/n
            @test 0 <= d.probability_equal <= 1
            @test d.probability_of_direction==max(positive,negative)/n
            @test d.direction== (positive==negative ? :undetermined : positive>negative ? :positive : :negative)
            @test d.probability_positive+d.probability_negative+d.probability_equal ≈ 1
            rows=B._posterior_summary_rows(reshape(values,:,1),["fixed counts"];
                lower=.05,upper=.95,intervals=(.9,),reference,rope=(-1.,3.),rope_probability_threshold=.95)
            row=only(rows);old_equal=1-row.probability_positive-row.probability_negative
            old=merge(row,(;probability_equal=old_equal))
            @test row.probability_equal==ties/n
            @test B._fit_cache_summary_rows_equal([old],rows)
            @test B._fit_cache_summary_rows_equal(rows,rows)
            @test old.probability_equal===old_equal
            for bad in (NaN,Inf,-.1,1.1,nextfloat(old_equal),prevfloat(old_equal))
                bad==row.probability_equal && continue
                @test !B._fit_cache_summary_rows_equal([merge(old,(;probability_equal=bad))],rows)
            end
            for change in ((;probability_positive=nextfloat(row.probability_positive)),
                    (;probability_negative=nextfloat(row.probability_negative)),
                    (;reference=nextfloat(reference)),(;lower=nextfloat(row.lower)),
                    (;n_draws=n+1),(;parameter="changed"))
                @test !B._fit_cache_summary_rows_equal([merge(old,change)],rows)
            end
        end
        @test B._posterior_direction_summary([-0.,0.],0.).probability_equal==1
    end
end
end
