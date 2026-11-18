# How Solo Tandems works

Solo Tandems is a Practice mode and an in-game app. You drive one car. The lead is a model drawn in the world. Lead contact is off, so you can drive through it. Turning Lead contact on puts a light box on the lead. The first touch plays the crash sound once, and the next one waits until the cars have separated.

The session starts in the pits. A setup saved as Solo Tandems for this car on this track is loaded. When that file is missing, the Solo Tandems setup saved for the car is loaded. When neither file exists, the car keeps the setup the game already loaded. Extended physics is on. The pit crew is hidden. Yellow and blue flags are off. Lap-cut checks are turned off, so a chase line off the racing line does not count as a cut.

## A session

Record while you drive. A sample is stored 30 times a second. Each sample keeps where the car is, which way it faces, how it is moving, steering, brake, handbrake, throttle, rpm, gear, the angle it is sliding, speed, how fast each wheel is spinning, and how hard each tyre is slipping. Playback blends from one sample to the next. The run also keeps the skin folder that was on the car.

Press Record again to stop. The notice says Lead run saved. If the run has no samples, the notice says Recording is empty. Starting Record again replaces the run and hides the lead.

A recording stops itself at 15 minutes. The notice says 15 minute recording limit reached. From 14 minutes the notice counts the seconds left, down to 1 second of recording left.

Spawn puts the lead on the first sample and holds it there. The wheels are still. The steering stays where it was at the start. The notice says Lead is waiting.

Chase marks where your car is, and which way it faces. That mark can be set while a recording is still going. The notice says Chase car set.

Start plays the run from the first sample. The lead moves along the saved line, blending between samples. The notice says Lead is running.

When the run reaches the end, the lead sits on the first sample again and waits. Your car stays where it is. The notice says Lead ready. Start plays the run again from there.

Teleport puts your car back on the chase mark, stopped, in neutral. If a lead run is loaded, the lead goes back to waiting at the start. Teleport needs extended physics. This mode turns that on. If extended physics is off, the notice says Extended physics is off and the car stays put.

Clear throws the run away. The notice says Lead run cleared.

Spawn, Start, and Teleport do nothing while a recording is still going. The notice says Stop the recording first. Spawn does nothing if there is no run. Start does nothing until the lead has been spawned. Teleport does nothing until Chase has been set.

## The lead car

The model is the car the run was recorded in. Loading that run later keeps that car, whichever car you are driving. The skin from the run is applied when that folder is installed. A missing skin keeps the textures in the car file. If that car is not installed, or it has no model, the notice names the car and says which of those it is. A model file that will not load says so too. In those cases the lead is a wireframe box, 1 m wide, 0.6 m tall and 3 m long, with an arrow for the heading, so the line can still be chased.

The wheels and the steering wheel follow the recording. The steering wheel uses that car's own steering lock. The front tyres turn by that lock divided by the car's steer ratio. When that ratio is missing, or the angle would fall outside 15 to 70 degrees, the tyres turn 32 degrees at full lock. The saved speed of each wheel turns that tyre, so a locked wheel stays still. The tyre size comes from that car too. It is used when a wheel speed was not saved, and it is also used for the smoke and the ride height. The brake lights follow the brake. The headlights, high beams, and tail lights follow the recording. A high-beam flash lights the headlights without the tail lights. The blinkers follow the recorded side, and whether that blink was lit. The reverse lights come on when the recorded gear is reverse. Each wheel smokes from its own recorded slip, at that wheel. A tyre at peak grip stays quiet. Past that it starts, and around four times the peak it is a full cloud. The wipers follow the rain in the current session. A dry track parks them. A wet track with no rain sweeps every 2.5 seconds. Rain sweeps every 1.5 seconds in a drizzle and every 1 second in full rain. While the track is wet, the outside paint and the tyres are made to look wet. The cockpit stays dry. When the track dries, each outside part goes back to the shine it had before the rain. If that shine could not be read, the body gets a plain dry shine. The lead plays that car's engine sound from the saved rpm and throttle. From the cockpit that sound is at 0.4 of its volume. From an outside camera it is full.

The point saved while you drive can sit above the wheels. The lead's wheel hubs and that car's tyre size give the height of each axle. The lower axle is the one that is kept, so the rear tyres sit on the road instead of being pushed through it. That ride is divided by how upright the car is, so a slope matches the saved height. While the saved point is within 15 cm of that ride, the lead uses the saved height, so bumps and the squat of a drift stay in the run. A larger gap, up to a metre, eases toward the road. A reading further away than that is ignored, so a jump, a tunnel ceiling, or a surface under the track leaves the lead on the saved height. The lead cannot drop through the road in one frame. Until a road reading arrives, the lead stays on the saved point.

## Sharing a run

Export writes a `.lead` file. The file holds the samples, the car, the skin, and the track. The folder is `Documents/Solo Tandems`, unless you set another folder in the app window. The window can put the folder back to that default.

Import reads a `.lead` file from that folder. The lead stays hidden until Spawn. A run from another track is refused, and the notice names the track it needs. A file that is empty, the wrong kind, or missing a position or a direction is refused. A broken file says Bad file. The run already loaded stays in place. A good import says Imported and the file name.

## The window and the controls

The window shows the current notice, whether a recording is going, how many samples are stored, and whether the lead is hidden, waiting, or running. It also shows whether extended physics is on, which car the lead is using, and whether that model loaded.

The buttons are Record, Spawn, Start, Chase, Teleport, and Clear.

The same six actions can be bound to a keyboard or a controller. The names are Solo Tandems/Record Lead Run, Spawn Lead Car, Set Chase Car, Teleport, Start, and Clear Lead Run. The app loads with the session, and that is when the names are written. After that, Content Manager lists them with the patch controls, under Solo Tandems. They are not listed before that first session. You do not need to drive for them to appear.

A Stream Deck can send the same six actions. A key writes an action number into shared memory named `soloTandems.v1`. The app reads that and runs the action. A press that was already waiting when the app opened is ignored.
