###########################################################################
# Lazy wrapper around a Py to load a module on demand.

mutable struct LazyPyModule
    name::String
    o::Py
    LazyPyModule(n::AbstractString) = new(n, PythonCall.pynew())
end

_ispynull(x::Py) = PythonCall.getptr(x) == PythonCall.C.PyNULL
PythonCall.Py(m::LazyPyModule) = _ispynull(getfield(m, :o)) ? PythonCall.pycopy!(getfield(m, :o), pyimport(getfield(m, :name))) : getfield(m, :o)
Base.Docs.doc(m::LazyPyModule) = Base.Docs.Text(pyconvert(String, Py(m).__doc__))
Base.getproperty(m::LazyPyModule, x::Symbol) = getproperty(Py(m), x)
Base.setproperty!(m::LazyPyModule, x::Symbol, v) = setproperty!(Py(m), x, v)
Base.hasproperty(m::LazyPyModule, x::Symbol) = PyCall.hasproperty(Py(m), x)
Base.propertynames(m::LazyPyModule) = propertynames(Py(m))

###########################################################################
# Lazily load mplot3d modules.  This (slightly) improves load time of PythonPlot,
# and it also allows PythonPlot to load on systems where mplot3d is not installed.

const axes3D = LazyPyModule("mpl_toolkits.mplot3d.axes3d")
const art3D = LazyPyModule("mpl_toolkits.mplot3d.art3d")

"""
    using3D()

This function ensures that the `mplot3d` module is loaded for 3d
plotting.   This occurs automatically if you call any of the
3d plotting functions like `plot3D` or `surf`, but it may be
necessary to call this function manually if you are passing
`projection="3d"` explicitly to axes or subplot objects.
"""
using3D() = (Py(axes3D); nothing)

###########################################################################
# 3d plotting functions from mplot3d

export art3D, Axes3D, using3D, surf, mesh, bar3D, contour3D, contourf3D, plot3D, plot_surface, plot_trisurf, plot_wireframe, scatter3D, text2D, text3D, zlabel, zlim, zscale, zticks

const mplot3d_funcs = (:bar3d, :contour3D, :contourf3D, :plot3D, :plot_surface,
                       :plot_trisurf, :plot_wireframe, :scatter3D,
                       :text2D, :text3D, :view_init, :voxels)

function gca3d()
    using3D() # make sure mplot3d is loaded
    return version <= v"3.4" ? gca(projection="3d") : pyplot.subplot(gca().get_subplotspec(), projection="3d")
end

for f in mplot3d_funcs
    fs = string(f)
    @eval @doc LazyHelp(axes3D,"Axes3D", $fs) function $f(args...; kws...)
        pycall(gca3d().$fs, args...; kws...)
    end
end

@doc LazyHelp(axes3D,"Axes3D") Axes3D(args...; kws...) = pycall(axes3D."Axes3D", args...; kws...)

# correct for annoying mplot3d inconsistency
@doc LazyHelp(axes3D,"Axes3D", "bar3d") bar3D(args...; kws...) = bar3d(args...; kws...)

# it's annoying to have xlabel etc. but not zlabel
const zlabel_funcs = (:zlabel, :zlim, :zscale, :zticks)
for f in zlabel_funcs
    fs = string("set_", f)
    @eval @doc LazyHelp(axes3D,"Axes3D", $fs) function $f(args...; kws...)
        pycall(gca3d().$fs, args...; kws...)
    end
end

# export Matlab-like names

function surf(Z::AbstractMatrix; kws...)
    plot_surface([1:size(Z,1);]*ones(1,size(Z,2)),
                 ones(size(Z,1))*[1:size(Z,2);]', Z; kws...)
end

@doc LazyHelp(axes3D,"Axes3D", "plot_surface") function surf(X, Y, Z::AbstractMatrix, args...; kws...)
    plot_surface(X, Y, Z, args...; kws...)
end

function surf(X, Y, Z::AbstractVector, args...; kws...)
    plot_trisurf(X, Y, Z, args...; kws...)
end

@doc LazyHelp(axes3D,"Axes3D", "plot_wireframe") mesh(args...; kws...) = plot_wireframe(args...; kws...)

function mesh(Z::AbstractMatrix; kws...)
    plot_wireframe([1:size(Z,1);]*ones(1,size(Z,2)),
                   ones(size(Z,1))*[1:size(Z,2);]', Z; kws...)
end
