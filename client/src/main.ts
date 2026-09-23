import Phaser from "phaser";
import { GameState } from "./game-state.js";

class BootScene extends Phaser.Scene {
  private state = GameState.Menu;
  private elapsed = 0;

  constructor() {
    super("boot");
  }

  create(): void {
    this.cameras.main.setBackgroundColor("#07131f");

    this.add.text(32, 32, "ISLES OF MYTHOS: SUNKEN TIDES", {
      fontFamily: "sans-serif",
      fontSize: "28px",
      color: "#ffffff",
    });

    this.add.text(32, 78, "Engine Foundation • Step 1", {
      fontFamily: "sans-serif",
      fontSize: "16px",
      color: "#b7c9d6",
    });

    this.add.text(32, 120, this.state, {
      fontFamily: "sans-serif",
      fontSize: "20px",
      color: "#6fd3ff",
    });
  }

  update(_time: number, delta: number): void {
    this.elapsed += delta;

    if (this.elapsed >= 1000) {
      this.elapsed = 0;
      this.registry.set("gameState", this.state);
    }
  }
}

export const gameConfig: Phaser.Types.Core.GameConfig = {
  type: Phaser.AUTO,
  parent: "game",
  width: 1280,
  height: 720,
  backgroundColor: "#07131f",
  scale: {
    mode: Phaser.Scale.RESIZE,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
  scene: [BootScene],
  render: {
    antialias: true,
    powerPreference: "high-performance",
  },
};

new Phaser.Game(gameConfig);
