# SC BOXING

## Open the project
1. Extract the ZIP file.
2. Open Godot 4 and choose **Import**.
3. Select `project.godot`.
4. Press **F5** to run the game.

## Controls
- **A / D** — Move left and right on the fighting plane.
- **W / Up** — Jump.
- **S / Down** — Crouch.
- **U** — Crouching-only low punch.
- **Space** — Dash.
- **J / K / L** — Jab, cross punch, and uppercut.
- **I** — Block.

## Main menu and progress
- Choose **Campaign** to fight through the original four-fight roster.
- Choose **Rival**, **Vinchita**, or **Chicho Medina** for an exhibition fight against that opponent.
- Select **Save Progress** during a fight to save the current round, score, timer, and both fighters' health and stamina.
- **Continue Saved Progress** restores the saved fight. Progress is stored locally in Godot's `user://boxing_progress.json` file.

## Combat visual effects
- Hit sparks, block flashes, dash trails, jump and landing dust, healing particles, critical slashes, and knockout smoke use the Kenney Particle Pack sprite assets from Godot's Asset Library.
- The included Kenney Particle Pack is CC0: `addons/kenney_particle_pack/LICENSE.txt`.

## Audio effects
- Original local WAV effects are included in `assets/audio/` and are loaded by the `SoundManager` autoload.
- The game plays separate sounds for menu hover/clicks, punches and impacts, blocks, footsteps, dashes, round bells, the final countdown, special abilities, save confirmation, knockouts, and victory/defeat/draw.
- A low-volume ring-crowd ambience runs during fights and stops when returning to the main menu.

## Project layout
- `Scenes/` — Original game and fighter scenes.
- `scripts/combat/` — Player movement and combat logic.
- `scripts/managers/` — Fight flow, HUD, menu, save/load management, and shared sound playback.
- `scripts/AI/` — Opponent behavior.
- `assets/` — Original sprite images, shaders, and the new audio effects.

## Asset credits
- Kenney Particle Pack by Kenney, packaged for Godot by Calinou. CC0 1.0 Universal. Godot Asset Library: https://godotengine.org/asset-library/asset/784

## Notes
This build uses a side-on fighting plane with horizontal movement, jump, crouch, and a crouching-only low punch.
