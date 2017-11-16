using OrdinaryDiffEq, Requires, ForwardDiff
import OrdinaryDiffEq.ODEProblem
import OrdinaryDiffEq.ODEIntegrator

export ContinuousDS, ODEProblem, ODEIntegrator

#######################################################################################
#                                     Constructors                                    #
#######################################################################################
"Abstract type representing continuous systems."
abstract type ContinuousDynamicalSystem <: DynamicalSystem end

"""
    ContinuousDS(state, eom! [, jacob]; name="") <: ContinuousDynamicalSystem
    Continuous dynamical system with dimension D = length(state)
## Fields:
* `state::Vector{T}` : Current state-vector of the system
* `eom!` (function) : The function that represents the system's equations of motion
  (also called vector field). The function is of the format: `eom!(du, u)`
  which means that it is **in-place**, with the Julian syntax (the mutated argument
  `du` is the first).
* `jacob` (function) : The function that represents the Jacobian of the system,
  given in the format: `jacob(u) => J` (i.e. returns a matrix). If the matrix is
  an `SMatrix` from `StaticArrays.jl` there are major performance gains.
* `name::String` : A name for the dynamical system (possibly including parameter
  values), solely for pretty-printing purposes. Always passed to the constructors
  as a keyword.

Because the `jacob` function is only necessary for a subset of algorithms, you
do not have to provide it necessarily to the constructor (but then you can't use these
functions).
"""
mutable struct ContinuousDS{T<:AbstractVector, F, J} <: ContinuousDynamicalSystem
    state::T
    eom!::F
    jacob::J
    name::String
end

# Constructors
ContinuousDS(state, eom!; name = "") = ContinuousDS(state, eom!, nothing, name)
ContinuousDS(state, eom!, j!; name="") = ContinuousDS(state, eom!, j!, name)

dimension(ds::ContinuousDS) = length(ds.state)
Base.eltype(ds::ContinuousDS{T,F,J}) where {T, F, J} = eltype(T)
#######################################################################################
#                         Interface to DifferentialEquations                          #
#######################################################################################
function get_solver!(diff_eq_kwargs::Dict)
    if haskey(diff_eq_kwargs, :solver)
        solver = diff_eq_kwargs[:solver]
        pop!(diff_eq_kwargs, :solver)
    else
        solver = Tsit5()
    end
    return solver
end



"""
```julia
ODEProblem(ds::ContinuousDS, t)
```
Return an `ODEProblem` with the given
system information (t0 is zero).
This can be passed directly into `solve` from [`DifferentialEquations.jl`](http://docs.juliadiffeq.org/stable/index.html).
"""
function ODEProblem(ds::ContinuousDS, t)
    odef = (t, u, du) -> ds.eom!(du, u)
    OrdinaryDiffEq.ODEProblem(odef, copy(ds.state), (zero(t), t))
end



"""
```julia
ODEIntegrator(ds::ContinuousDS, t; diff_eq_kwargs)
```
Return an `ODEIntegrator`, by first creating an `ODEProblem(ds, t)`.
This can be used directly with the interfaces of
[`DifferentialEquations.jl`](http://docs.juliadiffeq.org/stable/index.html).

`diff_eq_kwargs = Dict()` is a dictionary `Dict{Symbol, ANY}`
of keyword arguments
passed into the `init` of the
[`DifferentialEquations.jl`](http://docs.juliadiffeq.org/stable/index.html) package,
for example `Dict(:abstol => 1e-9)`. If you want to specify a solver,
do so by using the symbol `:solver`, e.g.:
`Dict(:solver => DP5(), :tstops => 0:0.01:t)`. This requires you to have been first
`using OrdinaryDiffEq` to access the solvers.
"""
function ODEIntegrator(ds::ContinuousDS, t; diff_eq_kwargs = Dict())
    prob = ODEProblem(ds, t)
    solver = get_solver!(diff_eq_kwargs)
    integrator = init(prob, solver; diff_eq_kwargs...,
    save_first=false, save_everystep=false)
    return integrator
end



"""
    get_sol(prob::ODEProblem, diff_eq_kwargs::Dict = Dict())
Solve the `prob` using `solve` and return the solution.
"""
function get_sol(prob::ODEProblem, diff_eq_kwargs::Dict = Dict())
    solver = get_solver!(diff_eq_kwargs)
    sol = solve(prob, solver; diff_eq_kwargs..., save_everystep=false)
    return sol.u
end

#######################################################################################
#                                Evolution of System                                  #
#######################################################################################
# See discrete.jl for the documentation string
function evolve(ds::ContinuousDS, t::Real = 1.0; diff_eq_kwargs = Dict())
    prob = ODEProblem(ds, t)
    return get_sol(prob, diff_eq_kwargs)[end]
end
function evolve!(ds::ContinuousDS, t::Real = 1.0; diff_eq_kwargs = Dict())
    ds.state = evolve(ds, t, diff_eq_kwargs = diff_eq_kwargs)
    return ds.state
end

# See discrete.jl for the documentation string
function trajectory(ds::ContinuousDS, T::Real;
    dt::Real=0.05, diff_eq_kwargs = Dict())

    # Necessary due to DifferentialEquations:
    if !issubtype(typeof(T), AbstractFloat)
        T = convert(Float64, T)
    end
    T<=0 && throw(ArgumentError("Total time `T` must be positive."))

    D = dimension(ds)
    t = zero(T):dt:T #time vector
    prob = ODEProblem(ds, T)
    kw = Dict{Symbol, Any}(diff_eq_kwargs) #nessesary conversion to add :saveat
    kw[:saveat] = t
    return Dataset(get_sol(prob, kw))
end

#######################################################################################
#                                 Pretty-Printing                                     #
#######################################################################################
import Base.show
function Base.show(io::IO, ds::ContinuousDS{S, F, J}) where {S, F, J}
    D = dimension(ds)
    print(io, "$D-dimensional continuous dynamical system:\n",
    "state: $(ds.state)\n", "e.o.m.: $F\n", "jacobian: $J")
end

@require Juno begin
function Juno.render(i::Juno.Inline, s::ContinuousDS{S, F, J}) where
    {S, F, J}
    t = Juno.render(i, Juno.defaultrepr(s))
    if ds.name == ""
        text = "$(dimension(s))-dimensional continuous dynamical system"
    else
        text = ds.name
    end
    t[:head] = Juno.render(i, Text(text))
    pop!(t[:children]) # remove name field
    t
end
end