package;

import haxe.ds.Option;

typedef Action = {
	var frame:Int;
	var code:Int;
	var down:Bool;
}

typedef ResolutionAction = {
	var frame:Int;
	var height:Int;
	var width:Int;
}

class Video {
	static var headerSize = 6 * 4;
	static var delaySize = 5;
	static var longDelaySize = 10;
	static var resolutionDelaySize = 12;
	static var resolutionSize = 14;

	public var actions:Array<Action>;
	public var resolutionActions:Array<ResolutionAction>;
	public var pauseFrame:Int = 0;

	public var initialGameHeight:Int;
	public var initialGameWidth:Int;

	private function getOption<T>(x:Option<T>):T {
		switch x {
			case None:
				throw "Invalid video string.";
			case Some(x):
				return x;
		}
	}

	public function new(?save:String) {
		actions = new Array();
		resolutionActions = new Array();

		if (save != null) {
			// Load from save.
			var reader = new Bitstream.BSReader(save);

			var actionsLength = getOption(reader.readInt(12));
			pauseFrame = getOption(reader.readInt(headerSize));
			
			var frame = 0;
			for (i in 0...actionsLength) {
				var longDelay = getOption(reader.read(1))[0];
				var delay = getOption(reader.readInt(longDelay ? longDelaySize : delaySize));
				var code = getOption(reader.readInt(3));
				var down = getOption(reader.read(1));
				frame += delay;
				actions.push({frame: frame, code: code, down: down[0]});
			}
			
			initialGameHeight = getOption(reader.readInt(resolutionSize));
			initialGameWidth = getOption(reader.readInt(resolutionSize));

			var resolutionActionsLength = getOption(reader.readInt(8));
			frame = 0;
			for (i in 0...resolutionActionsLength) {
				var delay = getOption(reader.readInt(resolutionDelaySize));
				var height = getOption(reader.readInt(resolutionSize));
				var width = getOption(reader.readInt(resolutionSize));
				frame += delay;
				resolutionActions.push({frame: frame, height: height, width: width});
			}
		}
	}

	public function toString():String {
		var writer = new Bitstream.BSWriter();
		writer.writeInt(actions.length, 12);
		writer.writeInt(pauseFrame, headerSize);
		
		var lastFrame = 0;
		for (action in actions) {
			var delay = action.frame - lastFrame;
			lastFrame = action.frame;
			var longDelay = delay >= 32;
			writer.write([longDelay]);
			writer.writeInt(delay, longDelay ? longDelaySize : delaySize);
			writer.writeInt(action.code, 3);
			writer.write([action.down]);
		}

		writer.writeInt(initialGameHeight, resolutionSize);
		writer.writeInt(initialGameWidth, resolutionSize);

		writer.writeInt(resolutionActions.length, 8);
		lastFrame = 0;
		for (action in resolutionActions) {
			var delay = action.frame - lastFrame;
			lastFrame = action.frame;

			writer.writeInt(delay, resolutionDelaySize);
			writer.writeInt(action.height, resolutionSize);
			writer.writeInt(action.width, resolutionSize);
		}

		return writer.toString();
	}

	public static var keyCodes = [37, 39, 38, 87, 72, 32, 80]; // 37: Left arrow, 39: Right arrow, 38: Up arrow, 87: W, 72: H, 32: Space, 80: P

	public static function toActionCode(keyCode:Int):Option<Int> {
		for (i in 0...keyCodes.length) {
			if (keyCodes[i] == keyCode)
				return Some(i);
		}
		return None;
	}

	public static function fromActionCode(actionCode:Int):Int {
		return keyCodes[actionCode];
	}

	public static function showActionCode(actionCode:Int):String {
		switch actionCode {
			case 0:
				return "Left   ";
			case 1:
				return "Right  ";
			case 2 | 3 | 4 | 5:
				return "Jump   ";
			case 6:
				return "Pause  ";
		}
		return "???    ";
	}

	public function copy():Video {
		var video = new Video();
		video.actions = actions.copy();
		video.resolutionActions = resolutionActions.copy();
		video.pauseFrame = pauseFrame;
		video.initialGameHeight = initialGameHeight;
		video.initialGameWidth = initialGameWidth;
		return video;
	}
}

class VideoRecorder {
	public var video:Video = new Video();

	private var keyStates:Array<Bool>;
	
	private var gameHeight:Int;
	private var gameWidth:Int;

	public function new(initialGameHeight:Int, initialGameWidth:Int) {
		keyStates = new Array();
		for (i in 0...Video.keyCodes.length) {
			keyStates.push(false);
		}

		video.initialGameHeight = initialGameHeight;
		gameHeight = initialGameHeight;
		video.initialGameWidth = initialGameWidth;
		gameWidth = initialGameWidth;

		trace('Initial resolution: ${initialGameWidth}x${initialGameHeight}');
	}

	public function recordKey(frame:Int, keyCode:Int, down:Bool, silent:Bool) {
		switch Video.toActionCode(keyCode) {
			case Some(action):
				var oldState = keyStates[action];
				if (down == oldState)
					return;
				keyStates[action] = down;
				if (frame > 0)
					video.actions.push({frame: frame, code: action, down: down}); // can't record thing below frame 1
				if (!silent)
					trace('---> ${Video.showActionCode(action)} ${down ? "down" : "up  "} @ ${frame}');
			case None:
				return;
		}
	}

	public function recordResolutionChange(frame:Int, newHeight:Int, newWidth:Int) {
		// Do nothing if the resolution wasn't actually changed
		if (gameHeight == newHeight && gameWidth == newWidth)
			return;

		// We only want to allow changing resolution once in a given frame.
		// Check if there is already a resolution change in the current frame,
		// and if so - replace it.
		if (video.resolutionActions.length > 0) {
			var lastAction = video.resolutionActions[video.resolutionActions.length - 1];
			if (lastAction.frame == frame)
				video.resolutionActions.pop();
		}

		video.resolutionActions.push({frame: frame, height: newHeight, width: newWidth});
		trace('Resolution changed to ${newWidth}x${newHeight} @ ${frame}');
	}

	public function saveVideo(frame:Int):Video {
		var res = video.copy();
		res.pauseFrame = frame;
		return res;
	}
}

class VideoPlayer {
	public var video:Video;

	public function new(video:Video) {
		this.video = video.copy();
	}

	public function getActions(frame:Int):Array<{code:Int, down:Bool}> {
		var res = [];
		while (video.actions.length > 0 && video.actions[0].frame == frame) {
			var action = video.actions.shift();
			res.push({code: Video.fromActionCode(action.code), down: action.down});
		}
		return res;
	}

	public function getResolutionAction(frame:Int):ResolutionAction {
		while (video.resolutionActions.length > 0 && video.resolutionActions[0].frame == frame) {
			var action = video.resolutionActions.shift();
			return action;
		}
		return null;
	}
}
