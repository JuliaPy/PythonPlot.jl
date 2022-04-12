
"""
PythonPlot allows Julia to interface with the Matplotlib library in Python, specifically the matplotlib.pyplot module, so you can create beautiful plots in Julia with your favorite Python package.

Only the currently documented matplotlib.pyplot API is exported. To use other functions in the module, you can also call matplotlib.pyplot.foo(...) as plt.foo(...).
For example, plt.plot(x, y) also works. (And the raw Py object for the matplotlib modules is also accessible as PythonPlot.matplotlib.)

In general, all the arguments are the same as in Python.

Here's a brief demo of a simple plot in Julia:

    using PythonPlot
    x = range(0; stop=2*pi, length=1000); y = sin.(3 * x + 4 * cos.(2 * x));
    plot(x, y, color="red", linewidth=2.0, linestyle="--")
    title("A sinusoidally modulated sinusoid")

For more information on API, see the matplotlib.pyplot documentation and the PythonPlot GitHub page.
"""
module PythonPlot

using PythonCall
import Base: convert, ==, isequal, hash, getindex, setindex!, haskey, keys, show
export Figure, plt, matplotlib, pygui, withfig

###########################################################################
# Define a documentation object
# that lazily looks up help from a Py object via zero or more keys.
# This saves us time when loading PythonPlot, since we don't have
# to load up all of the documentation strings right away.
struct LazyHelp
    o # a Py or similar object supporting getindex with a __doc__ property
    keys::Tuple{Vararg{String}}
    LazyHelp(o) = new(o, ())
    LazyHelp(o, k::AbstractString) = new(o, (k,))
    LazyHelp(o, k1::AbstractString, k2::AbstractString) = new(o, (k1,k2))
    LazyHelp(o, k::Tuple{Vararg{AbstractString}}) = new(o, k)
end
function Base.show(io::IO, ::MIME"text/plain", h::LazyHelp)
    o = h.o
    for k in h.keys
        o = o[k]
    end
    if hasproperty(o, :__doc__)
        print(io, pyconvert(String, o.__doc__))
    else
        print(io, "no Python docstring found for ", o)
    end
end
Base.show(io::IO, h::LazyHelp) = show(io, "text/plain", h)
function Base.Docs.catdoc(hs::LazyHelp...)
    Base.Docs.Text() do io
        for h in hs
            show(io, MIME"text/plain"(), h)
        end
    end
end

###########################################################################

include("pygui.jl")
include("init.jl")

###########################################################################
# Wrapper around matplotlib Figure, supporting graphics I/O and pretty display

mutable struct Figure
    o::Py
end
PythonCall.Py(f::Figure) = getfield(f, :o)
PythonCall.pyconvert(::Type{Figure}, o::Py) = Figure(o)
==(f::Figure, g::Figure) = Py(f) == Py(g)
==(f::Figure, g::Py) = Py(f) == g
==(f::Py, g::Figure) = f == Py(g)
hash(f::Figure) = hash(Py(f))
PythonCall.pycall(f::Figure, args...; kws...) = pycall(Py(f), args...; kws...)
(f::Figure)(args...; kws...) = pycall(Py(f), PyAny, args...; kws...)
Base.Docs.doc(f::Figure) = Base.Docs.Text(pyconvert(String, Py(f).__doc__))

# Note: using `Union{Symbol,String}` produces ambiguity.
Base.getproperty(f::Figure, s::Symbol) = getproperty(Py(f), s)
Base.getproperty(f::Figure, s::AbstractString) = getproperty(f, Symbol(s))
Base.setproperty!(f::Figure, s::Symbol, x) = setproperty!(Py(f), s, x)
Base.setproperty!(f::Figure, s::AbstractString, x) = setproperty!(f, Symbol(s), x)
Base.hasproperty(f::Figure, s::Symbol) = hasproperty(Py(f), s)
Base.propertynames(f::Figure) = propertynames(Py(f))

