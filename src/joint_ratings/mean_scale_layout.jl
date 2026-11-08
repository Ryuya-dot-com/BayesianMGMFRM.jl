module MeanScaleLayout
using LinearAlgebra
import LogDensityProblems as L
import ..AssociationKernel as C
function helmert(n)
    H=zeros(n,n-1)
    for j in 1:n-1
        H[1:j,j].=1/sqrt(j*(j+1));H[j+1,j]=-j/sqrt(j*(j+1))
    end
    H
end

struct Target{T}
    original::T
    hp::Matrix{Float64}
    ht::Matrix{Float64}
    person::UnitRange{Int}
    task::UnitRange{Int}
    difference::UnitRange{Int}
    tail::UnitRange{Int}
end
function Target(t::C.Target)
    P,T=t.base.sizes;b=t.base.blocks
    b.person_white==1:2P && b.task==2P+1:2P+2T || error("unexpected source layout")
    p=1:2(P-1);w=last(p)+1:last(p)+2(T-1);d=last(w)+1:last(w)+2
    Target(t,helmert(P),helmert(T),p,w,d,last(d)+1:L.dimension(t)-2)
end
L.dimension(t::Target)=L.dimension(t.original)-2
L.capabilities(::Type{<:Target})=L.LogDensityOrder{1}()
tail(t)=last(t.original.base.blocks.task)+1:L.dimension(t.original)

function gaussian_logpdf(x,sd=1.)
    -length(x)*(log(2pi)/2+log(sd))-sum(abs2,x)/(2sd^2)
end
end
