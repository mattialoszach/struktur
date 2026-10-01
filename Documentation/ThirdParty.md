# Third-party notices

Struktur includes [SwiftMath 1.7.3](https://github.com/mgriebling/SwiftMath/tree/1.7.3) for offline native LaTeX math rendering. It is the only package dependency and has no transitive package dependencies. The exact revision is pinned in `Package.resolved`.

SwiftMath is MIT licensed. Its copyright and license ship in `Struktur_Struktur.bundle/SwiftMath-LICENSE.txt`. The bundled math fonts retain their upstream licenses inside `SwiftMath_SwiftMath.bundle/mathFonts.bundle` (including the GUST Font License and SIL Open Font License notices). Packaging copies both resource bundles into the app.

The editor uses the Latin Modern math font and caches rendered results. No script engine, remote renderer, downloaded fonts, or runtime network requests are involved. Unsupported expressions remain editable LaTeX source.