for (mime,fmt) in aggformats
    @eval _showable(::MIME{Symbol($mime)}, f::Figure) = !isempty(f) && haskey(PyDict{Any,Any}(f.canvas.get_supported_filetypes()), $fmt)
    @eval function Base.show(io::IO, m::MIME{Symbol($mime)}, f::Figure)
        if !_showable(m, f)
            throw(MethodError(show, (io, m, f)))
        end
        f.canvas.print_figure(io, format=$fmt, bbox_inches="tight")
    end
    if fmt != "svg"
        @eval Base.showable(m::MIME{Symbol($mime)}, f::Figure) = _showable(m, f)
    end
end

# disable SVG output by default, since displaying large SVGs (large datasets)
# in IJulia is slow, and browser SVG display is buggy.  (Similar to IPython.)
const SVG = [false]
Base.showable(m::MIME"image/svg+xml", f::Figure) = SVG[1] && _showable(m, f)
svg() = SVG[1]
svg(b::Bool) = (SVG[1] = b)

###########################################################################
# In IJulia, we want to automatically display any figures
# at the end of cell execution, and then close them.   However,
# we don't want to display/close figures being used in withfig,
# since the user is keeping track of these in some other way,
# e.g. for interactive widgets.

Base.isempty(f::Figure) = isempty(f.get_axes())

# We keep a set of figure numbers for the figures used in withfig, because
# for these figures we don't want to auto-display or auto-close them
# when the cell finishes executing.   (We store figure numbers, rather
# than Figure objects, since the latter would prevent the figures from
# finalizing and hence closing.)  Closing the figure removes it from this set.
const withfig_fignums = Set{Int}()

function display_figs() # called after IJulia cell executes
    if isjulia_display[]
        for manager in Gcf.get_all_fig_managers()
            f = manager.canvas.figure
            if pyconvert(Int, f.number) ∉ withfig_fignums
                fig = Figure(f)
                isempty(fig) || display(fig)
                plt.close(f)
            end
        end
    end
end

function close_figs() # called after error in IJulia cell
    if isjulia_display[]
        for manager in Gcf.get_all_fig_managers()
            f = manager.canvas.figure
            if pyconvert(Int, f.number) ∉ withfig_fignums
                plt.close(f)
            end
        end
    end
end

# hook to force new IJulia cells to create new figure objects
const gcf_isnew = [false] # true to force next gcf() to be new figure
force_new_fig() = gcf_isnew[1] = true

# wrap gcf() and figure(...) so that we can force the creation
# of new figures in new IJulia cells (e.g. after @manipulate commands
# that leave the figure from the previous cell open).

@doc LazyHelp(orig_figure) function figure(args...; kws...)
    gcf_isnew[1] = false
    Figure(pycall(orig_figure, args...; kws...))
end

@doc LazyHelp(orig_gcf) function gcf()
    if isjulia_display[] && gcf_isnew[1]
        return figure()
    else
        return Figure(orig_gcf())
    end
end

###########################################################################

# export documented pyplot API (http://matplotlib.org/api/pyplot_api.html)
export acorr,annotate,arrow,autoscale,autumn,axhline,axhspan,axis,axline,axvline,axvspan,bar,barbs,barh,bone,box,boxplot,broken_barh,cla,clabel,clf,clim,cohere,colorbar,colors,contour,contourf,cool,copper,csd,delaxes,disconnect,draw,errorbar,eventplot,figaspect,figimage,figlegend,figtext,figure,fill_between,fill_betweenx,findobj,flag,gca,gcf,gci,get_current_fig_manager,get_figlabels,get_fignums,get_plot_commands,ginput,gray,grid,hexbin,hist2D,hlines,hold,hot,hsv,imread,imsave,imshow,ioff,ion,ishold,jet,legend,locator_params,loglog,margins,matshow,minorticks_off,minorticks_on,over,pause,pcolor,pcolormesh,pie,pink,plot,plot_date,plotfile,polar,prism,psd,quiver,quiverkey,rc,rc_context,rcdefaults,rgrids,savefig,sca,scatter,sci,semilogx,semilogy,set_cmap,setp,show,specgram,spectral,spring,spy,stackplot,stem,step,streamplot,subplot,subplot2grid,subplot_tool,subplots,subplots_adjust,summer,suptitle,table,text,thetagrids,tick_params,ticklabel_format,tight_layout,title,tricontour,tricontourf,tripcolor,triplot,twinx,twiny,vlines,waitforbuttonpress,winter,xkcd,xlabel,xlim,xscale,xticks,ylabel,ylim,yscale,yticks,hist

