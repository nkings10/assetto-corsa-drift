# How Solo Tandems works

Solo Tandems is a Practice mode and an in-game app. You drive one car. The lead is a model drawn in the world. It has no physics, so you can drive through it.

The mode starts you in the pits, the same way Practice does, so you can open the setup and return to the pits. It turns extended physics on, hides the pit crew, and turns yellow and blue flags off. Lap-cut penalties are disarmed, so a chase line off the racing line does not throw a cut.

## A session

Record while you drive. Every frame is stored: where the car is, which way it faces, how fast it is moving, steering, brake, throttle, rpm, gear, drift angle, and the speed of each wheel. Press Record again to stop. A recording stops itself at 15 minutes. The notice then says Lead run saved.

Spawn puts the lead at the first point of that run and holds it there. The wheels are still. The steering stays where it was at the start.

Chase marks the spot your car is in. Teleport uses that spot later.

Start plays the run. The lead moves along the saved line. Between two saved points the motion is blended, so it does not step from one frame to the next.

When the run reaches the end, the lead goes back to the first point and waits. You stay where you are. The notice says Lead ready. Start plays it again from there.

Teleport puts your car back on the chase mark, stopped, in neutral. The lead goes back to waiting at the start, so you can run it again. Teleport needs extended physics. This mode turns that on. If extended physics is off, the notice says so and the car stays put.

Clear throws the run away.

Spawn, Start, and Teleport do nothing while a recording is still going. Stop the recording first. Spawn does nothing if there is no run. Start does nothing until the lead has been spawned. Teleport does nothing until Chase has been set.

## The lead car

The model is the car you recorded, unless you pick another. The app lists the cars installed in the game, and the list can be filtered. Picking a different car while the lead is showing loads that model.

The model follows the saved line. Its wheels steer and spin with the recording. The brake lights follow the brake. The headlights are on while it is showing. Tyre smoke appears when the saved run is sliding and moving. The wipers sweep while it is showing. In the rain the paint is made to look wet. The lead plays that car's engine sound from the saved rpm and throttle.

The point saved while you drive sits in the body of the car, about a metre above the road. The app looks down from that point, finds the road, and sits the model on it.

## Sharing a run

Export writes a `.lead` file. The file holds the run, the car, and the track. The folder is `Documents/Solo Tandems`, unless you set another folder in the app window.

Import reads a `.lead` file from that folder. A run recorded on another track is refused, and the notice names the track it needs. A file that is not a Solo Tandems run is refused.

## Controls

The app window has Record, Spawn, Start, Chase, Teleport, and Clear. The top of the window shows the current notice, whether a recording is going, how many frames are stored, and whether the lead is hidden, waiting, or running.

The same six actions can be bound to a keyboard or a controller. The names are written when a session starts and the app loads. After that, Content Manager lists them with the patch controls, under Solo Tandems. They are not listed before that first session. You do not need to drive for them to appear.

A Stream Deck can send the same six actions. A key press writes an action number into shared memory named `soloTandems.v1`. The app reads that and runs the action.
