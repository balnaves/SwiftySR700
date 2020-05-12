//
//  HeatController.swift
//  
//
//  Created by James Balnaves on 3/26/20.
//

import Foundation


class HeatController {
    
    var heatLevel: Int = 0 {
        didSet {
            if heatLevel < 0 {
                heatLevel = 0
            }
            else if heatLevel > segmentCount {
                heatLevel = segmentCount
            }
        }
    }
    
    /*
     Use this to determine if it's time to pick up the latest commanded heatLevel value and run a PID controller iteration.
     */
    var aboutToRollOver: Bool {
        get {
            currentIndex >= segmentCount
        }
    }
    
    fileprivate var currentHeatLevel = 0
    fileprivate var currentIndex = 0
    fileprivate var segmentCount = 8
    
    var outputArray = [[Bool]]() // accessible for testing

    init(segmentCount: Int) {
        self.segmentCount = segmentCount
        generateOutputArray(segmentCount)
    }
    
    init() {
        //self.segmentCount = 8
        generateOutputArray(segmentCount)
    }
    
    fileprivate func generateOutputArray(_ size: Int) {
        switch size {
        case 4:
            outputArray = [[false, false, false, false],
                           [true, false, false, false],
                           [true, false, true, false],
                           [true, true, true, false],
                           [true, true, true, true]]
            break
        case 8:
            outputArray = [[false, false, false, false, false, false, false, false],
                           [true, false, false, false, false, false, false, false],
                           [true, false, false, false, true, false, false, false],
                           [true, false, false, true, false, false, true, false],
                           [true, false, true, false, true, false, true, false],
                           [true, true, false, true, true, false, true, false],
                           [true, true, true, false, true, true, true, false],
                           [true, true, true, true, true, true, true, false],
                           [true, true, true, true, true, true, true, true]]
            break
        default:
            outputArray = Array(repeating: Array(repeating: false, count: size), count: size + 1)
            for i in 0...size {
                for j in 0..<size {
                    outputArray[i][j] = j < i
                }
            }
        }
    }
    
    func generateBangBang() -> Bool {
        if currentIndex >= segmentCount {
            // switch to the next level
            currentHeatLevel = heatLevel
            currentIndex = 0
        }
        let out = outputArray[currentHeatLevel][currentIndex]
        currentIndex += 1
        return out
    }
}