# The following pyplot functions must be handled specially since they
# overlap with standard Julia functions:
#          close, fill, show, step
# … as in PyPlot.jl, we commit some type piracy here.

const plt_funcs = (:acorr,:annotate,:arrow,:autoscale,:autumn,:axes,:axhline,:axhspan,:axis,:axline,:axvline,:axvspan,:bar,:barbs,:barh,:bone,:box,:boxplot,:broken_barh,:cla,:clabel,:clf,:clim,:cohere,:colorbar,:colors,:connect,:contour,:contourf,:cool,:copper,:csd,:delaxes,:disconnect,:draw,:errorbar,:eventplot,:figaspect,:figimage,:figlegend,:figtext,:fill_between,:fill_betweenx,:findobj,:flag,:gca,:gci,:get_current_fig_manager,:get_figlabels,:get_fignums,:get_plot_commands,:ginput,:gray,:grid,:hexbin,:hlines,:hold,:hot,:hsv,:imread,:imsave,:imshow,:ioff,:ion,:ishold,:jet,:legend,:locator_params,:loglog,:margins,:matshow,:minorticks_off,:minorticks_on,:over,:pause,:pcolor,:pcolormesh,:pie,:pink,:plot,:plot_date,:plotfile,:polar,:prism,:psd,:quiver,:quiverkey,:rc,:rc_context,:rcdefaults,:rgrids,:savefig,:sca,:scatter,:sci,:semilogx,:semilogy,:set_cmap,:setp,:specgram,:spectral,:spring,:spy,:stackplot,:stem,:streamplot,:subplot,:subplot2grid,:subplot_tool,:subplots,:subplots_adjust,:summer,:suptitle,:table,:text,:thetagrids,:tick_params,:ticklabel_format,:tight_layout,:title,:tricontour,:tricontourf,:tripcolor,:triplot,:twinx,:twiny,:vlines,:waitforbuttonpress,:winter,:xkcd,:xlabel,:xlim,:xscale,:xticks,:ylabel,:ylim,:yscale,:yticks,:hist,:xcorr,:isinteractive)

for f in plt_funcs
    sf = string(f)
    @eval @doc LazyHelp(plt,$sf) function $f(args...; kws...)
        if !hasproperty(plt, $(QuoteNode(f)))
            error("matplotlib ", version, " does not have pyplot.", $sf)
        end
        return pycall(plt.$f, args...; kws...)
    end
end

# type piracy as in PyPlot.jl:
@doc LazyHelp(plt,"step") Base.step(x, y; kws...) = pycall(plt.step, x, y; kws...)

# type piracy as in PyPlot.jl:
Base.show(; kws...) = begin pycall(plt.show; kws...); nothing; end

Base.close(f::Figure) = close(f.number)

# type piracy as in PyPlot.jl:
function Base.close(f::Integer)
    pop!(withfig_fignums, f, f)
    plt.close(f)
end
Base.close(f::Union{AbstractString,Symbol}) = plt.close(f)
@doc LazyHelp(plt,"close") Base.close() = plt.close()

# type piracy as in PyPlot.jl:
@doc LazyHelp(plt,"fill") Base.fill(x::AbstractArray,y::AbstractArray, args...; kws...) =
    pycall(plt."fill", PyAny, x, y, args...; kws...)

