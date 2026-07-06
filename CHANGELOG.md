# Window Switcher on Current Screen Changelog

## [Click at Cursor + List Screens + List Spaces] - {PR_MERGE_DATE}

- Click at Cursor: synthesize a left mouse click at the current cursor position (`CGEvent`; button enum in the helper leaves room for right/double-click variants).
- List Screens: list all displays with resolution/position and Main / Built-in / Virtual flags.
- List Spaces: list Mission Control Spaces (Desktops) per display and flag the current one (read-only, via SkyLight).

## [Initial Version] - {PR_MERGE_DATE}

- Switch Windows on Current Screen: list and focus windows on the screen under the mouse cursor, with a scope toggle for "Current screen" vs "All screens".
- Focus Next Screen / Focus Previous Screen: warp the mouse cursor to the center of the adjacent screen (cyclic).
