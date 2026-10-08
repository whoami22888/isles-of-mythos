export interface MobileLayout {
  joystickX: number;
  joystickY: number;
  radius: number;
  actionX: number;
  actionY: number;
  statusX: number;
  statusY: number;
}

export function clampUnit(value: number): number {
  return Math.max(-1, Math.min(1, value));
}

export function normalizeStick(dx: number, dy: number, radius: number): { x: number; y: number } {
  if (!Number.isFinite(radius) || radius <= 0) return { x: 0, y: 0 };
  const length = Math.hypot(dx, dy);
  if (length === 0) return { x: 0, y: 0 };
  const scale = Math.min(1, radius / length);
  return {
    x: clampUnit((dx * scale) / radius),
    y: clampUnit((dy * scale) / radius),
  };
}

function readSafeAreaInsets(): { top: number; right: number; bottom: number; left: number } {
  if (typeof document === "undefined") return { top: 0, right: 0, bottom: 0, left: 0 };
  const probe = document.createElement("div");
  probe.style.cssText = "position:fixed;inset:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);pointer-events:none;visibility:hidden";
  document.body.appendChild(probe);
  const style = getComputedStyle(probe);
  const insets = {
    top: Number.parseFloat(style.paddingTop) || 0,
    right: Number.parseFloat(style.paddingRight) || 0,
    bottom: Number.parseFloat(style.paddingBottom) || 0,
    left: Number.parseFloat(style.paddingLeft) || 0,
  };
  probe.remove();
  return insets;
}

export function getMobileLayout(width: number, height: number): MobileLayout {
  const safe = readSafeAreaInsets();
  const compact = width < 720 || height < 500;
  const radius = Math.max(48, Math.min(compact ? 68 : 82, Math.min(width, height) * 0.12));
  const margin = Math.max(18, Math.min(44, Math.min(width, height) * 0.045));
  const bottom = height - safe.bottom - margin - radius;
  return {
    joystickX: safe.left + margin + radius,
    joystickY: bottom,
    radius,
    actionX: width - safe.right - margin - radius,
    actionY: bottom,
    statusX: margin,
    statusY: Math.max(safe.top + 10, height * 0.12),
  };
}
