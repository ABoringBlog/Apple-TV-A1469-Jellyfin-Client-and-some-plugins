# Task 3 — Login / Token Persistence

Stable device candidate: `0.5.28-directlibrary1`

## Accepted behavior on Apple TV 3 (12H1006)

- Real Jellyfin username/password login succeeds against Jellyfin 12.
- Session credential is persisted without persisting the password.
- Re-entering Jellyfin restores the session without asking for the password again.
- FrontRow restart preserves the saved session and Jellyfin restores directly to the authenticated Libraries view.
- Invalid/expired authentication returns to the login page and clears the saved credential.
- Network/transport failures do not erase a structurally valid saved credential.
- Explicit Sign out returns to the login page and, after leaving and reopening Jellyfin, the session is not restored.
- Server or username changes invalidate the locally persisted credential.
- Closing Jellyfin does not revoke the saved session.
- Token data is not placed in URLs, UI snapshots, test output, or normal logs.
- Jellyfin 12 authenticated requests use the Authorization MediaBrowser Token field rather than X-Emby-Token.
- Typed libraries open directly: movie libraries go straight to movies, TV libraries go straight to series. The intermediate type chooser remains only for mixed/unknown libraries.
- BackRow remote state is reset across page changes so a swallowed Select release on 12H1006 cannot turn the next physical press into a hold.
- Menu navigation remains functional.

## Device acceptance notes

Physical validation confirmed:
- Real Libraries are visible after login.
- Archived, movie and erotic movie libraries open directly to their content lists.
- TV library opens directly to its series list.
- After FrontRow restart, Jellyfin restores without a password prompt.
- After explicit Sign out, leaving and reopening Jellyfin remains on the login page.

## Stable hashes

Package SHA256:
`06b289dc8954524db69d15f5fe3aa21f86e94836bcb37b8b3c5116ff79841586`

Binary SHA256:
`48c429e9d0c36f74bc447358f5920f842cb3f01ea0962fd345ab889038a047b7`

AppIcon SHA256:
`5236d4c4475054799cf23262b96ebd850651534260c28f4188cd2b0736c98c65`

No whole-device reboot was used for this acceptance. FrontRow restarts only.
