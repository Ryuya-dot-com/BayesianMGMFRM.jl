# Declared correlated or independent intercept/multi-slope blocks per named owner.
# K=1 retains the exact original record layout and parameter naming for saved-producer parity.
slope_blocks(t)=hasproperty(t.specification,:random_slopes) ? t.specification.random_slopes : ()
_sb_is_multi(b)=hasproperty(b,:columns)
_sb_cols(b)=_sb_is_multi(b) ? b.columns : (b.column,)
_sb_raws(b)=_sb_is_multi(b) ? b.raws : (b.raw,)
_sb_hyps(b)=_sb_is_multi(b) ? b.hyps : (b.hyper,)
_sb_scales(b)=_sb_is_multi(b) ? b.scales : (b.scale,)
_sb_corr_range(b)=b.corr_raw isa UnitRange ? b.corr_raw : (b.corr_raw==0 ? (1:0) : (b.corr_raw:b.corr_raw))

function _corr_pair_name(owner::Symbol,cols::Tuple,i::Int,j::Int)
    j==1 ? "correlation[$owner,intercept,$(cols[i-1])]" : "correlation[$owner,$(cols[j-1]),$(cols[i-1])]"
end

function slope_population(population,allow)
    out=Pair{Symbol,Any}[];specs=Pair{Symbol,Any}[]
    for (owner,p) in pairs(population)
        if p isa NamedTuple
            allow || throw(ArgumentError("structured population slopes require scalar ZOIB or count models"))
            _keys(p,(:intercept,:slopes,:correlation),:population_slope)
            p.slopes isa NamedTuple && !isempty(p.slopes) || throw(ArgumentError("declare at least one slope column in slopes"))
            cols=Tuple(keys(p.slopes))
            scales=Tuple(_population_parameters(getproperty(p.slopes,c),c) for c in cols)
            D_dim=length(cols)+1
            cp=p.correlation
            corr=if cp isa D.LKJ
                dim,eta=D.params(cp);isfinite(eta) && eta>0 || throw(ArgumentError("LKJ shape must be positive and finite"))
                dim==D_dim || throw(ArgumentError("intercept plus $(length(cols)) slope(s) needs LKJ($D_dim, eta)"))
                (;kind=:lkj,eta=Float64(eta))
            elseif cp isa Real && !(cp isa Bool) && cp==0
                (;kind=:fixed,value=0.)
            else
                throw(ArgumentError("correlation must be LKJ($D_dim, eta) or numeric zero for independence"))
            end
            push!(out,owner=>p.intercept);push!(specs,owner=>(;columns=cols,scales,correlation=corr))
        else
            push!(out,owner=>p)
        end
    end
    (;out...),specs
end

function compile_slopes(identity,raw,table,terms,residuals,specs,offset)
    blocks=NamedTuple[];n=length(identity.person)
    for (owner,p) in specs
        cols=p.columns;scales=p.scales
        for c in cols
            count(t->t.owner===:response && t.column===c && t.by===nothing,terms)==1 ||
                throw(ArgumentError("random slope $owner.$c requires one common response coefficient for that column"))
        end
        m=length(_owner_levels(identity,owner));m>=2 || throw(ArgumentError("random slopes need at least two owner levels"))
        r=only(filter(r->r.name===owner,residuals))
        if length(cols)==1
            c=only(cols);sp=only(scales)
            z=offset+1:offset+m;offset+=m
            h=0;j=0
            sp.kind===:lognormal && (offset+=1;h=offset)
            p.correlation.kind===:lkj && (offset+=1;j=offset)
            push!(blocks,(;owner,column=c,raw=z,intercept_raw=r.raw,hyper=h,corr_raw=j,scale=sp,correlation=p.correlation))
        else
            K=length(cols);D_dim=K+1
            raws=Vector{UnitRange{Int}}(undef,K)
            hyps=zeros(Int,K)
            for k in 1:K
                raws[k]=offset+1:offset+m;offset+=m
            end
            for k in 1:K
                scales[k].kind===:lognormal && (offset+=1;hyps[k]=offset)
            end
            n_corr=p.correlation.kind===:lkj ? (D_dim*(D_dim-1))÷2 : 0
            cr=n_corr>0 ? (offset+1:offset+n_corr) : (1:0)
            offset+=n_corr
            push!(blocks,(;owner,columns=cols,raws=Tuple(raws),intercept_raw=r.raw,hyps=Tuple(hyps),corr_raw=cr,scales,correlation=p.correlation))
        end
    end
    Tuple(blocks),offset
