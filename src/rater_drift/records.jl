module RaterDriftRecords
using SHA, LinearAlgebra
const Parent=parentmodule(@__MODULE__)
const B=Parent.B
const M=Parent.M
digest(path)=bytes2hex(sha256(read(path)))
seal(body)=merge(body,(;content_hash=B._cache_hash(body)))

const TargetRecord=typeof((;P=0,R=0,K=0,person=Int[],rater=Int[],time=Int[],score=Int[],
    event=String[],person_labels=String[],rater_labels=String[],time_ticks=Int[],
    time_labels=String[],time_unit="",mu_sigma=0.,parameterization="",static=false))
const Context=typeof((;julia="",kernel="",arch="",threads=0,blas_threads=0,
    project_sha256="",manifest_sha256="",package_sha256="",target_sha256="",adapter_sha256=""))
function package_sources()
    root=dirname(dirname(pathof(B)))
    files=sort([joinpath(d,f) for branch in ("src","ext")
        for (d,_,fs) in walkdir(joinpath(root,branch)) for f in fs if endswith(f,".jl")])
    [(;path=relpath(f,root),sha256=digest(f)) for f in files]
end

function context()
    project=Base.active_project()
    project!==nothing || throw(ArgumentError("an explicit project is required"))
    # Bind all available manifest selections; do not silently choose a new environment.
    manifests=sort(filter(p->occursin(r"^Manifest.*\.toml$",basename(p)),readdir(dirname(project);join=true)))
    !isempty(manifests) || throw(ArgumentError("a retained Manifest is required"))
    (;julia=string(VERSION),kernel=string(Sys.KERNEL),arch=string(Sys.ARCH),
      threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads(),project_sha256=digest(project),
      manifest_sha256=B._cache_hash([(;name=basename(p),sha256=digest(p)) for p in manifests]),
      package_sha256=B._cache_hash(package_sources()),
      target_sha256=digest(joinpath(@__DIR__,"target.jl")),adapter_sha256=digest(@__FILE__))
end

target_record(t)=(;P=t.P,R=t.R,K=t.K,person=copy(t.person),rater=copy(t.rater),
    time=copy(t.time),score=copy(t.score),event=copy(t.event),person_labels=copy(t.person_labels),
    rater_labels=copy(t.rater_labels),time_ticks=copy(t.time_ticks),time_labels=copy(t.time_labels),
    time_unit=t.time_unit,mu_sigma=t.mu_sigma,parameterization=String(t.parameterization),static=t.static)
target(s)=M.Target(;merge(s,(;parameterization=Symbol(s.parameterization)))...)


panel_status(args...)=Parent._panel_status(args...)
write_json(path,x)=B._write_json_record(path,x)
end
