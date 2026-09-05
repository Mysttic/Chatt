# Brand

`icon.svg` is the app icon: two speech bubbles on the project's purple
gradient, `#6B45E0` at the top to `#512BD4` at the bottom.

Everything else is generated from code, so the shapes stay in one place:

| What | Where it goes | Made by |
|---|---|---|
| Android launcher and adaptive icons, the notification icon, the Windows `.ico` | `app/android/…/mipmap-*`, `app/windows/runner/resources` | `app/tool/make_icons.py` |
| The README banner (`docs/promo.png`, 1024x500) | `docs/` | `app/tool/store_assets.py` |

Both scripts need Pillow and are run from `app/`.
