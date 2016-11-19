import Foundation
import ReactiveSwift
import enum Result.NoError

private let swizzledClasses = Atomic<Set<ObjectIdentifier>>([])

extension Reactive where Base: NSObject {
	/// Create a signal which sends a `next` event at the end of every invocation
	/// of `selector` on the object.
	///
	/// - note: Observers to the resulting signal should not call the method
	///         specified by the selector.
	///
	/// - parameters:
	///   - selector: The selector to observe.
	///
	/// - returns:
	///   A trigger signal.
	public func trigger(for selector: Selector) -> Signal<(), NoError> {
		return base.synchronized {
			return setupInterception(base, for: selector).map { _ in }
		}
	}

	/// Create a signal which sends a `next` event, containing an array of bridged
	/// arguments, at the end of every invocation of `selector` on the object.
	///
	/// - note: Observers to the resulting signal should not call the method
	///         specified by the selector.
	///
	/// - parameters:
	///   - selector: The selector to observe.
	///
	/// - returns:
	///   A signal that sends an array of bridged arguments.
	public func signal(for selector: Selector) -> Signal<[Any?], NoError> {
		return base.synchronized {
			return setupInterception(base, for: selector).map(unpackInvocation)
		}
	}
}

private var interopImplKey = 0
private var interceptingStatesKey = 0
private var interceptedSelectorsKey = 0

private let NSInvocation: AnyClass = NSClassFromString("NSInvocation")!
private let NSMethodSignature: AnyClass = NSClassFromString("NSMethodSignature")!

// A container to circumvent Swift dynamic bridging overhead.
private final class Box<Value> {
	var value: Value

	init(_ value: Value) {
		self.value = value
	}
}

