# Vendored CompactSlider

Upstream: <https://github.com/buh/CompactSlider> — MIT, Copyright (c) 2022 Alexey Bukhtin.
Vendored from tag **1.2.1**, byte-identical except for the single patch below.
The upstream `LICENSE` is kept alongside the sources; the `CompactSliderDemo`
target, `Usage.md`, and the CI configuration were not copied.

## Why this is vendored instead of resolved from GitHub

On the macOS 27 SDK, `ProminentCompactSliderStyle.swift` fails to compile:

```
Sources/CompactSlider/ProminentCompactSliderStyle.swift:37:18: error: ambiguous use of 'opacity'
```

`LinearGradient` conforms to both `View` and `ShapeStyle`, and the macOS 27 SDK
made `.opacity(_:)` ambiguous between the two. This single expression blocks the
whole package, and the whole package blocks Ice — it is the only compile error in
the entire project on macOS 27.

The file is dead code for Ice, which never selects a slider style, but SPM compiles
every file in a module so the error cannot be avoided by not using it.

Upstream has not fixed this: <https://github.com/buh/CompactSlider/issues/35> has
been open since 2026-06-30, and 1.2.1 is the final 1.x release — the next tag is
`2.0.0-alpha`, an API rewrite.

Upgrading to 2.x is a real option but a separate one: it drops the trailing-closure
label API, moves the label out of the slider body, and flips several defaults, so
`IceSlider` would have to hand-restore its current appearance and behavior. That is
a product change nobody asked for, and it cannot be visually verified on macOS 14,
15, or 26 from here. It belongs in its own commit, not in the macOS 27 work.

## The patch

One expression in `Sources/CompactSlider/ProminentCompactSliderStyle.swift`,
resolving the gradient through a `Rectangle` fill so the `View.opacity` overload is
selected. The rendered result is identical; no behavior and no appearance changes.

```diff
             .background(
-                LinearGradient(
-                    colors: [lowerColor, upperColor],
-                    startPoint: .leading,
-                    endPoint: .trailing
-                )
+                Rectangle().fill(
+                    LinearGradient(
+                        colors: [lowerColor, upperColor],
+                        startPoint: .leading,
+                        endPoint: .trailing
+                    )
+                )
                 .opacity(useGradientBackground && (configuration.isDragging || configuration.isHovering) ? 0.2 : 0)
             )
```

## Re-vendoring

```sh
git clone --depth 1 --branch 1.2.1 https://github.com/buh/CompactSlider
# copy Package.swift, Sources/, LICENSE, README.md; reapply the patch above
```
