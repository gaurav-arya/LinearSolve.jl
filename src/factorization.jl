_ldiv!(x, A, b) = ldiv!(x, A, b)
function _ldiv!(x::Vector, A::Factorization, b::Vector)
    # workaround https://github.com/JuliaLang/julia/issues/43507
    copyto!(x, b)
    ldiv!(A, x)
end

function SciMLBase.solve(cache::LinearCache, alg::AbstractFactorization; kwargs...)
    if cache.isfresh
        fact = do_factorization(alg, cache.A, cache.b, cache.u) # is this run too often? + can this mutate b?
        cache = set_cacheval(cache, fact)
    end
    y = _ldiv!(cache.u, cache.cacheval, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

#RF Bad fallback: will fail if `A` is just a stand-in
# This should instead just create the factorization type.
function init_cacheval(alg::AbstractFactorization, A, b, u, Pl, Pr, maxiters::Int, abstol,
                       reltol, verbose::Bool, assumptions::OperatorAssumptions)
    do_factorization(alg, A, b, u)
end

## LU Factorizations

struct LUFactorization{P} <: AbstractFactorization
    pivot::P
end

struct GenericLUFactorization{P} <: AbstractFactorization
    pivot::P
end

function LUFactorization()
    pivot = @static if VERSION < v"1.7beta"
        Val(true)
    else
        RowMaximum()
    end
    LUFactorization(pivot)
end

function GenericLUFactorization()
    pivot = @static if VERSION < v"1.7beta"
        Val(true)
    else
        RowMaximum()
    end
    GenericLUFactorization(pivot)
end

function do_factorization(alg::LUFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    if A isa SparseMatrixCSC
        return lu(A)
    else
        fact = lu!(A, alg.pivot)
    end
    return fact
end

function do_factorization(alg::GenericLUFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = LinearAlgebra.generic_lufact!(A, alg.pivot)
    return fact
end

function init_cacheval(alg::Union{LUFactorization, GenericLUFactorization}, A, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(convert(AbstractMatrix, A))
end

## QRFactorization

struct QRFactorization{P} <: AbstractFactorization
    pivot::P
    blocksize::Int
    inplace::Bool
end

function QRFactorization(inplace = true)
    pivot = @static if VERSION < v"1.7beta"
        Val(false)
    else
        NoPivot()
    end
    QRFactorization(pivot, 16, inplace)
end

function do_factorization(alg::QRFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    if alg.inplace && (!(A isa SparseMatrixCSC) || VERSION >= v"1.8-")
        fact = qr!(A, alg.pivot)
    else
        fact = qr(A) # CUDA.jl does not allow other args!
    end
    return fact
end

## SVDFactorization

struct SVDFactorization{A} <: AbstractFactorization
    full::Bool
    alg::A
end

SVDFactorization() = SVDFactorization(false, LinearAlgebra.DivideAndConquer())

function do_factorization(alg::SVDFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = svd!(A; full = alg.full, alg = alg.alg)
    return fact
end

## MatrixFreeFactorization

# TODO: should this be part of generic factoriation, part of polyalg, etc.
struct MatrixFreeFactorization <: AbstractFactorization end

function do_factorization(::MatrixFreeFactorization, A, b, u)
    fact = LinearAlgebra.factorize(A)
    fact = cache_operator(fact, u)
    return fact
end


## GenericFactorization

struct GenericFactorization{F} <: AbstractFactorization
    fact_alg::F
end

GenericFactorization(; fact_alg = LinearAlgebra.factorize) = GenericFactorization(fact_alg)

function do_factorization(alg::GenericFactorization, A, b, u)
    A = convert(AbstractMatrix, A)
    fact = alg.fact_alg(A)
    return fact
end

function init_cacheval(alg::GenericFactorization{typeof(lu)}, A, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(convert(AbstractMatrix, A))
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)}, A, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(convert(AbstractMatrix, A))
end

function init_cacheval(alg::GenericFactorization{typeof(lu)},
                       A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)},
                       A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(lu)}, A::Diagonal, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(lu)}, A::Tridiagonal, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)}, A::Diagonal, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization{typeof(lu!)}, A::Tridiagonal, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(A)
