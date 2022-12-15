struct OperatorAssumptions{issquare} end
function OperatorAssumptions(issquare = nothing)
    issquare = something(_unwrap_val(issquare), Nothing)
    OperatorAssumptions{issquare}()
end
issquare(::OperatorAssumptions{issq}) where {issq} = issq

struct LinearCache{TA, Tb, Tu, Tp, Talg, Tc, Tl, Tr, Ttol, issquare}
    A::TA
    b::Tb
    u::Tu
    p::Tp
    alg::Talg
    cacheval::Tc  # store alg cache here. for abstract factorization, this is something backslashable.
    isfresh::Bool # false => cacheval is set wrt A, true => update cacheval wrt A
    Pl::Tl        # preconditioners
    Pr::Tr
    abstol::Ttol
    reltol::Ttol
    maxiters::Int
    verbose::Bool
    assumptions::OperatorAssumptions{issquare}
end

"""
$(SIGNATURES)
"""
function set_A(cache::LinearCache, A)
    @set! cache.A = A
    @set! cache.isfresh = true
    return cache
end

"""
$(SIGNATURES)
"""
function set_b(cache::LinearCache, b)
    @set! cache.b = b
    return cache
end

"""
$(SIGNATURES)
"""
function set_u(cache::LinearCache, u)
    @set! cache.u = u
    return cache
end

"""
$(SIGNATURES)
"""
function set_p(cache::LinearCache, p)
    @set! cache.p = p
    #   @set! cache.isfresh = true
    return cache
end

"""
$(SIGNATURES)
"""
function set_prec(cache, Pl, Pr)
    @set! cache.Pl = Pl
    @set! cache.Pr = Pr
    return cache
end

function set_cacheval(cache::LinearCache, alg_cache)
    if cache.isfresh
        @set! cache.cacheval = alg_cache
        @set! cache.isfresh = false
    end
    return cache
end

init_cacheval(alg::SciMLLinearSolveAlgorithm, args...) = nothing

function SciMLBase.init(prob::LinearProblem, args...; kwargs...)
    SciMLBase.init(prob, nothing, args...; kwargs...)
end

default_tol(::Type{T}) where {T} = √(eps(T))
default_tol(::Type{Complex{T}}) where {T} = √(eps(T))
default_tol(::Type{<:Rational}) = 0
default_tol(::Type{<:Integer}) = 0
default_tol(::Type{Any}) = 0

function SciMLBase.init(prob::LinearProblem, alg::Union{SciMLLinearSolveAlgorithm, Nothing},
                        args...;
                        alias_A = false, alias_b = false,
                        abstol = default_tol(eltype(prob.A)),
                        reltol = default_tol(eltype(prob.A)),
                        maxiters::Int = length(prob.b),
                        verbose::Bool = false,
                        Pl = Identity(),
                        Pr = Identity(),
                        assumptions = OperatorAssumptions(),
                        kwargs...)
    @unpack A, b, u0, p = prob

    u0 = if u0 !== nothing
        u0
    else
        u0 = similar(b, size(A, 2))
        fill!(u0, false)
    end

    cacheval = init_cacheval(alg, A, b, u0, Pl, Pr, maxiters, abstol, reltol, verbose,
                             assumptions)
    isfresh = true
    Tc = typeof(cacheval)

    A = alias_A ? A : deepcopy(A)
    b = alias_b ? b : deepcopy(b)

    cache = LinearCache{
                        typeof(A),
                        typeof(b),
                        typeof(u0),
                        typeof(p),
                        typeof(alg),
                        Tc,
                        typeof(Pl),
                        typeof(Pr),
                        typeof(reltol),
                        issquare(assumptions)
                        }(A,
                          b,
                          u0,
                          p,
                          alg,
                          cacheval,
                          isfresh,
                          Pl,
                          Pr,
                          abstol,
                          reltol,
                          maxiters,
                          verbose,
                          assumptions)
    return cache
end

function SciMLBase.solve(prob::LinearProblem, args...; kwargs...)
    solve(init(prob, nothing, args...; kwargs...))
end

function SciMLBase.solve(prob::LinearProblem,
                         alg::Union{SciMLLinearSolveAlgorithm, Nothing},
                         args...; kwargs...)
    solve(init(prob, alg, args...; kwargs...))
end

function SciMLBase.solve(cache::LinearCache, args...; kwargs...)
    solve(cache, cache.alg, args...; kwargs...)
end
