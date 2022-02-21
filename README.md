# JTAC-I

Version 0.0.1a

## Prerequisites

### DCS Simple Radio Standalone

- [SRS](https://github.com/ciribob/DCS-SimpleRadioStandalone/releases/tag/1.9.9.0) - Download and run SRS-AUtoUpdater.exe

### Files

- [Moose.lua](https://github.com/FlightControl-Master/MOOSE/releases/download/2.7.8.1/Moose.lua)
- [DCS-SimpleTextToSpeech.lua](https://github.com/ciribob/DCS-SimpleTextToSpeech/blob/master/DCS-SimpleTextToSpeech.lua)

## Setup

### From the mission editor:

1. **Create JTAC Unit**: Place a ground unit that will serve as the JTAC and name it `observer`.
2. **Create objective**: Place a trigger zone in the editor at your objective's location and name it `objective`. The aircraft will reference this location, and may also serve as the designated "overhead" position for holding aircraft.
3. **Initial Points/Battle Positions** (optional): Place as many IPs (Initial Point objects) in the editor as needed. These will be used for routing and holding aircraft.
4. **Set Contact Point**: Create a trigger zone in th editor at your CP location and name it `cp`.
5. **Load Scripts**:

- Create a trigger of type `ONCE` with event `NO EVENT`
- Create an action of type `DO SCRIPT FILE` and enter the path to the `Moose.lua` file.
- Create a second action for the same trigger, also of tye `DO SCRIPT FILE` and enter the path of the `DCS-SimpleTextToSpeech.lua` file.
- Repeat previous step for `jtac-i.lua` file.
- (Optional) The default frequency and modulation for the JTAC is `251.000` and `AM`. To customize this, create another action (still on the same trigger) of type `DO SCRIPT` and enter custom radio configurations like so:

```
JTAC.comms.frequency = 124.75
JTAC.comms.modulation = 'AM'
```
