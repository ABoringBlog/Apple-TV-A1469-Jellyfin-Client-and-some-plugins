# Task 4 — Home / Library

Stable device candidate: `0.5.30-home2`

## Accepted behavior on Apple TV 3 (12H1006)

- Authenticated Libraries load from the real Jellyfin server.
- Movie libraries open directly to their movie lists.
- TV libraries open directly to their series lists.
- Mixed/unknown video libraries may use the explicit Movies / TV shows chooser.
- Explicit non-video library types are not misrepresented as Movies or TV shows.
- Empty libraries are handled without leaving the navigation model in an invalid state.
- Refresh is an explicit row on the Libraries page.
- A transient Refresh failure preserves the last good Libraries list and selected library state.
- Authentication failure clears the authenticated state and returns to login.
- Refresh is root-only and does not run inside media/detail navigation.
- Library focus is tracked by Jellyfin library ID when the server reorders libraries.
- Media lists are paged at 100 visible items using a 101-item look-ahead request so an exact multiple of 100 does not show a phantom Load more.
- Pagination tolerates overlapping server pages by de-duplicating media by item ID.
- A failed Load more preserves existing media and focus.
- Repeated Load more while a request is already running is rejected by the session busy gate.
- Returning from movie detail restores the prior media list and focus.
- Series -> Seasons -> Episodes -> Detail navigation and Menu back-stack behavior are preserved.
- Closing the session while a library refresh is in flight prevents stale completion from republishing state.
- UI remains functional-first; visual redesign, posters, artwork layout and other presentation work are deferred until the feature set is complete.

## Physical device acceptance

Confirmed on Apple TV 3:
- Archived opens directly to its movie list.
- Movie library opens directly to its movie list.
- Erotic opens directly to its movie list.
- TV library opens directly to its series list.
- Movie detail -> Menu returns correctly.
- Series -> Season -> Episode -> Detail navigation and back behavior are correct.
- Long-library pagination / Load more works.
- Refresh works as the explicit Libraries-page row.
- No new crash was produced during Task 4 acceptance.

The Refresh interaction is intentionally kept as a dedicated row for now. Triggering Refresh while focus remains on another library is not required for Task 4 and may be revisited during the later UI/interaction redesign.

## Stable hashes

Package SHA256:
`3b750454bcbedb40934347cace114e0ca8162e6670d527b3e76319e3bf925a60`

Binary SHA256:
`b1368cbd54908000c678bef7ffbc32bfe3b539135a20c7a4f9f549ed2f33190c`

AppIcon SHA256:
`5236d4c4475054799cf23262b96ebd850651534260c28f4188cd2b0736c98c65`

No whole-device reboot was used for this acceptance. FrontRow restarts only.
