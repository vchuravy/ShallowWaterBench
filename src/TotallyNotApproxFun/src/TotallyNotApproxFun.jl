module TotallyNotApproxFun

using FastGaussQuadrature
using StaticArrays

export Fun, ComboFun, ApproxFun, ProductFun, LagrangeFun, VectorFun, MultilinearFun
export Basis, OrthoBasis, ProductBasis, LagrangeBasis
export points, LobattoPoints

#A representation of a T-valued function in an N-Dimensional space.
abstract type Fun{T, N} end

#A discretization of a (T-valued function)-valued function in an N-Dimensional space.
abstract type Basis{T, N, F<:Fun{T, N}} <: AbstractArray{F, N} end

#A function represented by a linear combination of basis functions
struct ComboFun{T, N, B<:Basis{<:Any, N}, C<:AbstractArray{T}} <: Fun{T, N}
    basis::B
    coeffs::C
end

(f::ComboFun)(x) = apply(f, SVector(x))
(f::ComboFun)(x::AbstractVector) = apply(f, x)
(f::ComboFun)(x...)  = apply(f, SVector(x...))
#f(x) is just sum_i(c_i * b_i(x))
function apply(f::ComboFun, x::AbstractVector)
    return sum(f.coeffs .* (apply.(f.basis, Ref(x))))
end

#A basis corresponding to a set of points, where the basis function i is one(T) at point i and zero(T) everywhere else
abstract type OrthoBasis{T, N, F} <: Basis{T, N, F} end
points(::OrthoBasis) = error("Subtypes of OrthoBasis must define the points function")
ApproxFun(f, b::OrthoBasis) = ComboFun(b, map(f, points(b)))

for op in (:+, :-)
    @eval begin
        function Base.$(op)(a::ComboFun{T, N, B}) where {T, N, B <: OrthoBasis}
            ComboFun(a.basis, map($op, a.coeffs))
        end
    end
end
for op in (:(Base.:+), :(Base.:-), :(Base.:*), :(Base.:/))
    @eval begin
        function $op(a::ComboFun{T, N, B}, b::ComboFun{S, N, B}) where {T, S, N, B <: OrthoBasis}
            @assert a.basis == b.basis
            ComboFun(a.basis, map($op, a.coeffs, b.coeffs))
        end
        function $op(a::ComboFun{T, N, B}, b) where {T, N, B <: OrthoBasis}
            @assert a.basis == b.basis
            ComboFun(a.basis, map($op, a.coeffs, b))
        end
        function $op(a::ComboFun{T, N, B}, b::Fun) where {T, N, B <: OrthoBasis}
            throw(NotImplementedError())
        end
        function $op(a, b::ComboFun{T, N, B}) where {T, N, B <: OrthoBasis}
            @assert a.basis == b.basis
            ComboFun(a.basis, map($op, a.coeffs, b))
        end
        function $op(a::Fun, b::ComboFun{T, N, B}) where {T, N, B <: OrthoBasis}
            throw(NotImplementedError())
        end
    end
end

#A function which is a product of one-dimensional functions
struct ProductFun{T, N, F <: Tuple{Vararg{Fun{T, 1}, N}}} <: Fun{T, N}
    funs::F
    ProductFun(funs::Fun{T, 1}) where {T} = new{T, 1, Tuple{typeof(funs)}}((funs,))
    ProductFun(funs::Fun{T, 1}...) where {T} = new{T, length(funs), typeof(funs)}(funs)
end

(f::ProductFun)(x) = apply(f, SVector(x))
(f::ProductFun)(x::AbstractVector) = apply(f, x)
(f::ProductFun)(x...) = apply(f, SVector(x...))
function apply(f::ProductFun, x::AbstractVector)
    prod(apply.(SVector(f.funs), SVector.(x)))
end

#A basis which is a cartesian product of one-dimensional bases
struct ProductBasis{T, N, F, B <: Tuple{Vararg{OrthoBasis{T, 1}, N}}} <: OrthoBasis{T, N, ProductFun{T, N, Tuple{Vararg{F, N}}}}
    bases::B
    ProductBasis(basis::OrthoBasis{T, 1, F}) where {T, F} = new{T, 1, F, Tuple{typeof(basis)}}((basis,))
    ProductBasis(bases::OrthoBasis{T, 1, F}...) where {T, F} = new{T, length(bases), F, typeof(bases)}(bases)
