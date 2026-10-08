import type Phaser from "phaser";

export type MobileAction = "attack" | "dodge" | "capture" | "gather";

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

export class TouchControls {
  public movement = { x: 0, y: 0 };
  private readonly joystickBase: Phaser.GameObjects.Graphics;
  private readonly joystickKnob: Phaser.GameObjects.Graphics;
  private readonly actionButtons = new Map<MobileAction, Phaser.GameObjects.Text>();
  private actionHandler?: (action: MobileAction) => void;
  private activePointerId?: number;
  private centerX = 0;
  private centerY = 0;
  private radius = 64;

  constructor(private readonly scene: Phaser.Scene) {
    this.joystickBase = scene.add.graphics().setScrollFactor(0).setDepth(1400);
    this.joystickKnob = scene.add.graphics().setScrollFactor(0).setDepth(1401);

    const actions: Array<[MobileAction, string]> = [
      ["attack", "ATK"],
      ["dodge", "DODGE"],
      ["capture", "CAP"],
      ["gather", "GATHER"],
    ];
    for (const [action, label] of actions) {
      const button = scene.add.text(0, 0, label, {
        fontFamily: "sans-serif",
        fontSize: "12px",
        color: "#ffffff",
        backgroundColor: "#17314dcc",
        padding: { left: 9, right: 9, top: 8, bottom: 8 },
      }).setOrigin(0.5).setScrollFactor(0).setDepth(1402).setInteractive({ useHandCursor: true });
      button.on("pointerdown", () => this.actionHandler?.(action));
      this.actionButtons.set(action, button);
    }

    scene.input.on("pointerdown", (pointer: Phaser.Input.Pointer) => {
      if (!pointer.wasTouch || this.activePointerId !== undefined) return;
      const distance = Phaser.Math.Distance.Between(pointer.x, pointer.y, this.centerX, this.centerY);
      if (distance <= this.radius * 1.35) {
        this.activePointerId = pointer.id;
        this.updateJoystick(pointer.x, pointer.y);
      }
    });
    scene.input.on("pointermove", (pointer: Phaser.Input.Pointer) => {
      if (pointer.id === this.activePointerId) this.updateJoystick(pointer.x, pointer.y);
    });
    const release = (pointer: Phaser.Input.Pointer) => {
      if (pointer.id !== this.activePointerId) return;
      this.activePointerId = undefined;
      this.movement = { x: 0, y: 0 };
      this.renderKnob(this.centerX, this.centerY);
    };
    scene.input.on("pointerup", release);
    scene.input.on("pointerupoutside", release);
  }

  onAction(handler: (action: MobileAction) => void): void {
    this.actionHandler = handler;
  }

  layout(joystickX: number, joystickY: number, radius: number, actionX: number, actionY: number): void {
    this.centerX = joystickX;
    this.centerY = joystickY;
    this.radius = radius;
    this.joystickBase.clear();
    this.joystickBase.fillStyle(0x07131f, 0.72);
    this.joystickBase.fillCircle(joystickX, joystickY, radius);
    this.joystickBase.lineStyle(2, 0xffffff, 0.7);
    this.joystickBase.strokeCircle(joystickX, joystickY, radius);

    const compact = this.scene.scale.width < 720;
    const gap = compact ? 46 : 54;
    const buttons = [...this.actionButtons.values()];
    const positions = [
      [actionX, actionY],
      [actionX - gap, actionY - gap],
      [actionX, actionY - gap * 2],
      [actionX - gap, actionY - gap * 3],
    ];
    buttons.forEach((button, index) => {
      const position = positions[index] ?? positions[0];
      button.setPosition(position[0], position[1]);
    });
    this.renderKnob(this.centerX, this.centerY);
  }

  private updateJoystick(pointerX: number, pointerY: number): void {
    const normalized = normalizeStick(pointerX - this.centerX, pointerY - this.centerY, this.radius);
    this.movement = normalized;
    this.renderKnob(
      this.centerX + normalized.x * this.radius,
      this.centerY + normalized.y * this.radius,
    );
  }

  private renderKnob(x: number, y: number): void {
    this.joystickKnob.clear();
    this.joystickKnob.fillStyle(0x2f80ed, 0.82);
    this.joystickKnob.fillCircle(x, y, Math.max(22, this.radius * 0.38));
    this.joystickKnob.lineStyle(2, 0xffffff, 0.9);
    this.joystickKnob.strokeCircle(x, y, Math.max(22, this.radius * 0.38));
  }
}