end

function slope_population_restore(s)
    pop=Dict{Symbol,Any}(k=>(v.kind===:fixed ? v.sd : D.LogNormal(v.logmean,v.logsd)) for (k,v) in pairs(s.population))
    for b in (hasproperty(s,:random_slopes) ? s.random_slopes : ())
        cols=_sb_cols(b);scales=_sb_scales(b);cr=_sb_corr_range(b);D_dim=length(cols)+1
        spairs=Pair{Symbol,Any}[c=>(sc.kind===:fixed ? sc.sd : D.LogNormal(sc.logmean,sc.logsd)) for (c,sc) in zip(cols,scales)]
        corr=isempty(cr) ? 0. : D.LKJ(D_dim,b.correlation.eta)
        pop[b.owner]=(;intercept=pop[b.owner],slopes=(;spairs...),correlation=corr)
    end
    (;(k=>pop[k] for k in keys(s.population))...)
end

_logsech2(a)=2*(log(2)-_softplus(2a)+a)

function _cholesky_cpc(q,cr::UnitRange{Int},D_dim::Int)
    Z=promote_type(Float64,eltype(q))
    L=zeros(Z,D_dim,D_dim)
    for i in 1:D_dim;L[i,i]=one(Z);end
    isempty(cr) && return L,zero(Z),zero(Z)
    log_diag_sum=zero(Z)
    log_corr_jac=zero(Z)
    k=0
    for i in 2:D_dim
        log_rem=zero(Z)
        for j in 1:(i-1)
            k+=1;a=q[cr[k]]
            u=tanh(a);ls=_logsech2(a)
            L[i,j]=u*exp(log_rem/2)
            log_corr_jac+=(1.0+(D_dim-1-j)/2)*ls
            log_rem+=ls
        end
        diag_ij=exp(log_rem/2)
        isfinite(diag_ij) && diag_ij>zero(Z) || throw(ArgumentError("unrepresentable slope correlation Cholesky factor"))
        L[i,i]=diag_ij
        log_diag_sum+=log_rem/2
    end
    L,log_diag_sum,log_corr_jac
end

function slope_coordinates(t,q)
    Z=promote_type(Float64,eltype(q))
    map(slope_blocks(t)) do b
        if !_sb_is_multi(b)
            s=b.hyper==0 ? Z(b.scale.sd) : exp(b.scale.logmean+b.scale.logsd*q[b.hyper])
            a=b.corr_raw==0 ? zero(Z) : Z(q[b.corr_raw])
            rho=tanh(a);lc=_logsech2(a)/2;c=exp(lc)
            isfinite(s) && s>0 && c>0 || throw(ArgumentError("unrepresentable slope scale/correlation"))
            v=s.*(rho.*view(q,b.intercept_raw).+c.*view(q,b.raw))
            lv=length(b.raw)*(log(s)+lc)+(b.hyper==0 ? zero(s) : log(b.scale.logsd)+log(s))+
                (b.corr_raw==0 ? zero(s) : 2lc)
            return (;values=v,sd=s,rho,complement=c,log_volume=lv)
        end
        cols=b.columns;raws=b.raws;hyps=b.hyps;scales=b.scales;cr=b.corr_raw
        K=length(cols);D_dim=K+1;m=length(b.intercept_raw)
        sds=Vector{Z}(undef,K)
        lv_sd=zero(Z)
        for k in 1:K
            sk=hyps[k]==0 ? Z(scales[k].sd) : exp(scales[k].logmean+scales[k].logsd*q[hyps[k]])
            isfinite(sk) && sk>zero(Z) || throw(ArgumentError("unrepresentable slope scale"))
            sds[k]=sk
            lv_sd+=m*log(sk)+(hyps[k]==0 ? zero(Z) : log(scales[k].logsd)+log(sk))
        end
        L,log_diag_sum,log_corr_jac=_cholesky_cpc(q,cr,D_dim)
        vals=Vector{Vector{Z}}(undef,K)
        z0=view(q,b.intercept_raw)
        for k in 1:K
            i=k+1
            wi=L[i,1].*z0
            for j in 2:i
                wi.+=L[i,j].*view(q,raws[j-1])
            end
            vals[k]=sds[k].*wi
        end
        R=L*transpose(L)
        corrs=Z[R[i,j] for i in 2:D_dim for j in 1:(i-1)]
        lv=lv_sd+m*log_diag_sum+log_corr_jac
        (;values=Tuple(vals),sds=Tuple(sds),L,R,correlations=corrs,log_volume=lv)
    end
