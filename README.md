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

**The wake vanishing when you leave the helm.** A boat's wake is drawn only over a square of water
the game keeps centred on the boat while someone is at the helm. Leave the helm under way and the
square stays behind; the boat sails out of it within seconds and its wake disappears. While your boat
has nobody at the helm and you are within 200 m of it, the mod slides that square along with the boat,
a short step at a time, so the wake keeps drawing. Jumping the square onto the boat fills it with
white water. At the helm the game's own handling is left alone. This is always on.

**The invert mouse setting not applying in a crane's camera.** The game applies invert mouse (and
invert stick) through input modifiers on the look binding of each input context. The character, boat
and water cannon contexts have them. The crane's does not, so in a crane's camera the setting did
nothing. The mod adds the character context's own inversion modifiers to the crane's look binding for
the mouse and the right stick, so the setting is followed as it is everywhere else. Sensitivity is
left as the game has it. This is always on.

## Install

You need Windows, the Steam version of Ships At Sea, and UE4SS installed first.

**1. UE4SS, experimental build.** The game runs on Unreal Engine 5.7, which the stable UE4SS
release does not support.

- Download `UE4SS_v3.0.1-<build>.zip` from
  https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest
- Extract it into the game's `SAS\Binaries\Win64` folder, next to `Sas-Win64-Shipping.exe`. You
  should end up with `dwmapi.dll` and a `ue4ss` folder there.

**2. The mod.**

1. Download `SasBoatFixes-<version>.zip` from the
   [latest release](https://github.com/foxyv/SasBoatFixes/releases/latest).
2. Extract it into the game's `SAS\Binaries\Win64\ue4ss\Mods` folder, so that
   `ue4ss\Mods\SasBoatFixes\Scripts\main.lua` exists.
3. Start the game. The fix is on from the start; there is nothing to press.

To check it loaded, look in `ue4ss\UE4SS.log` for the line
`[SasBoatFixes] loaded: list fix on (F4 toggles), wake fix on, F9 = record boat physics`.

### Uninstall

Delete `ue4ss\Mods\SasBoatFixes` from the game folder.

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

## Notes

- Tested in solo play. The fix changes a movement setting on characters locally; its effect in
  multiplayer is untested.
- The mod does all its work from a single timer on the game thread.

## Working on it

```
.\deploy.ps1              # copy the mod into the game; takes -GameDir for a non-default library
.\package.ps1 v0.1.0      # build the release zip into dist\
```

Ctrl+R in game reloads UE4SS Lua mods without a restart, if `EnableHotReloadSystem = 1` is set in
`ue4ss\UE4SS-settings.ini`.

## License

MIT. See `LICENSE`.
