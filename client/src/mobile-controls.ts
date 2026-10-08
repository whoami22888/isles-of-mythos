import Phaser from "phaser";
import { getMobileLayout, normalizeStick } from "./mobile-layout.js";
import type { MobileLayout } from "./mobile-layout.js";

export type MobileAction = "attack" | "dodge" | "capture" | "gather";

export { getMobileLayout, normalizeStick };
export type { MobileLayout };

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