end

function slope_prior(t,q)
    half_log2pi=log(2pi)/2
    lp=-length(q)*half_log2pi-sum(abs2,q)/2
    for b in slope_blocks(t)
        cr=_sb_corr_range(b);isempty(cr) && continue
        D_dim=length(_sb_cols(b))+1;eta=b.correlation.eta;k=0
        for i in 2:D_dim,j in 1:(i-1)
            k+=1;a=q[cr[k]];alpha=eta+(D_dim-1-j)/2
            lp+=a^2/2+half_log2pi+alpha*_logsech2(a)-SF.logbeta(.5,alpha)
        end
    end
    lp
end

function location_prior_draw(t,rng)
    q=randn(rng,t.dimension)
    for b in slope_blocks(t)
        cr=_sb_corr_range(b);isempty(cr) && continue
        D_dim=length(_sb_cols(b))+1;eta=b.correlation.eta;k=0
        for i in 2:D_dim,j in 1:(i-1)
            k+=1;alpha=eta+(D_dim-1-j)/2
            rho=2rand(rng,D.Beta(alpha,alpha))-1
            abs(rho)<1 || throw(ArgumentError("LKJ draw rounded to boundary; review correlation prior"))
            q[cr[k]]=atanh(rho)
        end
    end
    q
end

function logprior(t::BoundedTarget,q)
    _check(t,q);slope_prior(t,q)
end
function prior_draw(t::BoundedTarget;seed=1)
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) || throw(ArgumentError("invalid seed"))
    location_prior_draw(t,MersenneTwister(Int(seed)))
end

function slope_eta(t,v,n)
    e=zero(eltype(v.person))
    for (b,s) in zip(slope_blocks(t),v.random_slopes)
        sgn=b.owner===:person ? 1 : -1
        idx=_owner_index(t,b.owner)[n]
        if !_sb_is_multi(b)
            e+=sgn*s.values[idx]*t.table[b.column][n]
        else
            for (k,col) in enumerate(b.columns)
                e+=sgn*s.values[k][idx]*t.table[col][n]
            end
        end
    end
    e
end

