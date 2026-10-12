# SasBoatFixes

Boat handling fixes for Ships At Sea, as a UE4SS Lua mod, plus the recorder used to find them.

## What it fixes

**Boats listing with people aboard.** A boat carrying crew or passengers could heel over in a turn
and then stay heeled for as long as it kept its speed, slowly pulling itself off course.

Crew and passengers press down on the deck where they stand. Upright, that push does nothing
noticeable. Once a turn heels the hull over at speed, the hull has very little force pulling it back,
and the small push from people standing on the low side is enough to hold it there. On the class 3
service vessel this held 17 degrees of list at 26 knots with six people aboard, and the boat levelled
within five seconds of the push being switched off.

The game already switches this push off for the player's own character. The mod does the same for
every other character. Six people are about 600 kg on a 131,800 kg boat, so nothing else about the
boat's handling changes noticeably.

The fix removes what holds a boat over. It does not change the hulls' weak righting force at speed,
which is the underlying cause.

## Keys

- **F4** toggles the list fix. It is on by default and comes back on after a game restart.
- **F9** starts and stops a physics recording of the boat being driven.

## The recorder

F9 writes `boatlog.txt` in the mod's folder under the game's `ue4ss\Mods\SasBoatFixes`:

- once, at the start: the boat's mass, centre of mass, inertia, damping, buoyancy settings, what is
  attached to it, and who is aboard and where they stand;
- four times a second: roll, pitch, heading, speed, mass, centre of mass, the sideways push of the
  people aboard, and whether the list fix is on.

The recorder only reads. It is there to diagnose other handling problems the same way this one was.

## Install

Requires the UE4SS experimental build in the game's `SAS\Binaries\Win64` folder (the game is on
Unreal Engine 5.7).

Copy the `SasBoatFixes` folder into `SAS\Binaries\Win64\ue4ss\Mods`, or run:

```
.\deploy.ps1
```

`deploy.ps1` takes `-GameDir` if the game is not in the default Steam library path. In game,
Ctrl+R reloads UE4SS Lua mods without a restart.

## Notes

- Tested in solo play. The fix changes a movement setting on characters locally; its effect in
  multiplayer is untested.
- The mod does all its work from a single timer on the game thread.

## License

MIT. See `LICENSE`.
