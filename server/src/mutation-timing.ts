export interface MutationTiming {
  startedAt: number;
  stages: Record<string, number>;
}

export interface MutationTimingSnapshot {
  totalMs: number;
  stages: Record<string, number>;
}

export type TimingClock = () => number;

export function createMutationTiming(): MutationTiming {
  return { startedAt: 0, stages: {} };
}

export async function measureMutationStage<T>(
  timing: MutationTiming,
  name: string,
  operation: () => Promise<T>,
  now: TimingClock = () => performance.now(),
): Promise<T> {
  const startedAt = now();
  try {
    return await operation();
  } finally {
    timing.stages[name] = now() - startedAt;
  }
}

export async function runTimedMutation<T>(
  timing: MutationTiming,
  operation: () => Promise<T>,
  onSettled: (snapshot: MutationTimingSnapshot) => void,
  now: TimingClock = () => performance.now(),
): Promise<T> {
  timing.startedAt = now();
  try {
    return await operation();
  } finally {
    const snapshot: MutationTimingSnapshot = {
      totalMs: now() - timing.startedAt,
      stages: { ...timing.stages },
    };
    try {
      onSettled(snapshot);
    } catch {
      // Diagnostics must never alter mutation success or error semantics.
    }
  }
}
