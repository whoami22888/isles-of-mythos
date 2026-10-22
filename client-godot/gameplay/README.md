# Non-production vertical slice

This scene is an internal server-authority integration scaffold. It is not the
default game scene, an Android distribution scene, or a premium visual claim.
The normal project launch remains `res://scenes/boot.tscn`.

Run it explicitly from a developer checkout:

```sh
godot --path client-godot res://gameplay/vertical_slice.tscn
```

The scene only renders server-authenticated state and sends the supported
`subscribe_chunks` and `gather_resource` messages. It does not mint inventory,
currency, buildings, quests, or other client-owned state.
