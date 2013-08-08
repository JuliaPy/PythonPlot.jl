# The PyPlot module for Julia

This module provides a Julia interface to the
[matplotlib](http://matplotlib.org/) plotting library from Python, and
specifically to the `matplotlib.pyplot` module.

PyPlot uses the Julia [PyCall](https://github.com/stevengj/PyCall.jl)
package to call matplotlib directly from Julia with little or no
overhead (arrays are passed without making a copy).

This package takes advantage of Julia's [multimedia
I/O](http://docs.julialang.org/en/latest/stdlib/base/#multimedia-i-o)
API to display plots in any Julia graphical backend, including as
inline graphics in [IJulia](https://github.com/JuliaLang/IJulia.jl).
Alternatively, you can use a Python-based graphical matplotlib
backend to support interactive plot zooming etcetera.

(This PyPlot package replaces an earlier package of the same name by
[Junfeng Li](https://github.com/autozimu/), which used PyPlot over a
ZeroMQ socket with IPython.)

## Installation

You will need to have the Python [matplotlib](http://matplotlib.org/)
library installed on your machine in order to use PyPlot.

Once matplotlib is installed, then you can just use
`Pkg.add("PyPlot")` in Julia to install PyPlot and its dependencies.

**Note:** Julia version 0.2 (or a recent pre-release version thereof)
is required to use PyPlot.

## Basic usage

Once matplotlib and PyPlot is installed, and you are using a
graphics-capable Julia environment such as IJulia, you can simply type
`using PyPlot` and begin calling functions in the
[matplotlib.pyplot](http://matplotlib.org/api/pyplot_api.html) API.
For example:

```
Using PyPlot
x = linspace(0,2*pi,1000); y = sin(3*x + 4*cos(2*x));
plot(x, y, color="red", linewidth=2.0, linestyle="--")
title("A sinusoidally modulated sinusoid")
```

In general, all of the arguments, including keyword arguments, are
exactly the same as in Python.  (With minor translations, of course,
e.g. Julia uses `true` and `nothing` instead of Python's `True` and
`None`.)

The full matplotlib.pyplot API is far too extensive to describe here;
see the [matplotlib.pyplot documentation for more
information](http://matplotlib.org/api/pyplot_api.html)

Only the currently documented matplotlib.pyplot API is exported.  To use
other functions in the module, you can also call `matplotlib.pyplot.foo(...)`
as `plt.foo(...)`.  For example, `plt.plot(x, y)` also works.  (And
the raw `PyObject`s for the matplotlib and pyplot modules are accessible
as `PyPlot.matplotlib` and `PyPlot.pltm`, respectively.)

## Figure objects

You can get the current figure as a `PyFigure` object (a wrapper
around `matplotlib.pyplot.Figure`) by calling `gcf()`.  

The `PyFigure` type supports Julia's [multimedia I/O
API](http://docs.julialang.org/en/latest/stdlib/base/#multimedia-i-o),
so you can use `display(fig)` to show a `fig::PyFigure` and
`writemime(io, mime, fig)` to write it to a given `mime` type string
(e.g. `"image/png"` or `"application/pdf"`) that is supported by the
matplotlib backend.

## Changing the graphics backend

PyPlot can use any Julia graphics backend capable of displaying PNG,
SVG, or PDF images, such as the IJulia environment.  To use a
different backend, simply call `pushdisplay` with the desired
`Display`; see the [Julia multimedia display
API](http://docs.julialang.org/en/latest/stdlib/base/#multimedia-i-o)
for more detail.

On the other hand, you may wish to use one of the Python matplotlib
backends to open an interactive window for each plot (for interactive
zooming, panning, etcetera).  You can do this by importing the PyCall
module and using its `pygui` function to set a Python backend:

```
using PyCall
pygui()
```

This must be done *before* importing the PyPlot module, and picks a
default Python GUI toolkit.  You can also call `pygui(gui)` to pick a
specific toolkit; `gui` can currently be one of `:wx`, `:gtk`, or
`:qt` in order to specify [wxWidgets](http://www.wxwidgets.org/),
[GTK+](http://www.gtk.org/), or [Qt](http://qt-project.org/) (via the
[PyQt4](http://wiki.python.org/moin/PyQt4) or
[PySide](http://qt-project.org/wiki/PySide), respectively.  (Obviously,
you must have installed one of these toolkits for Python first.)

If no Julia graphics backend is available, PyPlot will default to
a `pygui` backend.  Conversely, if you have started a `pygui` backend
for some other reason, but wish to use PyPlot with Julia graphics,
just run `pygui(:default)` before importing PyPlot.

## Author

This module was written by [Steven G. Johnson](http://math.mit.edu/~stevenj/).
