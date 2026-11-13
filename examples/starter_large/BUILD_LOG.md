# How this example was built

Built by `tools/build_starter_level.gd`, deliberately out of order.

Enemies placed before any room exists
  a Grub Hound with chase 4 m < wander 8 m (must be fixed later)
  three Umbral Eyes out in the void, far from any future room
Doors, a floor plate, the exit teleporter and a depot placed with no rooms yet
Fifteen rooms dropped in a scrambled order, unattached and overlapping
  14 to fix, 15 to check with the rooms piled up
Rooms renamed (references follow) and dragged into place one step at a time
  6 to fix, 15 to check after the drag
A stray room with two enemies added, deleted, undone, redone
  the sprites it held are now outside every room: 8 to fix, 15 to check
Corridors added last
  plus one corridor dropped inside the start room by mistake: 8 to fix, 2 to check
The plains: three touching rooms set to 'Fully open', broken up by rock pillars
Triggers, a dialogue, doors that open on a cleared fight, hazards, a bridge and a lift
  8 to fix, 1 to check before the compliance pass
Compliance pass
  deleted 5 enemies standing outside every room and corridor
  moved enemies into the waves of the rooms they stand in
  bad leash fixed: chase 12 m >= wander 8 m
  removed the corridor dropped inside the start room
Result: 0 to fix, 0 to check
