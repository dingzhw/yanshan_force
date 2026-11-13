"""Stage selected licensed assets and game source outside the sync directory."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]


def _default_runtime() -> Path:
    cfg = ROOT / "docs/runtime-local.json"
    if cfg.exists():
        data = json.loads(cfg.read_text(encoding="utf-8"))
        if data.get("runtime_root"):
            return Path(data["runtime_root"])
    local = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData/Local"))
    return local / "Temp" / "drz-english-shooter-20261103"


RUNTIME = Path(os.environ.get("DRZ_RUNTIME") or _default_runtime())


def copy_asset(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != source.read_bytes():
        raise RuntimeError(f"Preserving differing existing asset: {target}")
    if not target.exists():
        shutil.copy2(source, target)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    assets = ROOT / "game/assets"
    nature = ROOT / "third_party/kenney-nature-kit/Models/GLTF format"
    survival = ROOT / "third_party/kenney-survival-kit/Models/GLB format"
    for name in ("tree_pineTallA", "tree_pineRoundD", "tree_oak", "tree_default_dark", "rock_largeA", "rock_largeC", "rock_tallC", "statue_obelisk", "cliff_steps_rock", "cliff_rock", "rock_smallFlatA", "rock_smallFlatB", "bridge_wood", "bridge_stone", "fence_simple", "fence_planksDouble", "flower_redA", "flower_redB", "flower_purpleA", "flower_yellowA", "flower_yellowB", "mushroom_redGroup", "mushroom_redTall", "mushroom_tanGroup", "lily_large", "lily_small", "plant_bushDetailed", "plant_flatTall"):
        copy_asset(nature / f"{name}.glb", assets / "nature" / f"{name}.glb")
    for name in ("tent-canvas", "barrel", "box-large", "box-large-open", "box", "chest", "patch-grass-large", "grass-large", "structure-roof", "structure-metal-wall", "signpost", "fence-fortified", "workbench"):
        copy_asset(survival / f"{name}.glb", assets / "survival" / f"{name}.glb")
    for folder, destination in ((nature / "Textures", assets / "nature/Textures"), (survival / "Textures", assets / "survival/Textures")):
        if folder.exists():
            for source in folder.iterdir():
                if source.is_file():
                    copy_asset(source, destination/source.name)
    fps = ROOT / "third_party/kenney-fps"
    for name in ("blaster", "enemy-flying", "wall-low", "wall-high"):
        copy_asset(fps / f"models/{name}.glb", assets / f"fps/{name}.glb")
    copy_asset(fps / "models/Textures/colormap.png", assets / "fps/Textures/colormap.png")
    for filename in ("blaster.ogg", "blaster_repeater.ogg", "enemy_attack.ogg", "enemy_destroy.ogg", "enemy_hurt.ogg", "jump_a.ogg", "land.ogg", "walking.ogg", "weapon_change.ogg"):
        copy_asset(fps / "sounds" / filename, assets / "fps/sounds" / filename)
    copy_asset(ROOT / "third_party/noto-sans-sc/NotoSansSC[wght].ttf", assets / "font/NotoSansSC.ttf")
    for source, target in ((fps/"LICENSE.md", "Kenney-FPS-MIT.txt"), (ROOT/"third_party/kenney-nature-kit/License.txt", "Nature-CC0.txt"), (ROOT/"third_party/kenney-survival-kit/License.txt", "Survival-CC0.txt"), (ROOT/"third_party/noto-sans-sc/OFL.txt", "NotoSansSC-OFL.txt"), (ROOT/"docs/licenses/GODOT_LICENSE.txt", "Godot-MIT.txt"), (ROOT/"docs/licenses/GODOT_COPYRIGHT.txt", "Godot-COPYRIGHT.txt")):
        copy_asset(source, ROOT/"game/licenses"/target)
    destination = RUNTIME / "yanshan-v01"
    assert destination.parent == RUNTIME and not destination.is_symlink() and not destination.is_junction()
    destination.mkdir(parents=True, exist_ok=True)
    count = 0
    for source in (ROOT/"game").rglob("*"):
        if not source.is_file() or any(p in {".godot", ".git", "__pycache__"} for p in source.parts):
            continue
        relative = source.relative_to(ROOT/"game")
        target = destination/relative
        if target.exists():
            old = target.read_bytes()
            if old == source.read_bytes():
                continue
            backup = RUNTIME/"stage-backups"/hashlib.sha256(old).hexdigest()/relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                backup.write_bytes(old)
            if target.read_bytes() != old:
                raise RuntimeError(f"Concurrent runtime change: {target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source,target)
        count += 1
    print(json.dumps({"staged":str(destination),"changed_files":count},ensure_ascii=False))


if __name__ == "__main__":
    main()
