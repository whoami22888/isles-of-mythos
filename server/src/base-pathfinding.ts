export interface GridPoint {
  x: number;
  y: number;
}

export interface PathObstacle extends GridPoint {
  active: boolean;
}

/**
 * Deterministic four-way BFS for a bounded base grid. The goal cell is always
 * traversable so workers can reach their assigned building; the start cell is
 * also allowed even if a building currently occupies it.
 */
export function findBasePath(
  start: GridPoint,
  goal: GridPoint,
  obstacles: readonly PathObstacle[],
  min = -128,
  max = 128,
): GridPoint[] | null {
  const valid = (point: GridPoint): boolean =>
    Number.isSafeInteger(point.x) && Number.isSafeInteger(point.y) &&
    point.x >= min && point.x <= max && point.y >= min && point.y <= max;
  if (!valid(start) || !valid(goal) || !Number.isSafeInteger(min) || !Number.isSafeInteger(max) || min > max) return null;
  if (start.x === goal.x && start.y === goal.y) return [{ ...start }];

  const key = ({ x, y }: GridPoint): string => x + ":" + y;
  const blocked = new Set(obstacles.filter((p) => p.active).map(key));
  blocked.delete(key(start));
  blocked.delete(key(goal));

  const startKey = key(start);
  const goalKey = key(goal);
  const queue: GridPoint[] = [{ ...start }];
  const parent = new Map<string, string | null>([[startKey, null]]);
  const directions: readonly GridPoint[] = [
    { x: 0, y: -1 },
    { x: 1, y: 0 },
    { x: 0, y: 1 },
    { x: -1, y: 0 },
  ];

  for (let head = 0; head < queue.length; head += 1) {
    const current = queue[head];
    if (!current) continue;
    const currentKey = key(current);
    for (const direction of directions) {
      const next = { x: current.x + direction.x, y: current.y + direction.y };
      if (!valid(next)) continue;
      const nextKey = key(next);
      if (blocked.has(nextKey) || parent.has(nextKey)) continue;
      parent.set(nextKey, currentKey);
      if (nextKey === goalKey) {
        const path: GridPoint[] = [next];
        let cursor: string | null = currentKey;
        while (cursor !== null) {
          const [x, y] = cursor.split(":").map(Number);
          path.push({ x: x ?? 0, y: y ?? 0 });
          cursor = parent.get(cursor) ?? null;
        }
        return path.reverse();
      }
      queue.push(next);
    }
  }
  return null;
}

export function nextWorkerWaypoint(base: { x: number; y: number; buildings: readonly { id: string; gridX: number; gridY: number; active: boolean }[]; workers: readonly { creatureId: string; buildingId: string }[] }, creatureId: string, worldX: number, worldY: number, min = -128, max = 128): GridPoint | null {
  if (!Number.isFinite(worldX) || !Number.isFinite(worldY)) return null;
  const worker = base.workers.find((entry) => entry.creatureId === creatureId);
  if (!worker) return null;
  const target = base.buildings.find((building) => building.id === worker.buildingId && building.active);
  if (!target) return null;
  const targetPoint = { x: base.x + target.gridX + 0.5, y: base.y + target.gridY + 0.5 };
  const localStart = { x: Math.floor(worldX - base.x), y: Math.floor(worldY - base.y) };
  if (localStart.x < min || localStart.x > max || localStart.y < min || localStart.y > max) {
    return Math.hypot(targetPoint.x - worldX, targetPoint.y - worldY) < 0.1 ? null : targetPoint;
  }
  const path = findBasePath(localStart, { x: target.gridX, y: target.gridY }, base.buildings.filter((b) => b.id !== target.id).map((b) => ({ x: b.gridX, y: b.gridY, active: b.active })), min, max);
  if (!path) return null;
  const next = path[1] ?? { x: target.gridX, y: target.gridY };
  const waypoint = { x: base.x + next.x + 0.5, y: base.y + next.y + 0.5 };
  return Math.hypot(waypoint.x - worldX, waypoint.y - worldY) < 0.1 ? null : waypoint;
}
