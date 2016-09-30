//
//  UIBarButtonItem.swift
//  Rex
//
//  Created by Bjarke Hesthaven Søndergaard on 24/07/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import UIKit

extension UIBarButtonItem {
	/// Exposes a property that binds an action to bar button item. The action is set as
	/// a target of the button. When property changes occur the previous action is
	/// overwritten. This also binds the enabled state of the action to the `rac_enabled`
	/// property on the button.
	public var rac_action: MutableProperty<CocoaAction> {
		return associatedObject(self, key: &actionKey) { host in
			let initial = CocoaAction.disabled
			let property = MutableProperty(initial)

			property.producer
				.startWithValues { [weak host] action in
					host?.target = action
					host?.action = CocoaAction.selector
			}

			host.rac_enabled <~ property.flatMap(.latest) { $0.isEnabled }

			return property
		}
	}
}

private var actionKey: UInt8 = 0
