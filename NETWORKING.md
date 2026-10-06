# Networking

## Authoritative model
The server is authoritative for movement validation, combat, inventory, creature ownership, party state, and persistence. The client sends intent and renders authoritative responses.

## Transport
The current gameplay transport is authenticated WebSockets. Payload size and per-connection message rate are bounded.

## Interest management
The server activates nearby wild creatures around connected players and processes active combat on a fixed tick. The client requests nearby chunk regions and unloads chunks outside its local rendering radius.

## Reliability
Combat request IDs are replay-protected. Ranged projectiles are resolved on the server. Capture and taming consume server-validated inventory items. Persistence failures are logged rather than hidden.

## Future production transport
A UDP-oriented or QUIC/LiteNetLib transport abstraction remains a later performance gate and must be selected using measured RTT, packet loss, replication bandwidth, NAT behaviour, and mobile performance data.
