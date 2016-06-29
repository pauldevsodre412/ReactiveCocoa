import Foundation
import enum Result.NoError

/// Represents a property that allows observation of its changes.
public protocol PropertyProtocol {
	associatedtype Value

	/// The current value of the property.
	var value: Value { get }

	/// A producer for signals that sends the property's current value,
	/// followed by all changes over time. It completes when the property
	/// has deinitialized, or has no further change.
	var producer: SignalProducer<Value, NoError> { get }

	/// A signal that will send the property's changes over time. It
	/// completes when the property has deinitialized, or has no further
	/// change.
	var signal: Signal<Value, NoError> { get }
}

/// Represents an observable property that can be mutated directly.
///
/// Only classes can conform to this protocol, because instances must support
/// weak references (and value types currently do not).
public protocol MutablePropertyType: class, PropertyProtocol {
	/// The current value of the property.
	var value: Value { get set }
}

/// Protocol composition operators
///
/// The producer and the signal of transformed properties would complete
/// only when its source properties have deinitialized.
///
/// A transformed property would retain its ultimate source, but not
/// any intermediate property during the composition.
extension PropertyProtocol {
	/// Lifts a unary SignalProducer operator to operate upon PropertyProtocol instead.
	private func lift<U>( _ transform: @noescape (SignalProducer<Value, NoError>) -> SignalProducer<U, NoError>) -> AnyProperty<U> {
		return AnyProperty(self, transform: transform)
	}

	/// Lifts a binary SignalProducer operator to operate upon PropertyProtocol instead.
	private func lift<P: PropertyProtocol, U>(_ transform: @noescape (SignalProducer<Value, NoError>) -> (SignalProducer<P.Value, NoError>) -> SignalProducer<U, NoError>) -> @noescape (P) -> AnyProperty<U> {
		return { otherProperty in
			return AnyProperty(self, otherProperty, transform: transform)
		}
	}

	/// Maps the current value and all subsequent values to a new property.
	public func map<U>(_ transform: (Value) -> U) -> AnyProperty<U> {
		return lift { $0.map(transform) }
	}

	/// Combines the current value and the subsequent values of two `Property`s in
	/// the manner described by `Signal.combineLatestWith:`.
	public func combineLatestWith<P: PropertyProtocol>(_ other: P) -> AnyProperty<(Value, P.Value)> {
		return lift(SignalProducer.combineLatestWith)(other)
	}

	/// Zips the current value and the subsequent values of two `Property`s in
	/// the manner described by `Signal.zipWith`.
	public func zipWith<P: PropertyProtocol>(_ other: P) -> AnyProperty<(Value, P.Value)> {
		return lift(SignalProducer.zipWith)(other)
	}

	/// Forwards events from `self` with history: values of the returned property
	/// are a tuple whose first member is the previous value and whose second member
	/// is the current value. `initial` is supplied as the first member of the first
	/// tuple.
	public func combinePrevious(_ initial: Value) -> AnyProperty<(Value, Value)> {
		return lift { $0.combinePrevious(initial) }
	}

	/// Forwards only those values from `self` which do not pass `isRepeat` with
	/// respect to the previous value. The first value is always forwarded.
	public func skipRepeats(_ isRepeat: (Value, Value) -> Bool) -> AnyProperty<Value> {
		return lift { $0.skipRepeats(isRepeat) }
	}
}

extension PropertyProtocol where Value: Equatable {
	/// Forwards only those values from `self` which is not equal to the previous
	/// value. The first value is always forwarded.
	public func skipRepeats() -> AnyProperty<Value> {
		return lift { $0.skipRepeats() }
	}
}

extension PropertyProtocol where Value: PropertyProtocol {
	/// Flattens the inner properties sent upon `self` (into a single property),
	/// according to the semantics of the given strategy.
	public func flatten(_ strategy: FlattenStrategy) -> AnyProperty<Value.Value> {
		return lift { $0.flatMap(strategy) { $0.producer } }
	}
}

extension PropertyProtocol {
	/// Maps each property from `self` to a new property, then flattens the
	/// resulting properties (into a single property), according to the
	/// semantics of the given strategy.
	public func flatMap<P: PropertyProtocol>(_ strategy: FlattenStrategy, transform: (Value) -> P) -> AnyProperty<P.Value> {
		return lift { $0.flatMap(strategy) { transform($0).producer } }
	}

	/// Forwards only those values from `self` that have unique identities across the set of
	/// all values that have been seen.
	///
	/// Note: This causes the identities to be retained to check for uniqueness.
	public func uniqueValues<Identity: Hashable>(_ transform: (Value) -> Identity) -> AnyProperty<Value> {
		return lift { $0.uniqueValues(transform) }
	}
}

