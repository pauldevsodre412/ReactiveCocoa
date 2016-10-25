import Quick
import Nimble
import ReactiveSwift
import ReactiveCocoa
import Result

class UISwitchSpec: QuickSpec {
	override func spec() {
		var toggle: UISwitch!
		weak var _toggle: UISwitch?

		beforeEach {
			toggle = UISwitch(frame: .zero)
			_toggle = toggle
		}

		afterEach {
			toggle = nil

			// Disabled due to an issue of the iOS SDK.
			// Please refer to https://github.com/ReactiveCocoa/ReactiveCocoa/issues/3251
			// for more information.
			//
			// expect(_toggle).to(beNil())
		}

		it("should accept changes from bindings to its `isOn` state") {
			toggle.isOn = false

			let (pipeSignal, observer) = Signal<Bool, NoError>.pipe()
			toggle.reactive.isOn <~ SignalProducer(signal: pipeSignal)

			observer.send(value: true)
			expect(toggle.isOn) == true

			observer.send(value: false)
			expect(toggle.isOn) == false
		}

		it("should emit user initiated changes to its `isOn` state") {
			var latestValue: Bool?
			toggle.reactive.isOnValues.observeValues { latestValue = $0 }

			toggle.isOn = true
			toggle.sendActions(for: .valueChanged)
			expect(latestValue!) == true
		}
	}
}
