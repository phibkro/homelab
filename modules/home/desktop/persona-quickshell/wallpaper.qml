//@ pragma QmlImportPath: "."
//@ pragma Env QSG_RENDER_LOOP=threaded
pragma ComponentBehavior: Bound
import Quickshell
import "./Widgets" as Wid

/*
  The animated wallpaper owns a separate Quickshell process. Stopping this
  entrypoint releases its images, shaders, render loop, and Cava state without
  taking down Persona's desktop widgets.
*/
ShellRoot {
    Variants {
        model: Quickshell.screens
        Scope {
            id: scopeRoot
            required property ShellScreen modelData
            Wid.WallpaperEngine {
                modelData: scopeRoot.modelData
            }
        }
    }
}
