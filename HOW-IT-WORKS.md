# How Solo Tandems works

Solo Tandems is a Practice mode and an in-game app. You drive one car. The lead is a model drawn in the world. It has no physics, so you can drive through it.

The mode starts you in the pits, so the car setup is available and you can return to the pits the way Practice does. Extended physics is on. The pit crew is hidden. Yellow and blue flags are off. Lap-cut checks are turned off, so a chase line off the racing line does not count as a cut.

## A session

Record while you drive. A sample is stored 30 times a second. Each sample keeps where the car is, which way it faces, how it is moving, steering, brake, handbrake, throttle, rpm, gear, the angle it is sliding, speed, how fast each wheel is spinning, and where the wipers were. Playback blends from one sample to the next.

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

The model is the car you recorded, unless you pick another from the cars installed in the game. The list can be filtered. The first choice is the recorded car. Picking a different car while the lead is showing unloads the old model and loads the new one.

The wheels and the steering wheel follow the recording. The brake lights follow the brake. The headlights are on while the lead is showing. Tyre smoke appears at the rear wheels when the saved run is sliding more than 5 degrees and moving faster than 12 km/h. If the model has no rear wheel to measure, the smoke sits a fixed distance behind the car. The wipers follow the recorded sweep. While the track is wet, the paint and the tyres are made to look wet. When it dries, each part goes back to the shine it had before the rain. If that shine could not be read, the body gets a plain dry shine. The lead plays that car's engine sound from the saved rpm and throttle.

The point saved while you drive sits in the body of the car, about a metre above the road. The first time that point is over the road, within a normal ride height, the app measures the gap down to the tyres and keeps that gap. Later points use the same gap, so a jump in the recording stays a jump. Until a road reading is taken, the model uses a fixed drop. A missed look leaves the gap unset, so a later point on the road can still measure it.

## Sharing a run

Export writes a `.lead` file. The file holds the samples, the car, and the track. The folder is `Documents/Solo Tandems`, unless you set another folder in the app window. The window can put the folder back to that default.

Import reads a `.lead` file from that folder. The lead stays hidden until Spawn. A run from another track is refused, and the notice names the track it needs. A file that is empty, the wrong kind, or missing a position or a direction is refused. A broken file says Bad file. The run already loaded stays in place. A good import says Imported and the file name.

## The window and the controls

The window shows the current notice, whether a recording is going, how many samples are stored, and whether the lead is hidden, waiting, or running. It also shows whether extended physics is on, which car the lead is using, and whether that model loaded.

The buttons are Record, Spawn, Start, Chase, Teleport, and Clear.

The same six actions can be bound to a keyboard or a controller. The names are Solo Tandems/Record Lead Run, Spawn Lead Car, Set Chase Car, Teleport, Start, and Clear Lead Run. The app loads with the session, and that is when the names are written. After that, Content Manager lists them with the patch controls, under Solo Tandems. They are not listed before that first session. You do not need to drive for them to appear.

A Stream Deck can send the same six actions. A key writes an action number into shared memory named `soloTandems.v1`. The app reads that and runs the action. A press that was already waiting when the app opened is ignored.
