# Non-production vertical slice

This scene is an internal server-authority integration scaffold. It is not the
default game scene, an Android distribution scene, or a premium visual claim.
The normal project launch remains `res://scenes/boot.tscn`.

Run it explicitly from a developer checkout:

```sh
godot --path client-godot res://gameplay/vertical_slice.tscn
```

The scene only renders server-authenticated state and sends the supported
`subscribe_chunks` (for the chunk containing the server-reported player
position, refreshed every 10 s because snapshots are not pushed), `move`
(direction-only intent used to walk into the server's 2.5-unit gather range)
and `gather_resource` messages. A Reconnect button remains after handoff. It does not mint inventory,
currency, buildings, quests, or other client-owned state.

For an internal end-to-end auth test, combine this branch with the native auth
branch and set `application/config/internal_gameplay_handoff=true` in a
**temporary developer project override**. The normal boot remains the default:
after player login and WebSocket `auth_ok`, the boot hands the JWT and the same
validated endpoint to this scene in memory. The manual JWT field is hidden on
that path. Do not enable this setting in a distributed APK: the primitive
terrain/player/resource meshes are internal scaffolding below the required
visual floor. A phone-playable build still requires accepted 3D presentation,
an independently verified HTTPS/WSS test backend reachable by the phone, and
physical-device evidence. No endpoint or secret is shipped by this branch.
