# The menu behind `GridSim.bat` at the repo root: one Julia session, a numbered
# list of the eight windows, and back to the list when a window is closed. Run
# from the repo root:
#
#     julia --project=ui ui/scripts/start.jl
#
# One session rather than one per window because `using GridSimUI` is the
# expensive part (about 13 s); once it is paid, a window opens in a few seconds.
# Labels are ASCII only — the console this runs in is cmd's, and its code page is
# not something to bet on.

const UI_DIR = normpath(joinpath(@__DIR__, ".."))

# `ui/Manifest.toml` is gitignored, so a fresh clone has to resolve before the
# package can load (ui/README.md, "Setup").
if !isfile(joinpath(UI_DIR, "Manifest.toml"))
    println("First run: installing the UI's packages. This takes several minutes...")
    import Pkg
    Pkg.instantiate()
end

println("Loading GridSim (the first start after an update can take a few minutes)...")
using GridSimUI, GridSim

const WINDOWS = [
    ("Live frequency after a generator trip (one-bus system)", () -> launch()),
    ("Live three-machine network (trip machines and lines)",  () -> launch(three_machine_ring())),
    ("Scenario editor (draw your own grid)",                  () -> editor(three_machine_ring())),
    ("Playback: fast tier vs network tier",                   () -> playback()),
    ("Playback: voltages, classical vs detailed machines",    () -> voltage_playback()),
    ("Low-inertia study (inverters)",                         () -> low_inertia_playback()),
    ("Frequency screen (single outages)",                     () -> frequency_screen()),
    ("Double outages",                                        () -> double_outages()),
]

function menu()
    while true
        println()
        println("GridSim - pick a window (close it to come back here)")
        for (i, (label, _)) in enumerate(WINDOWS)
            println("  ", i, ". ", label)
        end
        println("  q. Quit")
        print("> ")
        answer = strip(readline())
        (isempty(answer) && eof(stdin)) && return
        lowercase(answer) in ("q", "quit", "exit") && return
        i = tryparse(Int, answer)
        if i === nothing || !(1 <= i <= length(WINDOWS))
            println("Type a number from 1 to ", length(WINDOWS), ", or q.")
            continue
        end
        label, open_window = WINDOWS[i]
        println("Opening: ", label, " ...")
        try
            wait_for_close(open_window())
        catch err
            err isa InterruptException && return
            println("That window failed:")
            showerror(stdout, err, catch_backtrace())
            println()
        end
    end
end

menu()
