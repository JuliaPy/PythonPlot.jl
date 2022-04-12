# Conveniences for working with and displaying matplotlib colormaps,
# integrating with the Julia Colors package

using Colors
export ColorMap, get_cmap, register_cmap, get_cmaps

########################################################################
# Wrapper around colors.Colormap type:

mutable struct ColorMap
    o::Py
end

PythonCall.Py(c::ColorMap) = getfield(c, :o)
PythonCall.pyconvert(::Type{ColorMap}, o::Py) = ColorMap(o)
==(c::ColorMap, g::ColorMap) = Py(c) == Py(g)
==(c::Py, g::ColorMap) = c == Py(g)
==(c::ColorMap, g::Py) = Py(c) == g
hash(c::ColorMap) = hash(Py(c))
PythonCall.pycall(c::ColorMap, args...; kws...) = pycall(Py(c), args...; kws...)
(c::ColorMap)(args...; kws...) = pycall(Py(c), args...; kws...)
Base.Docs.doc(c::ColorMap) = Base.Docs.Text(pyconvert(String, Py(c).__doc__))

# Note: using `Union{Symbol,String}` produces ambiguity.
Base.getproperty(c::ColorMap, s::Symbol) = getproperty(Py(c), s)
Base.getproperty(c::ColorMap, s::AbstractString) = getproperty(Py(c), Symbol(s))
Base.setproperty!(c::ColorMap, s::Symbol, x) = setproperty!(Py(c), s, x)
Base.setproperty!(c::ColorMap, s::AbstractString, x) = setproperty!(Py(c), Symbol(s), x)
Base.propertynames(c::ColorMap) = propertynames(Py(c))
Base.hasproperty(c::ColorMap, s::Union{Symbol,AbstractString}) = hasproperty(Py(c), s)

function show(io::IO, c::ColorMap)
    print(io, "ColorMap \"$(pyconvert(String, c.name))\"")
end

# all Python dependencies must be initialized at runtime (not when precompiled)
const colorsm = PythonCall.pynew()
const cm = PythonCall.pynew()
const LinearSegmentedColormap = PythonCall.pynew()
const cm_get_cmap = PythonCall.pynew()
const cm_register_cmap = PythonCall.pynew()
const ScalarMappable = PythonCall.pynew()
const Normalize01 = PythonCall.pynew()
function init_colormaps()
    PythonCall.pycopy!(colorsm, pyimport("matplotlib.colors"))
    PythonCall.pycopy!(cm, pyimport("matplotlib.cm"))

    # pytype_mapping(colorsm.Colormap, ColorMap)

    PythonCall.pycopy!(LinearSegmentedColormap, colorsm.LinearSegmentedColormap)

    PythonCall.pycopy!(cm_get_cmap, cm.get_cmap)
    PythonCall.pycopy!(cm_register_cmap, cm.register_cmap)

    PythonCall.pycopy!(ScalarMappable, cm.ScalarMappable)
    PythonCall.pycopy!(Normalize01, pycall(colorsm.Normalize; vmin=0,vmax=1))
end

########################################################################
# ColorMap constructors via colors.LinearSegmentedColormap

# most general constructors using RGB arrays of triples, defined
# as for matplotlib.colors.LinearSegmentedColormap
ColorMap(name::Union{AbstractString,Symbol},
         r::AbstractVector{Tuple{T,T,T}},
         g::AbstractVector{Tuple{T,T,T}},
         b::AbstractVector{Tuple{T,T,T}},
         n=max(256,length(r),length(g),length(b)), gamma=1.0) where {T<:Real} =
    ColorMap(name, r,g,b, Array{Tuple{T,T,T}}(undef, 0), n, gamma)

# as above, but also passing an alpha array
function ColorMap(name::Union{AbstractString,Symbol},
                  r::AbstractVector{Tuple{T,T,T}},
                  g::AbstractVector{Tuple{T,T,T}},
                  b::AbstractVector{Tuple{T,T,T}},
                  a::AbstractVector{Tuple{T,T,T}},
                  n=max(256,length(r),length(g),length(b),length(a)),
                  gamma=1.0) where T<:Real
    segmentdata = Dict("red" => r, "green" => g, "blue" => b)
    if !isempty(a)
        segmentdata["alpha"] = a
    end
    ColorMap(LinearSegmentedColormap(name, segmentdata, n, gamma))
end