end

Base.size(b::ProductBasis) = Tuple(map(length, b.bases))
Base.getindex(b::ProductBasis, i::CartesianIndex) = ProductFun(map(getindex, b.bases, Tuple(i))...)
points(b::ProductBasis) = map(i -> SVector(getindex.(b.bases, Tuple(i))), CartesianIndices(map(basis->axes(basis)[1], b.bases))) #This is a hard line to read

#The minimum-degree polynomial function which is 1 at the nth point and 0 at the other points
struct LagrangeFun{T, P <: AbstractVector{T}} <: Fun{T, 1}
    points::P
    n::Int
end

LagrangeFun(points::AbstractVector, n) = LagrangeFun{eltype(points), typeof(points)}(points, n)
(f::LagrangeFun)(x) = apply(f, SVector(x))
(f::LagrangeFun)(x::AbstractVector) = apply(f, x)
(f::LagrangeFun)(x...) = apply(f, SVector(x...))
#This method is mostly here for clarity, it probably shouldn't be called (TODO specialize somewhere with a stable interpolation routine)
apply(f::LagrangeFun, x::AbstractVector) = apply(f, x[1])
function apply(f::LagrangeFun, x)
    @assert length(x) == 1
    res = prod(ntuple(i->i == f.n ? 1 : (x - f.points[i])/(f.points[f.n] - f.points[i]), length(f.points)))
end

#A basis of polynomials
struct LagrangeBasis{T, P <: AbstractVector{T}} <: OrthoBasis{T, 1, LagrangeFun{T, P}}
    points::P
end

Base.size(b::LagrangeBasis) = size(b.points)
Base.getindex(b::LagrangeBasis, i::Int) = LagrangeFun(b.points, i)
points(b::LagrangeBasis) = b.points

#A vector representing Lobatto Points
struct LobattoPoints{T, N} <: AbstractVector{T} end

Base.size(p::LobattoPoints{T, N}) where {T, N} = (N,)
@generated function Base.getindex(p::LobattoPoints{T, N}, i::Int) where {T, N}
    return :($(SVector{N, T}(gausslobatto(N)[1]))[i])
end
LobattoPoints(n) = LobattoPoints{Float64, n + 1}()

#A vector-valued function composed of one-dimensional functions
struct VectorFun{T, N, F <: Tuple{Vararg{Fun{T, 1}, N}}} <: Fun{SVector{N, T}, N}
    funs::F
    VectorFun(x::Fun{T, 1}) where {T} = new{T, 1, Tuple{typeof(x)}}((x,))
    VectorFun(x::Fun{T, 1}...) where {T} = new{T, length(x), typeof(x)}(x)
end

(f::VectorFun)(x) = apply(f, SVector(x))
(f::VectorFun)(x::AbstractVector) = apply(f, x)
(f::VectorFun)(x...) = apply(f, SVector(x...))
function apply(f::VectorFun, x::AbstractVector)
    apply.(SVector(f.funs), SVector.(x))
end

#WARNING DEFINING AN SARRAY METHOD
StaticArrays.SVector(i::CartesianIndex) = SVector(Tuple(i))

function MultilinearFun(x₀, x₁, y₀, y₁)
    VectorFun(ComboFun.(LagrangeBasis.(SVector.(Tuple(x₀), Tuple(x₁))), SVector.(Tuple(y₀), Tuple(y₁)))...)
end

#r = repositioner(SVector(2.0, 4.0), SVector(3.0, 5.0), SVector(-1.0, -1.0), SVector(1.0, 1.0))

#println(r([3.4, 4.5]))
#using InteractiveUtils
#@code_warntype(r([3.4, 4.5]))











#1 function to interpolate global coefficients to local -1 to 1 for basis
#  a) only store scale in type domain
#  b) store scale and offset

#2 implement ∫ψ(f, ω, J) and ∫∇ψ(f) on combination functions (and handle the fact that f is repositioned) (f = f(reposition(x)))

#3 implement ∫ and ∫∇ on combination functions (and handle the fact that f is repositioned) (f = f(reposition(x)))

end
