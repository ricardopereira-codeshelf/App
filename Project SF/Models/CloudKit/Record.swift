//
//  Record.swift
//  Project SF
//
//  Created by William Taylor on 11/7/20.
//

import Foundation
import CloudKit

protocol Record {
    
    static var type: CKRecord.RecordType { get }
    
    init(record: CKRecord)

}
