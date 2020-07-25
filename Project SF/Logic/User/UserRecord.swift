//
//  User.swift
//  Project SF
//
//  Created by William Taylor on 10/7/20.
//

import Foundation
import CloudKit

/// - Tag: UserRecord
class UserRecord: DynamicRecord {
    
    // MARK: Properties
    
    static let type = "Users"
    
    static let model = Model()

    let record: CKRecord
    
    // MARK: Model
    
    struct Model {
        let name = ModelItem<String>(key: "name")
        let username = ModelItem<String>(key: "username")
        let bio = ModelItem<String>(key: "bio")
        let profilePictureURL = ModelItem<String>(key: "profilePictureURL")
        let userInfoRecordID = ModelItem<String>(key: "userInfoRecordID")
        let scoreRecordZoneName = ModelItem<String>(key: "scoreRecordZoneName")
        let scoreRecordRecordName = ModelItem<String>(key: "scoreRecordRecordName")
        let scoreRecordPublicShareURL = ModelItem<String>(key: "scoreRecordPublicShareURL")
    }
    
    // MARK: Init
    
    required init(record: CKRecord) {
        self.record = record
    }

}
