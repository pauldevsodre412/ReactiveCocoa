import Foundation
@testable import ReactiveCocoa
import ReactiveSwift
import enum Result.NoError
import Quick
import Nimble

class KeyValueObservingSpec: QuickSpec {
	override func spec() {
		describe("NSObject.signal(forKeyPath:)") {
			it("should not send the initial value") {
				let object = ObservableObject()
				var values: [Int] = []

				object.reactive
					.signal(forKeyPath: #keyPath(ObservableObject.rac_value))
					.observeValues { values.append(($0 as! NSNumber).intValue) }

				expect(values) == []
			}

			itBehavesLike("a reactive key value observer") {
				[
					"observe": { (object: NSObject, keyPath: String) in
						return object.reactive.signal(forKeyPath: keyPath)
					}
				]
			}
		}

		describe("NSObject.producer(forKeyPath:)") {
			it("should send the initial value") {
				let object = ObservableObject()
				var values: [Int] = []

				object.reactive
					.producer(forKeyPath: #keyPath(ObservableObject.rac_value))
					.startWithValues { value in
						values.append(value as! Int)
					}

				expect(values) == [0]
			}

			it("should send the initial value for nested key path") {
				let parentObject = NestedObservableObject()
				var values: [Int] = []

				parentObject
					.reactive
					.producer(forKeyPath: #keyPath(NestedObservableObject.rac_object.rac_value))
					.startWithValues { values.append(($0 as! NSNumber).intValue) }

				expect(values) == [0]
			}

			it("should send the initial value for weak nested key path") {
				let parentObject = NestedObservableObject()
				let innerObject = Optional(ObservableObject())
				parentObject.rac_weakObject = innerObject
				var values: [Int] = []

				parentObject
					.reactive
					.producer(forKeyPath: "rac_weakObject.rac_value")
					.startWithValues { values.append(($0 as! NSNumber).intValue) }

				expect(values) == [0]
			}

			itBehavesLike("a reactive key value observer") {
				[
					"observe": { (object: NSObject, keyPath: String) in
						return object.reactive.producer(forKeyPath: keyPath)
					}
				]
			}
		}

		describe("property type and attribute query") {
			let object = TestAttributeQueryObject()

			it("should be able to classify weak references") {
				"weakProperty".withCString { cString in
					let propertyPointer = class_getProperty(type(of: object), cString)
					expect(propertyPointer) != nil

					if let pointer = propertyPointer {
						let attributes = PropertyAttributes(property: pointer)
						expect(attributes.isWeak) == true
						expect(attributes.isObject) == true
						expect(attributes.isBlock) == false
						expect(attributes.objectClass).to(beIdenticalTo(NSObject.self))
					}
				}
			}

			it("should be able to classify blocks") {
				"block".withCString { cString in
					let propertyPointer = class_getProperty(type(of: object), cString)
					expect(propertyPointer) != nil

					if let pointer = propertyPointer {
						let attributes = PropertyAttributes(property: pointer)
						expect(attributes.isWeak) == false
						expect(attributes.isObject) == true
						expect(attributes.isBlock) == true
						expect(attributes.objectClass).to(beNil())
					}
				}
			}

			it("should be able to classify non object properties") {
				"integer".withCString { cString in
					let propertyPointer = class_getProperty(type(of: object), cString)
					expect(propertyPointer) != nil

					if let pointer = propertyPointer {
						let attributes = PropertyAttributes(property: pointer)
						expect(attributes.isWeak) == false
						expect(attributes.isObject) == false
						expect(attributes.isBlock) == false
						expect(attributes.objectClass).to(beNil())
					}
				}
			}
		}
	}
}

// Shared examples to ensure both `signal(forKeyPath:)` and `producer(forKeyPath:)`
// share common behavior.
fileprivate class KeyValueObservingSpecConfiguration: QuickConfiguration {
	class Context {
		let context: [String: Any]

		init(_ context: [String: Any]) {
			self.context = context
		}

		func observe(_ object: NSObject, _ keyPath: String) -> SignalProducer<Any?, NoError> {
			if let block = context["observe"] as? (NSObject, String) -> Signal<Any?, NoError> {
				return SignalProducer(block(object, keyPath))
			} else if let block = context["observe"] as? (NSObject, String) -> SignalProducer<Any?, NoError> {
				return block(object, keyPath).skip(first: 1)
			} else {
				fatalError("What is this?")
			}
		}

		func isFinished(_ object: Operation) -> SignalProducer<Any?, NoError> {
			return observe(object, #keyPath(Operation.isFinished))
		}

		func changes(_ object: NSObject) -> SignalProducer<Any?, NoError> {
			return observe(object, #keyPath(ObservableObject.rac_value))
		}

		func nestedChanges(_ object: NSObject) -> SignalProducer<Any?, NoError> {
			return observe(object, #keyPath(NestedObservableObject.rac_object.rac_value))
		}

		func weakNestedChanges(_ object: NSObject) -> SignalProducer<Any?, NoError> {
			// `#keyPath` does not work with weak relationships.
			return observe(object, "rac_weakObject.rac_value")
		}
	}

	override class func configure(_ configuration: Configuration) {
		sharedExamples("a reactive key value observer") { (sharedExampleContext: @escaping SharedExampleContext) in
			var context: Context!

			beforeEach { context = Context(sharedExampleContext()) }
			afterEach { context = nil }

			it("should send new values for the key path (even if the value remains unchanged)") {
				let object = ObservableObject()
				var values: [Int] = []

				context.changes(object).startWithValues {
					values.append(($0 as! NSNumber).intValue)
				}

				expect(values) == []

				object.rac_value = 0
				expect(values) == [0]

				object.rac_value = 1
				expect(values) == [0, 1]

				object.rac_value = 1
				expect(values) == [0, 1, 1]
			}

			it("should not crash an Operation") {
				// Related issue:
				// https://github.com/ReactiveCocoa/ReactiveCocoa/issues/3329
				func invoke() {
					let op = Operation()
					context.isFinished(op).start()
				}

				invoke()
			}

			describe("signal behavior") {
				it("should complete when the object deallocates") {
					var completed = false

					_ = {
						// Use a closure so this object has a shorter lifetime.
						let object = ObservableObject()

						context.changes(object).startWithCompleted {
							completed = true
						}

						expect(completed) == false
					}()

					expect(completed).toEventually(beTruthy())
				}
			}

			describe("nested key paths") {
				it("should observe changes in a nested key path") {
					let parentObject = NestedObservableObject()
					var values: [Int] = []

					context.nestedChanges(parentObject).startWithValues {
						values.append(($0 as! NSNumber).intValue)
					}

					expect(values) == []

					parentObject.rac_object.rac_value = 1
					expect(values) == [1]

					let oldInnerObject = parentObject.rac_object

					let newInnerObject = ObservableObject()
					parentObject.rac_object = newInnerObject
					expect(values) == [1, 0]

					parentObject.rac_object.rac_value = 10
					oldInnerObject.rac_value = 2
					expect(values) == [1, 0, 10]
				}

				it("should observe changes in a nested weak key path") {
					let parentObject = NestedObservableObject()
					var innerObject = Optional(ObservableObject())
					parentObject.rac_weakObject = innerObject
					var values: [Int] = []

					context.weakNestedChanges(parentObject).startWithValues {
						values.append(($0 as! NSNumber).intValue)
					}

					expect(values) == []

					innerObject?.rac_value = 1
					expect(values) == [1]

					autoreleasepool {
						innerObject = nil
					}

					// NOTE: [1] or [Optional(1), nil]?
					expect(values) == [1]

					innerObject = ObservableObject()
					parentObject.rac_weakObject = innerObject
					expect(values) == [1, 0]
					
					innerObject?.rac_value = 10
					expect(values) == [1, 0, 10]
				}

				it("should not retain replaced value in a nested key path") {
					let parentObject = NestedObservableObject()
					weak var weakOriginalInner: ObservableObject? = parentObject.rac_object
					expect(weakOriginalInner).toNot(beNil())

					autoreleasepool {
						_ = context
							.nestedChanges(parentObject)
							.start()
						parentObject.rac_object = ObservableObject()
					}

					expect(weakOriginalInner).toEventually(beNil())
				}
			}

			describe("thread safety") {
				var concurrentQueue: DispatchQueue!

				beforeEach {
					concurrentQueue = DispatchQueue(
						label: "org.reactivecocoa.ReactiveCocoa.DynamicPropertySpec.concurrentQueue",
						attributes: .concurrent
					)
				}

				it("should handle changes being made on another queue") {
					let object = ObservableObject()
					var observedValue = 0

					context.changes(object)
						.take(first: 1)
						.startWithValues { observedValue = ($0 as! NSNumber).intValue }

					concurrentQueue.async {
						object.rac_value = 2
					}

					concurrentQueue.sync(flags: .barrier) {}
					expect(observedValue).toEventually(equal(2))
				}

				it("should handle changes being made on another queue using deliverOn") {
					let object = ObservableObject()
					var observedValue = 0

					context.changes(object)
						.take(first: 1)
						.observe(on: UIScheduler())
						.startWithValues { observedValue = ($0 as! NSNumber).intValue }

					concurrentQueue.async {
						object.rac_value = 2
					}

					concurrentQueue.sync(flags: .barrier) {}
					expect(observedValue).toEventually(equal(2))
				}

				it("async disposal of target") {
					var object: ObservableObject? = ObservableObject()
					var observedValue = 0

					context.changes(object!)
						.observe(on: UIScheduler())
						.startWithValues { observedValue = ($0 as! NSNumber).intValue }

					concurrentQueue.async {
						object!.rac_value = 2
						object = nil
					}

					concurrentQueue.sync(flags: .barrier) {}
					expect(observedValue).toEventually(equal(2))
				}
			}

			describe("stress tests") {
				let numIterations = 5000

				var testObject: ObservableObject!
				var iterationQueue: DispatchQueue!
				var concurrentQueue: DispatchQueue!

				beforeEach {
					testObject = ObservableObject()
					iterationQueue = DispatchQueue(
						label: "org.reactivecocoa.ReactiveCocoa.RACKVOProxySpec.iterationQueue",
						attributes: .concurrent
					)
					concurrentQueue = DispatchQueue(
						label: "org.reactivecocoa.ReactiveCocoa.DynamicPropertySpec.concurrentQueue",
						attributes: .concurrent
					)
				}

				it("attach observers") {
					let deliveringObserver: QueueScheduler
					if #available(*, OSX 10.10) {
						deliveringObserver = QueueScheduler(name: "\(#file):\(#line)")
					} else {
						deliveringObserver = QueueScheduler(queue: DispatchQueue(label: "\(#file):\(#line)"))
					}

					var atomicCounter = Int64(0)

					DispatchQueue.concurrentPerform(iterations: numIterations) { index in
						context.changes(testObject)
							.observe(on: deliveringObserver)
							.map { $0 as! NSNumber }
							.map { $0.int64Value }
							.startWithValues { value in
								OSAtomicAdd64(value, &atomicCounter)
							}
					}

					testObject.rac_value = 2

					expect(atomicCounter).toEventually(equal(10000), timeout: 30.0)
				}

				// ReactiveCocoa/ReactiveCocoa#1122
				it("async disposal of observer") {
					let serialDisposable = SerialDisposable()

					iterationQueue.async {
						DispatchQueue.concurrentPerform(iterations: numIterations) { index in
							let disposable = context.changes(testObject)
								.startWithCompleted {}

							serialDisposable.inner = disposable

							concurrentQueue.async {
								testObject.rac_value = index
							}
						}
					}

					iterationQueue.sync(flags: .barrier) {
						serialDisposable.dispose()
					}
				}

				it("async disposal of signal with in-flight changes") {
					let otherScheduler: QueueScheduler

					var token = Optional(Lifetime.Token())
					let lifetime = Lifetime(token!)

					if #available(*, OSX 10.10) {
						otherScheduler = QueueScheduler(name: "\(#file):\(#line)")
					} else {
						otherScheduler = QueueScheduler(queue: DispatchQueue(label: "\(#file):\(#line)"))
					}

					let replayProducer = context.changes(testObject)
						.map { ($0 as! NSNumber).intValue }
						.map { $0 % 2 == 0 }
						.observe(on: otherScheduler)
						.take(during: lifetime)
						.replayLazily(upTo: 1)

					replayProducer.start()

					iterationQueue.suspend()

					let half = numIterations / 2

					for index in 0 ..< numIterations {
						iterationQueue.async {
							testObject.rac_value = index
						}

						if index == half {
							iterationQueue.async(flags: .barrier) {
								token = nil
								expect(replayProducer.last()).toNot(beNil())
							}
						}
					}

					iterationQueue.resume()
					iterationQueue.sync(flags: .barrier, execute: {})
				}
			}
		}
	}
}

private class ObservableObject: NSObject {
	dynamic var rac_value: Int = 0
}

private class NestedObservableObject: NSObject {
	dynamic var rac_object: ObservableObject = ObservableObject()
	dynamic weak var rac_weakObject: ObservableObject?
}

private class TestAttributeQueryObject: NSObject {
	@objc weak var weakProperty: NSObject? = nil
	@objc var block: @convention(block) (NSObject) -> NSObject? = { _ in nil }
	@objc let integer = 0
}