end

function init_cacheval(alg::GenericFactorization, A::Diagonal, b, u, Pl, Pr, maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    Diagonal(inv.(A.diag))
end
function init_cacheval(alg::GenericFactorization, A::Tridiagonal, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ArrayInterfaceCore.lu_instance(A)
end
function init_cacheval(alg::GenericFactorization, A::SymTridiagonal{T, V}, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions) where {T, V}
    LinearAlgebra.LDLt{T, SymTridiagonal{T, V}}(A)
end

function init_cacheval(alg::Union{GenericFactorization,
                                  GenericFactorization{typeof(bunchkaufman!)},
                                  GenericFactorization{typeof(bunchkaufman)}},
                       A::Union{Hermitian, Symmetric}, b, u, Pl, Pr, maxiters::Int, abstol,
                       reltol, verbose::Bool, assumptions::OperatorAssumptions)
    BunchKaufman(A.data, Array(1:size(A, 1)), A.uplo, true, false, 0)
end

function init_cacheval(alg::Union{GenericFactorization{typeof(bunchkaufman!)},
                                  GenericFactorization{typeof(bunchkaufman)}},
                       A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    if eltype(A) <: Complex
        return bunchkaufman!(Hermitian(A))
    else
        return bunchkaufman!(Symmetric(A))
    end
end

# Fallback, tries to make nonsingular and just factorizes
# Try to never use it.
function init_cacheval(alg::Union{QRFactorization, SVDFactorization, GenericFactorization},
                       A, b, u, Pl, Pr, maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    newA = copy(convert(AbstractMatrix, A))
    if newA isa AbstractSparseMatrix
        fill!(nonzeros(newA), true)
    else
        fill!(newA, true)
    end
    do_factorization(alg, newA, b, u)
end

# Ambiguity handling dispatch
function init_cacheval(alg::Union{QRFactorization, SVDFactorization},
                       A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    newA = copy(convert(AbstractMatrix, A))
    if newA isa AbstractSparseMatrix
        fill!(nonzeros(newA), true)
    else
        fill!(newA, true)
    end
    do_factorization(alg, newA, b, u)
end

# Cholesky needs the posdef matrix, for GenericFactorization assume structure is needed
function init_cacheval(alg::Union{GenericFactorization,
                                  GenericFactorization{typeof(cholesky)},
                                  GenericFactorization{typeof(cholesky!)}}, A, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    newA = copy(convert(AbstractMatrix, A))
    do_factorization(alg, newA, b, u)
end

# Ambiguity handling dispatch
function init_cacheval(alg::Union{GenericFactorization,
                                  GenericFactorization{typeof(cholesky)},
                                  GenericFactorization{typeof(cholesky!)}},
                       A::StridedMatrix{<:LinearAlgebra.BlasFloat}, b, u, Pl, Pr,
                       maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    newA = copy(convert(AbstractMatrix, A))
    do_factorization(alg, newA, b, u)
end

################################## Factorizations which require solve overloads

Base.@kwdef struct UMFPACKFactorization <: AbstractFactorization
    reuse_symbolic::Bool = true
    check_pattern::Bool = true # Check factorization re-use
end

function init_cacheval(alg::UMFPACKFactorization, A, b, u, Pl, Pr, maxiters::Int, abstol,
                       reltol,
                       verbose::Bool, assumptions::OperatorAssumptions)
    A = convert(AbstractMatrix, A)
    zerobased = SparseArrays.getcolptr(A)[1] == 0
    @static if VERSION < v"1.9.0-DEV.1622"
        return SuiteSparse.UMFPACK.UmfpackLU(C_NULL, C_NULL, size(A, 1), size(A, 2),
                                             zerobased ? copy(SparseArrays.getcolptr(A)) :
                                             SuiteSparse.decrement(SparseArrays.getcolptr(A)),
                                             zerobased ? copy(rowvals(A)) :
                                             SuiteSparse.decrement(rowvals(A)),
                                             copy(nonzeros(A)), 0)
        finalizer(SuiteSparse.UMFPACK.umfpack_free_symbolic, res)
    else
        return SuiteSparse.UMFPACK.UmfpackLU(A)
    end
end

function SciMLBase.solve(cache::LinearCache, alg::UMFPACKFactorization; kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    if cache.isfresh
        if cache.cacheval !== nothing && alg.reuse_symbolic
            # Caches the symbolic factorization: https://github.com/JuliaLang/julia/pull/33738
            if alg.check_pattern && !(SuiteSparse.decrement(SparseArrays.getcolptr(A)) ==
                 cache.cacheval.colptr &&
                 SuiteSparse.decrement(SparseArrays.getrowval(A)) == cache.cacheval.rowval)
                fact = lu(A)
            else
                fact = lu!(cache.cacheval, A)
            end
        else
            fact = lu(A)
        end
        cache = set_cacheval(cache, fact)
    end

    y = ldiv!(cache.u, cache.cacheval, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

Base.@kwdef struct KLUFactorization <: AbstractFactorization
    reuse_symbolic::Bool = true
    check_pattern::Bool = true
end

function init_cacheval(alg::KLUFactorization, A, b, u, Pl, Pr, maxiters::Int, abstol,
                       reltol,
                       verbose::Bool, assumptions::OperatorAssumptions)
    return KLU.KLUFactorization(convert(AbstractMatrix, A)) # this takes care of the copy internally.
end

function SciMLBase.solve(cache::LinearCache, alg::KLUFactorization; kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    if cache.isfresh
        if cache.cacheval !== nothing && alg.reuse_symbolic
            if alg.check_pattern && !(SuiteSparse.decrement(SparseArrays.getcolptr(A)) ==
                 cache.cacheval.colptr &&
                 SuiteSparse.decrement(SparseArrays.getrowval(A)) == cache.cacheval.rowval)
                fact = KLU.klu(A)
            else
                # If we have a cacheval already, run umfpack_symbolic to ensure the symbolic factorization exists
                # This won't recompute if it does.
                KLU.klu_analyze!(cache.cacheval)
                copyto!(cache.cacheval.nzval, A.nzval)
                if cache.cacheval._numeric === C_NULL # We MUST have a numeric factorization for reuse, unlike UMFPACK.
                    KLU.klu_factor!(cache.cacheval)
                end
                fact = KLU.klu!(cache.cacheval, A)
            end
        else
            # New fact each time since the sparsity pattern can change
            # and thus it needs to reallocate
            fact = KLU.klu(A)
        end
        cache = set_cacheval(cache, fact)
    end

    y = ldiv!(cache.u, cache.cacheval, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

## RFLUFactorization

struct RFLUFactorization{P, T} <: AbstractFactorization
    RFLUFactorization(::Val{P}, ::Val{T}) where {P, T} = new{P, T}()
end

function RFLUFactorization(; pivot = Val(true), thread = Val(true))
    RFLUFactorization(pivot, thread)
end

function init_cacheval(alg::RFLUFactorization, A, b, u, Pl, Pr, maxiters::Int,
                       abstol, reltol, verbose::Bool, assumptions::OperatorAssumptions)
    ipiv = Vector{LinearAlgebra.BlasInt}(undef, min(size(A)...))
    ArrayInterfaceCore.lu_instance(convert(AbstractMatrix, A)), ipiv
end

function SciMLBase.solve(cache::LinearCache, alg::RFLUFactorization{P, T};
                         kwargs...) where {P, T}
    A = cache.A
    A = convert(AbstractMatrix, A)
    fact, ipiv = cache.cacheval
    if cache.isfresh
        fact = RecursiveFactorization.lu!(A, ipiv, Val(P), Val(T))
        cache = set_cacheval(cache, (fact, ipiv))
    end
    y = ldiv!(cache.u, cache.cacheval[1], cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

## FastLAPACKFactorizations

struct WorkspaceAndFactors{W, F}
    workspace::W
    factors::F
end

# There's no options like pivot here.
# But I'm not sure it makes sense as a GenericFactorization
# since it just uses `LAPACK.getrf!`.
struct FastLUFactorization <: AbstractFactorization end

function init_cacheval(::FastLUFactorization, A, b, u, Pl, Pr,
                       maxiters::Int, abstol, reltol, verbose::Bool,
                       assumptions::OperatorAssumptions)
    ws = LUWs(A)
    return WorkspaceAndFactors(ws, LinearAlgebra.LU(LAPACK.getrf!(ws, A)...))
end

function SciMLBase.solve(cache::LinearCache, alg::FastLUFactorization; kwargs...)
    A = cache.A
    A = convert(AbstractMatrix, A)
    ws_and_fact = cache.cacheval
    if cache.isfresh
        # we will fail here if A is a different *size* than in a previous version of the same cache.
        # it may instead be desirable to resize the workspace.
        @set! ws_and_fact.factors = LinearAlgebra.LU(LAPACK.getrf!(ws_and_fact.workspace,
                                                                   A)...)
        cache = set_cacheval(cache, ws_and_fact)
    end
    y = ldiv!(cache.u, cache.cacheval.factors, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end

struct FastQRFactorization{P} <: AbstractFactorization
    pivot::P
    blocksize::Int
end

function FastQRFactorization()
    pivot = @static if VERSION < v"1.7beta"
        Val(false)
    else
        NoPivot()
    end
    FastQRFactorization(pivot, 36) # is 36 or 16 better here? LinearAlgebra and FastLapackInterface use 36,
    # but QRFactorization uses 16.
end

@static if VERSION < v"1.7beta"
    function init_cacheval(alg::FastQRFactorization{Val{false}}, A, b, u, Pl, Pr,
                           maxiters::Int, abstol, reltol, verbose::Bool,
                           assumptions::OperatorAssumptions)
        ws = QRWYWs(A; blocksize = alg.blocksize)
        return WorkspaceAndFactors(ws, LinearAlgebra.QRCompactWY(LAPACK.geqrt!(ws, A)...))
    end

    function init_cacheval(::FastQRFactorization{Val{true}}, A, b, u, Pl, Pr,
                           maxiters::Int, abstol, reltol, verbose::Bool,
                           assumptions::OperatorAssumptions)
        ws = QRpWs(A)
        return WorkspaceAndFactors(ws, LinearAlgebra.QRPivoted(LAPACK.geqp3!(ws, A)...))
    end
else
    function init_cacheval(alg::FastQRFactorization{NoPivot}, A, b, u, Pl, Pr,
                           maxiters::Int, abstol, reltol, verbose::Bool,
                           assumptions::OperatorAssumptions)
        ws = QRWYWs(A; blocksize = alg.blocksize)
        return WorkspaceAndFactors(ws, LinearAlgebra.QRCompactWY(LAPACK.geqrt!(ws, A)...))
    end
    function init_cacheval(::FastQRFactorization{ColumnNorm}, A, b, u, Pl, Pr,
                           maxiters::Int, abstol, reltol, verbose::Bool,
                           assumptions::OperatorAssumptions)
        ws = QRpWs(A)
        return WorkspaceAndFactors(ws, LinearAlgebra.QRPivoted(LAPACK.geqp3!(ws, A)...))
    end
end

function SciMLBase.solve(cache::LinearCache, alg::FastQRFactorization{P};
                         kwargs...) where {P}
    A = cache.A
    A = convert(AbstractMatrix, A)
    ws_and_fact = cache.cacheval
    if cache.isfresh
        # we will fail here if A is a different *size* than in a previous version of the same cache.
        # it may instead be desirable to resize the workspace.
        nopivot = @static if VERSION < v"1.7beta"
            Val{false}
        else
            NoPivot
        end
        if P === nopivot
            @set! ws_and_fact.factors = LinearAlgebra.QRCompactWY(LAPACK.geqrt!(ws_and_fact.workspace,
                                                                                A)...)
        else
            @set! ws_and_fact.factors = LinearAlgebra.QRPivoted(LAPACK.geqp3!(ws_and_fact.workspace,
                                                                              A)...)
        end
        cache = set_cacheval(cache, ws_and_fact)
    end
    y = ldiv!(cache.u, cache.cacheval.factors, cache.b)
    SciMLBase.build_linear_solution(alg, y, nothing, cache)
end
