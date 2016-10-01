//
//  UIBarItem.swift
//  Rex
//
//  Created by Bjarke Hesthaven Søndergaard on 24/07/15.
//  Copyright (c) 2015 Neil Pankey. All rights reserved.
//

import ReactiveSwift
import UIKit

extension Reactivity where Reactant: UIBarItem {
	/// Wraps a UIBarItem's `enabled` state in a bindable property.
	public var isEnabled: BindingTarget<Bool> {
		return bindingTarget { $0.isEnabled = $1 }
	}
}