function _slope_block_pullback!(g,q,b,s,hs)
    Z=eltype(g)
    if !_sb_is_multi(b)
        h=only(hs);z0=view(q,b.intercept_raw);z1=view(q,b.raw)
        g[b.intercept_raw].+=s.sd*s.rho.*h
        g[b.raw].+=s.sd*s.complement.*h
        b.hyper==0 || (g[b.hyper]+=b.scale.logsd*dot(h,s.values))
        b.corr_raw==0 || (g[b.corr_raw]=-2b.correlation.eta*s.rho+
            s.sd*dot(h,s.complement^2 .*z0.-s.rho*s.complement.*z1))
        return g
    end
    cols=b.columns;raws=b.raws;hyps=b.hyps;scales=b.scales;cr=b.corr_raw
    K=length(cols);D_dim=K+1;m=length(b.intercept_raw);L=s.L
    wbar=[s.sds[k].*hs[k] for k in 1:K]
    for k in 1:K
        hyps[k]==0 || (g[hyps[k]]+=scales[k].logsd*dot(hs[k],s.values[k]))
    end
    for p in 1:m
        acc0=zero(Z)
        for i in 2:D_dim;acc0+=L[i,1]*wbar[i-1][p];end
        g[b.intercept_raw[p]]+=acc0
        for j in 2:D_dim
            accj=zero(Z)
            for i in j:D_dim;accj+=L[i,j]*wbar[i-1][p];end
            g[raws[j-1][p]]+=accj
        end
    end
    if !isempty(cr)
        z_vecs=(view(q,b.intercept_raw),(view(q,raws[k]) for k in 1:K)...)
        Lbar=zeros(Z,D_dim,D_dim)
        for i in 2:D_dim,j in 1:i
            Lbar[i,j]=dot(wbar[i-1],z_vecs[j])
        end
        eta=b.correlation.eta;k_off=0
        for i in 2:D_dim
            len_i=i-1
            us=Vector{Z}(undef,len_i);cs=Vector{Z}(undef,len_i);rs=Vector{Z}(undef,len_i)
            r_cur=one(Z)
            for j in 1:len_i
                a=q[cr[k_off+j]]
                u=tanh(a);c=exp(_logsech2(a)/2)
                us[j]=u;cs[j]=c;rs[j]=r_cur
                r_cur*=c
            end
            rbar=Lbar[i,i]
            for j in len_i:-1:1
                alpha=eta+(D_dim-1-j)/2
                g_corr=rs[j]*cs[j]*(Lbar[i,j]*cs[j]-rbar*us[j])
                g[cr[k_off+j]]=-2*alpha*us[j]+g_corr
                rbar=Lbar[i,j]*us[j]+rbar*cs[j]
            end
            k_off+=len_i
        end
    end
    g
end

function slope_gradient!(g,t,q,v,gs)
    for (b,s,hs) in zip(slope_blocks(t),v.random_slopes,gs)
        _slope_block_pullback!(g,q,b,s,hs)
    end
    g
end

function slope_model_values(v)
    hasproperty(v,:random_slopes) || return Float64[]
    out=eltype(v.person)[]
    for s in v.random_slopes
        if hasproperty(s,:sds)
            for k in eachindex(s.sds)
                append!(out,s.values[k]);push!(out,s.sds[k])
            end
            append!(out,s.correlations)
        else
            append!(out,s.values);push!(out,s.sd);push!(out,s.rho)
        end
    end
    out
end

function slope_fixed_names(t)
    out=Set{String}()
    for b in slope_blocks(t)
        cols=_sb_cols(b);hyps=_sb_hyps(b);cr=_sb_corr_range(b);D_dim=length(cols)+1
        for (c,h) in zip(cols,hyps)
            h==0 && push!(out,"slope_sd[$(b.owner),$c]")
        end
        if isempty(cr)
            if !_sb_is_multi(b)
                push!(out,"correlation[$(b.owner),$(b.column)]")
            else
                for i in 2:D_dim,j in 1:(i-1)
                    push!(out,_corr_pair_name(b.owner,cols,i,j))
                end
            end
        end
    end
    out
end

