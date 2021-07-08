//
//  Extensions.swift
//  TextOCR
//
//  Created by Mohammad Gharari on 7/3/20.
//  Copyright © 2020 Mohammad Gharari. All rights reserved.
//

import UIKit

extension UIImage {
    var cgImageOrientation : CGImagePropertyOrientation
    {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        case .left: return .left
        default: return.up
            
        }
    }
}



extension String
{
    func trim() -> String
    {
        return self.trimmingCharacters(in: CharacterSet.whitespaces)
    }
}