extension PropertyProtocol where Value: Hashable {
	/// Forwards only those values from `self` that are unique across the set of
	/// all values that have been seen.
	///
	/// Note: This causes the values to be retained to check for uniqueness. Providing
	/// a function that returns a unique value for each sent value can help you reduce
	/// the memory footprint.
	public func uniqueValues() -> AnyProperty<Value> {
		return lift { $0.uniqueValues() }
	}
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol>(_ a: A, _ b: B) -> AnyProperty<(A.Value, B.Value)> {
	return a.combineLatestWith(b)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol>(_ a: A, _ b: B, _ c: C) -> AnyProperty<(A.Value, B.Value, C.Value)> {
	return combineLatest(a, b)
		.combineLatestWith(c)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value)> {
	return combineLatest(a, b, c)
		.combineLatestWith(d)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value)> {
	return combineLatest(a, b, c, d)
		.combineLatestWith(e)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value)> {
	return combineLatest(a, b, c, d, e)
		.combineLatestWith(f)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value)> {
	return combineLatest(a, b, c, d, e, f)
		.combineLatestWith(g)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value)> {
	return combineLatest(a, b, c, d, e, f, g)
		.combineLatestWith(h)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value)> {
	return combineLatest(a, b, c, d, e, f, g, h)
		.combineLatestWith(i)
		.map(repack)
}

/// Combines the values of all the given properties, in the manner described by
/// `combineLatest(with:)`.
public func combineLatest<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol, J: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value)> {
	return combineLatest(a, b, c, d, e, f, g, h, i)
		.combineLatestWith(j)
		.map(repack)
}

/// Combines the values of all the given producers, in the manner described by
/// `combineLatest(with:)`. Returns nil if the sequence is empty.
public func combineLatest<S: Sequence where S.Iterator.Element: PropertyProtocol>(_ properties: S) -> AnyProperty<[S.Iterator.Element.Value]>? {
	var generator = properties.makeIterator()
	if let first = generator.next() {
		let initial = first.map { [$0] }
		return IteratorSequence(generator).reduce(initial) { property, next in
			property.combineLatestWith(next).map { $0.0 + [$0.1] }
		}
	}

	return nil
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol>(_ a: A, _ b: B) -> AnyProperty<(A.Value, B.Value)> {
	return a.zipWith(b)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol>(_ a: A, _ b: B, _ c: C) -> AnyProperty<(A.Value, B.Value, C.Value)> {
	return zip(a, b)
		.zipWith(c)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value)> {
	return zip(a, b, c)
		.zipWith(d)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value)> {
	return zip(a, b, c, d)
		.zipWith(e)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value)> {
	return zip(a, b, c, d, e)
		.zipWith(f)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value)> {
	return zip(a, b, c, d, e, f)
		.zipWith(g)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value)> {
	return zip(a, b, c, d, e, f, g)
		.zipWith(h)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value)> {
	return zip(a, b, c, d, e, f, g, h)
		.zipWith(i)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`.
public func zip<A: PropertyProtocol, B: PropertyProtocol, C: PropertyProtocol, D: PropertyProtocol, E: PropertyProtocol, F: PropertyProtocol, G: PropertyProtocol, H: PropertyProtocol, I: PropertyProtocol, J: PropertyProtocol>(_ a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F, _ g: G, _ h: H, _ i: I, _ j: J) -> AnyProperty<(A.Value, B.Value, C.Value, D.Value, E.Value, F.Value, G.Value, H.Value, I.Value, J.Value)> {
	return zip(a, b, c, d, e, f, g, h, i)
		.zipWith(j)
		.map(repack)
}

/// Zips the values of all the given properties, in the manner described by
/// `zip(with:)`. Returns nil if the sequence is empty.
public func zip<S: Sequence where S.Iterator.Element: PropertyProtocol>(_ properties: S) -> AnyProperty<[S.Iterator.Element.Value]>? {
	var generator = properties.makeIterator()
	if let first = generator.next() {
		let initial = first.map { [$0] }
		return IteratorSequence(generator).reduce(initial) { property, next in
			property.zipWith(next).map { $0.0 + [$0.1] }
		}
	}

	return nil
}

/// A read-only, type-erased view of a property.
public struct AnyProperty<Value>: PropertyProtocol {
	private let sources: [Any]
	private let disposable: Disposable?

	private let _value: () -> Value
	private let _producer: () -> SignalProducer<Value, NoError>
	private let _signal: () -> Signal<Value, NoError>

	/// The current value of the property.
	public var value: Value {
		return _value()
	}

	/// A producer for Signals that will send the wrapped property's current value,
	/// followed by all changes over time, then complete when the wrapped property has
	/// deinitialized.
	public var producer: SignalProducer<Value, NoError> {
		return _producer()
	}

	/// A signal that will send the wrapped property's changes over time, then complete
	/// when the wrapped property has deinitialized.
	///
	/// It is strongly discouraged to use `signal` on any transformed property.
	public var signal: Signal<Value, NoError> {
		return _signal()
	}

	/// Initializes a property as a read-only view of the given property.
	public init<P: PropertyProtocol where P.Value == Value>(_ property: P) {
		sources = AnyProperty.capture(property)
		disposable = nil
		_value = { property.value }
		_producer = { property.producer }
		_signal = { property.signal }
	}

	/// Initializes a property that first takes on `initialValue`, then each value
	/// sent on a signal created by `producer`.
	public init(initialValue: Value, producer: SignalProducer<Value, NoError>) {
		self.init(propertyProducer: producer.prefix(value: initialValue),
		          capturing: [])
	}

	/// Initializes a property that first takes on `initialValue`, then each value
	/// sent on `signal`.
	public init(initialValue: Value, signal: Signal<Value, NoError>) {
		self.init(propertyProducer: SignalProducer(signal: signal).prefix(value: initialValue),
		          capturing: [])
	}

	/// Initializes a property by applying the unary `SignalProducer` transform on
	/// `property`. The resulting property captures `property`.
	private init<P: PropertyProtocol>(_ property: P, transform: @noescape (SignalProducer<P.Value, NoError>) -> SignalProducer<Value, NoError>) {
		self.init(propertyProducer: transform(property.producer),
		          capturing: AnyProperty.capture(property))
	}

	/// Initializes a property by applying the binary `SignalProducer` transform on
	/// `property` and `anotherProperty`. The resulting property captures `property`
	/// and `anotherProperty`.
	private init<P1: PropertyProtocol, P2: PropertyProtocol>(_ firstProperty: P1, _ secondProperty: P2, transform: @noescape (SignalProducer<P1.Value, NoError>) -> (SignalProducer<P2.Value, NoError>) -> SignalProducer<Value, NoError>) {
		self.init(propertyProducer: transform(firstProperty.producer)(secondProperty.producer),
		          capturing: AnyProperty.capture(firstProperty) + AnyProperty.capture(secondProperty))
	}

	/// Initializes a property from a producer that promises to send at least one
	/// value synchronously in its start handler before sending any subsequent event.
	/// If the producer fails its promise, a fatal error would be raised.
	///
	/// The producer and the signal of the created property would complete only
	/// when the `propertyProducer` completes.
	private init(propertyProducer: SignalProducer<Value, NoError>, capturing sources: [Any]) {
		var value: Value!

		let observerDisposable = propertyProducer.start { event in
			switch event {
			case let .next(newValue):
				value = newValue

			case .completed, .interrupted:
				break

			case let .failed(error):
				fatalError("Receive unexpected error from a producer of `NoError` type: \(error)")
			}
		}

		if value != nil {
			disposable = ScopedDisposable(observerDisposable)
			self.sources = sources

			_value = { value }
			_producer = { propertyProducer }
			_signal = {
				var extractedSignal: Signal<Value, NoError>!
				propertyProducer.startWithSignal { signal, _ in extractedSignal = signal }
				return extractedSignal
			}
		} else {
			fatalError("A producer promised to send at least one value. Received none.")
		}
	}

	/// Check if `property` is an `AnyProperty` and has already captured its sources
	/// using a closure. Returns that closure if it does. Otherwise, returns a closure
	/// which captures `property`.
	private static func capture<P: PropertyProtocol>(_ property: P) -> [Any] {
		if let property = property as? AnyProperty<P.Value> {
			return property.sources
		} else {
			return [property]
		}
	}
}

/// A property that never changes.
public struct ConstantProperty<Value>: PropertyProtocol {

	public let value: Value
	public let producer: SignalProducer<Value, NoError>
	public let signal: Signal<Value, NoError>

	/// Initializes the property to have the given value.
	public init(_ value: Value) {
		self.value = value
		self.producer = SignalProducer(value: value)
		self.signal = .empty
	}
}

/// A mutable property of type `Value` that allows observation of its changes.
///
/// Instances of this class are thread-safe.
public final class MutableProperty<Value>: MutablePropertyType {
	private let observer: Signal<Value, NoError>.Observer

	/// Need a recursive lock around `value` to allow recursive access to
	/// `value`. Note that recursive sets will still deadlock because the
	/// underlying producer prevents sending recursive events.
	private let lock: RecursiveLock

	/// The box of the underlying storage, which may outlive the property
	/// if a returned producer is being retained.
	private let box: Box<Value>

	/// The current value of the property.
	///
	/// Setting this to a new value will notify all observers of `signal`, or signals
	/// created using `producer`.
	public var value: Value {
		get {
			return withValue { $0 }
		}

		set {
			swap(newValue)
		}
	}

	/// A signal that will send the property's changes over time,
	/// then complete when the property has deinitialized.
	public let signal: Signal<Value, NoError>

	/// A producer for Signals that will send the property's current value,
	/// followed by all changes over time, then complete when the property has
	/// deinitialized.
	public var producer: SignalProducer<Value, NoError> {
		return SignalProducer { [box, weak self] producerObserver, producerDisposable in
			if let strongSelf = self {
				strongSelf.withValue { value in
					producerObserver.sendNext(value)
					producerDisposable += strongSelf.signal.observe(producerObserver)
				}
			} else {
				/// As the setter would have been deinitialized with the property,
				/// the underlying storage would be immutable, and locking is no longer necessary.
				producerObserver.sendNext(box.value)
				producerObserver.sendCompleted()
			}
		}
	}

	/// Initializes the property with the given value to start.
	public init(_ initialValue: Value) {
		lock = RecursiveLock()
		lock.name = "org.reactivecocoa.ReactiveCocoa.MutableProperty"

		box = Box(initialValue)
		(signal, observer) = Signal.pipe()
	}

	/// Atomically replaces the contents of the variable.
	///
	/// Returns the old value.
	@discardableResult
	public func swap(_ newValue: Value) -> Value {
		return modify { $0 = newValue }
	}

	/// Atomically modifies the variable.
	///
	/// Returns the old value.
	@discardableResult
	public func modify(_ action: @noescape (inout Value) throws -> Void) rethrows -> Value {
		return try withValue { value in
			try action(&box.value)
			observer.sendNext(box.value)
			return value
		}
	}

	/// Atomically performs an arbitrary action using the current value of the
	/// variable.
	///
	/// Returns the result of the action.
	@discardableResult
	public func withValue<Result>(action: @noescape (Value) throws -> Result) rethrows -> Result {
		lock.lock()
		defer { lock.unlock() }

		return try action(box.value)
	}

	deinit {
		observer.sendCompleted()
	}
}

private class Box<Value> {
	var value: Value

	init(_ value: Value) {
		self.value = value
	}
}

infix operator <~ {
	associativity right

	// Binds tighter than assignment but looser than everything else
	precedence 93
}

/// Binds a signal to a property, updating the property's value to the latest
/// value sent by the signal.
///
/// The binding will automatically terminate when the property is deinitialized,
/// or when the signal sends a `Completed` event.
@discardableResult
public func <~ <P: MutablePropertyType>(property: P, signal: Signal<P.Value, NoError>) -> Disposable {
	let disposable = CompositeDisposable()
	disposable += property.producer.startWithCompleted {
		disposable.dispose()
	}

	disposable += signal.observe { [weak property] event in
		switch event {
		case let .next(value):
			property?.value = value
		case .completed:
			disposable.dispose()
		case .failed, .interrupted:
			break
		}
	}

	return disposable
}

/// Creates a signal from the given producer, which will be immediately bound to
/// the given property, updating the property's value to the latest value sent
/// by the signal.
///
/// The binding will automatically terminate when the property is deinitialized,
/// or when the created signal sends a `Completed` event.
@discardableResult
public func <~ <P: MutablePropertyType>(property: P, producer: SignalProducer<P.Value, NoError>) -> Disposable {
	let disposable = CompositeDisposable()

	producer.startWithSignal { signal, signalDisposable in
		property <~ signal
		disposable += signalDisposable

		disposable += property.producer.startWithCompleted {
			disposable.dispose()
		}
	}

	return disposable
}

@discardableResult
public func <~ <P: MutablePropertyType, S: SignalProtocol where P.Value == S.Value?, S.Error == NoError>(property: P, signal: S) -> Disposable {
	return property <~ signal.optionalize()
}

@discardableResult
public func <~ <P: MutablePropertyType, S: SignalProducerProtocol where P.Value == S.Value?, S.Error == NoError>(property: P, producer: S) -> Disposable {
	return property <~ producer.optionalize()
}

@discardableResult
public func <~ <Destination: MutablePropertyType, Source: PropertyProtocol where Destination.Value == Source.Value?>(destinationProperty: Destination, sourceProperty: Source) -> Disposable {
	return destinationProperty <~ sourceProperty.producer
}

/// Binds `destinationProperty` to the latest values of `sourceProperty`.
///
/// The binding will automatically terminate when either property is
/// deinitialized.
@discardableResult
public func <~ <Destination: MutablePropertyType, Source: PropertyProtocol where Source.Value == Destination.Value>(destinationProperty: Destination, sourceProperty: Source) -> Disposable {
	return destinationProperty <~ sourceProperty.producer
}