private func setupInterception(_ object: NSObject, for selector: Selector) -> Signal<AnyObject, NoError> {
	let alias = selector.prefixing("rac0_")

	if let state = object.value(forAssociatedKey: alias.utf8Start) as! InterceptingState? {
		return state.signal
	}

	let subclass: AnyClass = swizzleClass(object)

	swizzledClasses.modify { classes in
		if !classes.contains(ObjectIdentifier(subclass)) {
			classes.insert(ObjectIdentifier(subclass))

			let interopImpls = Box<[Selector: IMP]>([:])
			objc_setAssociatedObject(subclass, &interopImplKey, interopImpls, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

			let signatureCache = Box<[Selector: AnyObject]>([:])
			objc_setAssociatedObject(subclass, &interceptedSelectorsKey, signatureCache, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

			enableMessageForwarding(subclass, interopImpls)
			setupMethodSignatureCaching(subclass, signatureCache)
		}

		let signatureCache = objc_getAssociatedObject(subclass, &interceptedSelectorsKey) as! Box<[Selector: AnyObject]>
		signatureCache.value[selector] = getSignature(subclass, selector)
	}

	guard let method = class_getInstanceMethod(subclass, selector) else {
		fatalError("Selector `\(selector)` does not exist in class `\(String(cString: class_getName(class_getSuperclass(subclass))))`.")
	}

	let impl = method_getImplementation(method)

	if impl != _rac_objc_msgForward {
		let typeEncoding = method_getTypeEncoding(method)!
		assert(checkTypeEncoding(typeEncoding))

		if let existingMethod = class_getImmediateMethod(subclass, selector) {
			// Make a method alias for the existing method implementation, if it is
			// defined in the runtime subclass.
			let existingImpl = method_getImplementation(existingMethod)

			swizzledClasses.modify { _ in
				let interopImpl = objc_getAssociatedObject(subclass, &interopImplKey) as! Box<[Selector: IMP]>
				interopImpl.value[selector] = existingImpl
			}
		}

		// Redefine the selector to call -forwardInvocation:.
		_ = class_replaceMethod(subclass, selector, _rac_objc_msgForward, typeEncoding)
	}

	let state = InterceptingState(lifetime: object.reactive.lifetime)
	object.setValue(state, forAssociatedKey: alias.utf8Start)

	return state.signal
}

private func getSignature(_ objcClass: AnyClass, _ selector: Selector) -> AnyObject {
	let method = class_getInstanceMethod(objcClass, selector)
	let typeEncoding = method_getTypeEncoding(method)!
	return NSMethodSignature.signature(withObjCTypes: typeEncoding)
}

private func enableMessageForwarding(_ objcClass: AnyClass, _ interopImpls: Box<[Selector: IMP]>) {
	// Set up a new version of -forwardInvocation:.
	//
	// If the selector has been passed to -rac_signalForSelector:, invoke
	// the aliased method, and forward the arguments to any attached signals.
	//
	// If the selector has not been passed to -rac_signalForSelector:,
	// invoke any existing implementation of -forwardInvocation:. If there
	// was no existing implementation, throw an unrecognized selector
	// exception.

	let realClass: AnyClass = objcClass
	let perceivedClass: AnyClass = class_getSuperclass(objcClass)

	typealias ForwardInvocationImpl = @convention(block) (NSObject, AnyObject) -> Void
	let newForwardInvocation: ForwardInvocationImpl = { object, invocation in
		let selector = invocation.selector!
		let alias = selector.prefixing("rac0_")

		defer {
			if let state = object.value(forAssociatedKey: alias.utf8Start) as! InterceptingState? {
				state.observer.send(value: invocation)
			}
		}

		// RAC exchanges implementations at runtime so as to invoke the desired
		// version without using fragile dependencies like libffi. This means
		// all instances that had been applied `signalForSelector:` are
		// non-threadsafe as any mutable instances.

		let method = class_getInstanceMethod(perceivedClass, selector)
		let typeEncoding = method_getTypeEncoding(method)

		if let interopImpl = interopImpls.value[selector] {
			// `self` uses a runtime subclass generated by third-party APIs, and RAC
			// found an existing implementation for the selector at the setup time.
			// Call that implementation if it is not the ObjC message forwarder.
			//
			// The IMP swapping would flush the IMP cache.
			let previousImpl = class_replaceMethod(realClass, selector, interopImpl, typeEncoding)
			invocation.invoke()
			_ = class_replaceMethod(realClass, selector, previousImpl, typeEncoding)

			return
		}

		if let impl = method.map(method_getImplementation), impl != _rac_objc_msgForward {
			// The stated class has an implementation of the selector. Call that
			// implementation if it is not the ObjC message forwarder.

			// Update the alias only if the implementation has been changed to avoid
			// flushing the IMP cache.
			let method = class_getImmediateMethod(realClass, alias)

			if method == nil || method_getImplementation(method!) != impl {
				_ = class_replaceMethod(realClass, alias, impl, typeEncoding)
			}

			invocation.setSelector(alias)
			invocation.invoke()

			return
		}

		// Forward the invocation to the closest `forwardInvocation:` in the
		// inheritance hierarchy.
		typealias SuperForwardInvocation = @convention(c) (AnyObject, Selector, AnyObject) -> Void
		let impl = class_getMethodImplementation(perceivedClass, ObjCSelector.forwardInvocation)
		let forwardInvocation = unsafeBitCast(impl, to: SuperForwardInvocation.self)
		forwardInvocation(object, ObjCSelector.forwardInvocation, invocation)
	}

	_ = class_replaceMethod(objcClass,
	                        ObjCSelector.forwardInvocation,
	                        imp_implementationWithBlock(newForwardInvocation as Any),
	                        ObjCMethodEncoding.forwardInvocation)
}

private func setupMethodSignatureCaching(_ objcClass: AnyClass, _ signatureCache: Box<[Selector: AnyObject]>) {
	let perceivedClass: AnyClass = class_getSuperclass(objcClass)

	let newMethodSignatureForSelector: @convention(block) (NSObject, Selector) -> AnyObject? = { object, selector in
		if let signature = signatureCache.value[selector] {
			return signature
		}

		typealias SuperMethodSignatureForSelector = @convention(c) (AnyObject, Selector, Selector) -> AnyObject?
		let impl = class_getMethodImplementation(perceivedClass, ObjCSelector.methodSignatureForSelector)
		let methodSignatureForSelector = unsafeBitCast(impl, to: SuperMethodSignatureForSelector.self)
		return methodSignatureForSelector(object, ObjCSelector.methodSignatureForSelector, selector)
	}

	_ = class_replaceMethod(objcClass,
	                        ObjCSelector.methodSignatureForSelector,
	                        imp_implementationWithBlock(newMethodSignatureForSelector as Any),
	                        ObjCMethodEncoding.methodSignatureForSelector)
}

private final class InterceptingState {
	let (signal, observer) = Signal<AnyObject, NoError>.pipe()

	init(lifetime: Lifetime) {
		lifetime.ended.observeCompleted(observer.sendCompleted)
	}
}

extension Selector {
	fileprivate var utf8Start: UnsafePointer<Int8> {
		return unsafeBitCast(self, to: UnsafePointer<Int8>.self)
	}

	public func prefixing(_ prefix: StaticString) -> Selector {
		assert(prefix.isASCII)

		let length = Int(strlen(utf8Start))
		let prefixedLength = length + prefix.utf8CodeUnitCount

		let asciiPrefix = UnsafeRawPointer(prefix.utf8Start).assumingMemoryBound(to: Int8.self)

		let cString = UnsafeMutablePointer<Int8>.allocate(capacity: prefixedLength + 1)
		defer {
			cString.deinitialize()
			cString.deallocate(capacity: prefixedLength + 1)
		}

		cString.initialize(from: asciiPrefix, count: prefix.utf8CodeUnitCount)
		(cString + prefix.utf8CodeUnitCount).initialize(from: utf8Start, count: length)
		(cString + prefixedLength).initialize(to: Int8(UInt8(ascii: "\0")))

		return sel_registerName(cString)
	}
}

private func checkTypeEncoding(_ types: UnsafePointer<CChar>) -> Bool {
	// Some types, including vector types, are not encoded. In these cases the
	// signature starts with the size of the argument frame.
	assert(types.pointee < Int8(UInt8(ascii: "1")) || types.pointee > Int8(UInt8(ascii: "9")),
	       "unknown method return type not supported in type encoding: \(String(cString: types))")

	assert(types.pointee != Int8(UInt8(ascii: "(")), "union method return type not supported")
	assert(types.pointee != Int8(UInt8(ascii: "{")), "struct method return type not supported")
	assert(types.pointee != Int8(UInt8(ascii: "[")), "array method return type not supported")

	assert(types.pointee != Int8(UInt8(ascii: "j")), "complex method return type not supported")

	return true
}

private func unpackInvocation(_ invocation: AnyObject) -> [Any?] {
	let invocation = invocation as AnyObject
	let methodSignature = invocation.objcMethodSignature!
	let count = UInt(methodSignature.numberOfArguments!)

	var bridged = [Any?]()
	bridged.reserveCapacity(Int(count - 2))

	// Ignore `self` and `_cmd`.
	for position in 2 ..< count {
		let rawEncoding = methodSignature.argumentType(at: position)
		let encoding = TypeEncoding(rawValue: rawEncoding.pointee) ?? .undefined

		func extract<U>(_ type: U.Type) -> U {
			let pointer = UnsafeMutableRawPointer.allocate(bytes: MemoryLayout<U>.size,
			                                               alignedTo: MemoryLayout<U>.alignment)
			defer {
				pointer.deallocate(bytes: MemoryLayout<U>.size,
				                   alignedTo: MemoryLayout<U>.alignment)
			}

			invocation.copy(to: pointer, forArgumentAt: Int(position))
			return pointer.assumingMemoryBound(to: type).pointee
		}

		switch encoding {
		case .char:
			bridged.append(NSNumber(value: extract(CChar.self)))
		case .int:
			bridged.append(NSNumber(value: extract(CInt.self)))
		case .short:
			bridged.append(NSNumber(value: extract(CShort.self)))
		case .long:
			bridged.append(NSNumber(value: extract(CLong.self)))
		case .longLong:
			bridged.append(NSNumber(value: extract(CLongLong.self)))
		case .unsignedChar:
			bridged.append(NSNumber(value: extract(CUnsignedChar.self)))
		case .unsignedInt:
			bridged.append(NSNumber(value: extract(CUnsignedInt.self)))
		case .unsignedShort:
			bridged.append(NSNumber(value: extract(CUnsignedShort.self)))
		case .unsignedLong:
			bridged.append(NSNumber(value: extract(CUnsignedLong.self)))
		case .unsignedLongLong:
			bridged.append(NSNumber(value: extract(CUnsignedLongLong.self)))
		case .float:
			bridged.append(NSNumber(value: extract(CFloat.self)))
		case .double:
			bridged.append(NSNumber(value: extract(CDouble.self)))
		case .bool:
			bridged.append(NSNumber(value: extract(CBool.self)))
		case .object:
			bridged.append(extract((AnyObject?).self))
		case .type:
			bridged.append(extract((AnyClass?).self))
		case .selector:
			bridged.append(extract((Selector?).self))
		case .undefined:
			var size = 0, alignment = 0
			NSGetSizeAndAlignment(rawEncoding, &size, &alignment)
			let buffer = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: alignment)
			defer { buffer.deallocate(bytes: size, alignedTo: alignment) }

			invocation.copy(to: buffer, forArgumentAt: Int(position))
			bridged.append(NSValue(bytes: buffer, objCType: rawEncoding))
		}
	}

	return bridged
}

private enum TypeEncoding: Int8 {
	case char = 99
	case int = 105
	case short = 115
	case long = 108
	case longLong = 113

	case unsignedChar = 67
	case unsignedInt = 73
	case unsignedShort = 83
	case unsignedLong = 76
	case unsignedLongLong = 81

	case float = 102
	case double = 100

	case bool = 66

	case object = 64
	case type = 35
	case selector = 58

	case undefined = -1
}