function slope_names(t,scale)
    out=String[]
    for b in slope_blocks(t)
        if !_sb_is_multi(b)
            append!(out,scale===:raw ? ["slope[$(b.owner),$(b.column)].white[$j]" for j in eachindex(b.raw)] :
                ["slope[$(b.owner),$(b.column),$(repr(id))]" for id in _owner_levels(t,b.owner)])
            (scale===:model || b.hyper>0) && push!(out,"slope_sd[$(b.owner),$(b.column)]"*(scale===:raw ? ".white" : ""))
            (scale===:model || b.corr_raw>0) && push!(out,"correlation[$(b.owner),$(b.column)]"*(scale===:raw ? ".fisher" : ""))
        else
            cols=b.columns;raws=b.raws;hyps=b.hyps;cr=b.corr_raw;D_dim=length(cols)+1
            ids=_owner_levels(t,b.owner)
            if scale===:raw
                for (k,c) in enumerate(cols)
                    append!(out,["slope[$(b.owner),$c].white[$j]" for j in eachindex(raws[k])])
                end
                for (k,c) in enumerate(cols)
                    hyps[k]>0 && push!(out,"slope_sd[$(b.owner),$c].white")
                end
                if !isempty(cr)
                    for i in 2:D_dim,j in 1:(i-1)
                        push!(out,_corr_pair_name(b.owner,cols,i,j)*".fisher")
                    end
                end
            else
                for c in cols
                    append!(out,["slope[$(b.owner),$c,$(repr(id))]" for id in ids])
                    push!(out,"slope_sd[$(b.owner),$c]")
                end
                for i in 2:D_dim,j in 1:(i-1)
                    push!(out,_corr_pair_name(b.owner,cols,i,j))
                end
            end
        end
    end
    out
end