# create from an array c, assuming linear mapping from [0,1] to c
function ColorMap(name::Union{AbstractString,Symbol},
                  c::AbstractVector{T}, n=max(256, length(c)), gamma=1.0) where T<:Colorant
    nc = length(c)
    if nc == 0
        throw(ArgumentError("ColorMap requires a non-empty Colorant array"))
    end
    r = Array{Tuple{Float64,Float64,Float64}}(undef, nc)
    g = similar(r)
    b = similar(r)
    a = T <: TransparentColor ?
        similar(r) : Array{Tuple{Float64,Float64,Float64}}(undef, 0)
    for i = 1:nc
        x = (i-1) / (nc-1)
        if T <: TransparentColor
            rgba = convert(RGBA{Float64}, c[i])
            r[i] = (x, rgba.r, rgba.r)
            b[i] = (x, rgba.b, rgba.b)
            g[i] = (x, rgba.g, rgba.g)
            a[i] = (x, rgba.alpha, rgba.alpha)
        else
            rgb = convert(RGB{Float64}, c[i])
            r[i] = (x, rgb.r, rgb.r)
            b[i] = (x, rgb.b, rgb.b)
            g[i] = (x, rgb.g, rgb.g)
        end
    end
    ColorMap(name, r,g,b,a, n, gamma)
end

ColorMap(c::AbstractVector{T},
         n=max(256, length(c)), gamma=1.0) where {T<:Colorant} =
    ColorMap(string("cm_", hash(c)), c, n, gamma)

function ColorMap(name::Union{AbstractString,Symbol}, c::AbstractMatrix{T},
                  n=max(256, size(c,1)), gamma=1.0) where T<:Real
    if size(c,2) == 3
        return ColorMap(name,
                        [RGB{T}(c[i,1],c[i,2],c[i,3]) for i in 1:size(c,1)],
                        n, gamma)
    elseif size(c,2) == 4
        return ColorMap(name,
                        [RGBA{T}(c[i,1],c[i,2],c[i,3],c[i,4])
                         for i in 1:size(c,1)],
                        n, gamma)
    else
        throw(ArgumentError("color matrix must have 3 or 4 columns"))
    end
end

ColorMap(c::AbstractMatrix{T}, n=max(256, size(c,1)), gamma=1.0) where {T<:Real} =
    ColorMap(string("cm_", hash(c)), c, n, gamma)

########################################################################

@doc LazyHelp(cm_get_cmap) get_cmap() = ColorMap(cm_get_cmap())
get_cmap(name::AbstractString) = ColorMap(pycall(cm_get_cmap(name)))
get_cmap(name::AbstractString, lut::Integer) = ColorMap(cm_get_cmap(name, lut))
get_cmap(c::ColorMap) = c
ColorMap(name::AbstractString) = get_cmap(name)

@doc LazyHelp(cm_register_cmap) register_cmap(c::ColorMap) = cm_register_cmap(c)
register_cmap(n::AbstractString, c::ColorMap) = cm_register_cmap(n,c)

# convenience function to get array of registered colormaps
get_cmaps() =
    ColorMap[get_cmap(c) for c in
             sort(filter!(c -> !endswith(c, "_r"),
                          [pyconvert(String, c) for c in PyPlot.cm.datad]),
                  by=lowercase)]

########################################################################
# display of ColorMaps as a horizontal color bar in SVG

function Base.show(io::IO, ::MIME"image/svg+xml", cs::AbstractVector{ColorMap})
    n = 256
    nc = length(cs)
    a = range(0; stop=1, length=n)
    namelen = mapreduce(c -> length(c.name), max, cs)
    width = 0.5
    height = 5
    pad = 0.5
    write(io,
        """
        <?xml version"1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN"
         "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg xmlns="http://www.w3.org/2000/svg" version="1.1"
             width="$(n*width+1+namelen*4)mm" height="$((height+pad)*nc)mm"
             shape-rendering="crispEdges">
        """)
    for j = 1:nc
        c = cs[j]
        y = (j-1) * (height+pad)
        write(io, """<text x="$(n*width+1)mm" y="$(y+3.8)mm" font-size="3mm">$(c.name)</text>""")
        rgba = PyArray(pycall(ScalarMappable; cmap=c, norm=Normalize01).to_rgba(a))
        for i = 1:n
            write(io, """<rect x="$((i-1)*width)mm" y="$(y)mm" width="$(width)mm" height="$(height)mm" fill="#$(hex(RGB(rgba[i,1],rgba[i,2],rgba[i,3])))" stroke="none" />""")
        end
    end
    write(io, "</svg>")
end

function Base.show(io::IO, m::MIME"image/svg+xml", c::ColorMap)
    show(io, m, [c])
end

########################################################################