# consistent capitalization with mplot3d
@doc LazyHelp(plt,"hist2d") hist2D(args...; kws...) = pycall(plt.hist2d, args...; kws...)

include("colormaps.jl")

###########################################################################
# Support array of string labels in bar chart

function bar(x::AbstractVector{<:AbstractString}, y; kws_...)
    kws = Dict{Any,Any}(kws_)
    xi = 1:length(x)
    if !any(==(:align), keys(kws))
        kws[:align] = "center"
    end
    p = bar(xi, y; kws...)
    ax = any(kw -> kw[1] == :orientation && lowercase(kw[2]) == "horizontal",
             pairs(kws)) ? gca().yaxis : gca().xaxis
    ax.set_ticks(xi)
    ax.set_ticklabels(x)
    return p
end

bar(x::AbstractVector{T}, y; kws...) where {T<:Symbol} =
    bar(map(string, x), y; kws...)

###########################################################################
# Allow plots with 2 independent variables (contour, surf, ...)
# to accept either 2 1d arrays or a row vector and a 1d array,
# to simplify construction of such plots via broadcasting operations.
# (Matplotlib is inconsistent about this.)

include("plot3d.jl")

for f in (:contour, :contourf)
    @eval function $f(X::AbstractMatrix, Y::AbstractVector, args...; kws...)
        if size(X,1) == 1 || size(X,2) == 1
            $f(reshape(X, length(X)), Y, args...; kws...)
        elseif size(X,1) > 1 && size(X,2) > 1 && isempty(args)
            $f(X; levels=Y, kws...) # treat Y as contour levels
        else
            throw(ArgumentError("if 2nd arg is column vector, 1st arg must be row or column vector"))
        end
    end
end

for f in (:surf,:mesh,:plot_surface,:plot_wireframe,:contour3D,:contourf3D)
    @eval begin
        function $f(X::AbstractVector, Y::AbstractVector, Z::AbstractMatrix, args...; kws...)
            m, n = length(X), length(Y)
            $f(repeat(transpose(X),outer=(n,1)), repeat(Y,outer=(1,m)), Z, args...; kws...)
        end
        function $f(X::AbstractMatrix, Y::AbstractVector, Z::AbstractMatrix, args...; kws...)
            if size(X,1) != 1 && size(X,2) != 1
                throw(ArgumentError("if 2nd arg is column vector, 1st arg must be row or column vector"))
            end
            m, n = length(X), length(Y)
            $f(repeat(transpose(X),outer=(n,1)), repeat(Y,outer=(1,m)), Z, args...; kws...)
        end
    end
end

# Already work: barbs, pcolor, pcolormesh, quiver

# Matplotlib pcolor* functions accept 1d arrays but not ranges
for f in (:pcolor, :pcolormesh)
    @eval begin
        $f(X::AbstractRange, Y::AbstractRange, args...; kws...) = $f([X...], [Y...], args...; kws...)
        $f(X::AbstractRange, Y::AbstractArray, args...; kws...) = $f([X...], Y, args...; kws...)
        $f(X::AbstractArray, Y::AbstractRange, args...; kws...) = $f(X, [Y...], args...; kws...)
    end
end

###########################################################################
# a more pure functional style, that returns the figure but does *not*
# have any display side-effects.  Mainly for use with @manipulate (Interact.jl)

function withfig(actions::Function, f::Figure; clear=true)
    ax_save = gca()
    push!(withfig_fignums, f.number)
    figure(f.number)
    finalizer(close, f)
    try
        if clear && !isempty(f)
            clf()
        end
        actions()
    catch
        rethrow()
    finally
        try
            sca(ax_save) # may fail if axes were overwritten
        catch
        end
        Main.IJulia.undisplay(f)
    end
    return f
end

###########################################################################

using LaTeXStrings
export LaTeXString, latexstring, @L_str, @L_mstr

end # module PythonPlot
