# How this example was built

Built by `tools/build_starter_level.gd` from basic shapes, room boundaries and the navmesh, deliberately out of order.

Enemies placed before there's any floor
  a Grub Hound with chase 4 m < wander 8 m (fixed later)
  three Umbral Eyes out in the void
Every room boundary placed before any floor
  14 to fix, 0 to check, 0 rooms + 0 corridors so far
Doors, a floor plate, the exit teleporter and a depot, still with no floor
Room floors dropped on a pile in random order, then slid into place
  piled up: 15 to fix, 1 to check, 1 rooms + 0 corridors so far
  slid into place: 6 to fix, 17 to check, 15 rooms + 0 corridors so far
A stray floor with two enemies: deleted, undone, redone
  the sprites it held are now off the navmesh: 9 to fix, 17 to check, 15 rooms + 0 corridors so far
Walls in random order, plus one dropped across a doorway by mistake
  101 wall pieces: 8 to fix, 19 to check, 17 rooms + 0 corridors so far
Corridor floors last
  9 to fix, 26 to check, 27 rooms + 0 corridors so far
Rocks on the plains, lights, fireflies, wiring and the rest of the enemies
Compliance pass
  removed the wall dropped across the hound den's doorway
  rooms named after their spaces, the bridge and lift rooms' two sides joined, 10 corridors marked
  deleted 5 enemies standing off the navmesh
  moved enemies into the waves of the rooms they stand in; fixed the leash (chase 12 m >= wander 8 m)
Result: 0 to fix, 0 to check, 15 rooms + 10 corridors so far