# Gram inner products use O(N) grouped weighted sums, never an observation-square matrix.
function slope_allocation(t,base)
    isempty(slope_blocks(t)) && return base
    kernels=NamedTuple[];one_v=ones(length(t.person));warnings=String[]
    for b in t.residuals
        b.hyper==0 || push!(kernels,(;owner=b.name,label="intercept_variance[$(b.name)]",terms=((one_v,one_v),)))
    end
    for b in slope_blocks(t)
        cols=_sb_cols(b);hyps=_sb_hyps(b);cr=_sb_corr_range(b);ids=_owner_index(t,b.owner)
        m_levels=length(_owner_levels(t,b.owner));K=length(cols);target_rk=K+1
        xs=[t.table[c] for c in cols]
        for (k,c) in enumerate(cols)
            xk=xs[k]
            hyps[k]==0 || push!(kernels,(;owner=b.owner,label="slope_variance[$(b.owner),$c]",terms=((xk,xk),)))
            if !isempty(cr)
                push!(kernels,(;owner=b.owner,label=!_sb_is_multi(b) ? "intercept_slope_covariance[$(b.owner),$c]" : "intercept_slope_covariance[$(b.owner),$c]",terms=((one_v,xk),(xk,one_v))))
                for l in 1:(k-1)
                    xl=xs[l];cl=cols[l]
                    push!(kernels,(;owner=b.owner,label="slope_covariance[$(b.owner),$cl,$c]",terms=((xl,xk),(xk,xl))))
                end
            end
            bad_var=count(j->length(unique(xk[ids.==j]))<2,unique(ids))
            bad_var==0 || push!(warnings,"$bad_var levels of $(b.owner) lack within-owner variation in $c; individual slopes may be prior-dominated.")
        end
        if K>=2
            bad_rk=0;sparse_obs=0
            for j in unique(ids)
                mask=ids.==j;mj=count(mask)
                mj<target_rk+1 && (sparse_obs+=1)
                Xj=hcat(ones(mj),(xk[mask] for xk in xs)...)
                sc=sqrt.(vec(sum(abs2,Xj;dims=1)));Xjn=Xj./reshape(ifelse.(sc.>0,sc,1.),1,:)
                rank(Xjn;rtol=max(size(Xjn)...)*eps(Float64))<target_rk && (bad_rk+=1)
            end
            bad_rk==0 || push!(warnings,"$bad_rk/$m_levels levels of $(b.owner) have local intercept/slope design rank below $target_rk; within-owner slopes are locally collinear or constant.")
            sparse_obs==0 || push!(warnings,"$sparse_obs/$m_levels levels of $(b.owner) have fewer than $(target_rk+1) observations for $target_rk random effects.")
        end
    end
    gram=zeros(length(kernels),length(kernels))
    for (i,a) in enumerate(kernels),(j,b) in enumerate(kernels)
        j<i && continue
        ia=_owner_index(t,a.owner);ib=_owner_index(t,b.owner);val=0.
        for (al,ar) in a.terms,(bl,br) in b.terms
            cells=Dict{Tuple{Int,Int},Tuple{Float64,Float64}}()
            for n in eachindex(ia)
                key=(ia[n],ib[n]);u,v=get(cells,key,(0.,0.));cells[key]=(u+al[n]*bl[n],v+ar[n]*br[n])
            end
            val+=sum(u*v for (u,v) in values(cells))
        end
        gram[i,j]=val;gram[j,i]=val
    end
    zero_diag=any(k->gram[k,k]<=1e-12,eachindex(kernels))
    scales=sqrt.(max.(diag(gram),0.));scales[scales.==0].=1.;normalized=gram./(scales*scales')
    rk=isempty(normalized) ? 0 : rank(normalized;rtol=max(size(normalized)...)*eps(Float64))
    reasons=copy(base.reasons)
    (zero_diag || rk<length(kernels)) && push!(reasons,"Estimated intercept/slope covariance kernels are aliased; slope variation cannot separate the declared components.")
    merge(base,(;identified=isempty(reasons),covariance_rank=zero_diag ? min(rk,length(kernels)-1) : rk,covariance_components=[k.label for k in kernels],normalized_covariance_gram=normalized,reasons,slope_warnings=warnings))
end

function slope_stan_data(t)
    bs=slope_blocks(t);n=length(t.person)
    B_cnt=length(bs)
    block_dim=Int[];block_m=Int[];block_corr_start=Int[];block_corr_len=Int[];block_eta=Float64[]
    slope_col_block=Int[];slope_col_k=Int[];slope_scale=Float64[];slope_hyper=Int[];slope_logmean=Float64[];slope_logsd=Float64[]
    Z_cols=Vector{Float64}[];vec_intercept_raw=Int[];vec_slope_raw=Int[];vec_col_id=Int[]
    c_id=0
    for (b_idx,b) in enumerate(bs)
        cols=_sb_cols(b);raws=_sb_raws(b);hyps=_sb_hyps(b);scales=_sb_scales(b);cr=_sb_corr_range(b)
        K=length(cols);m=length(b.intercept_raw);ids=_owner_index(t,b.owner);sgn=b.owner===:person ? 1. : -1.
        push!(block_dim,K+1);push!(block_m,m)
        push!(block_corr_start,isempty(cr) ? 0 : first(cr));push!(block_corr_len,length(cr))
        push!(block_eta,isempty(cr) ? 1. : b.correlation.eta)
        for k in 1:K
            c_id+=1
            push!(slope_col_block,b_idx);push!(slope_col_k,k)
            push!(slope_scale,hyps[k]==0 ? scales[k].sd : 1.)
            push!(slope_hyper,hyps[k])
            push!(slope_logmean,hyps[k]==0 ? 0. : scales[k].logmean)
            push!(slope_logsd,hyps[k]==0 ? 1. : scales[k].logsd)
            xk=t.table[cols[k]]
            for p in 1:m
                push!(Z_cols,sgn.*xk.*(ids.==p))
                push!(vec_intercept_raw,b.intercept_raw[p])
                push!(vec_slope_raw,raws[k][p])
                push!(vec_col_id,c_id)
            end
        end
    end
    Dict("B"=>B_cnt,"C_sl"=>c_id,"S"=>length(Z_cols),"Z"=>isempty(Z_cols) ? zeros(n,0) : hcat(Z_cols...),
        "block_dim"=>block_dim,"block_m"=>block_m,"block_corr_start"=>block_corr_start,"block_corr_len"=>block_corr_len,"block_eta"=>block_eta,
        "slope_col_block"=>slope_col_block,"slope_col_k"=>slope_col_k,
        "slope_scale"=>slope_scale,"slope_hyper"=>slope_hyper,"slope_logmean"=>slope_logmean,"slope_logsd"=>slope_logsd,
        "slope_intercept_raw"=>vec_intercept_raw,"slope_raw"=>vec_slope_raw,"slope_vec_col"=>vec_col_id)
end
