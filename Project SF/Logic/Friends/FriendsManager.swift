//
//  FriendsManager.swift
//  Project SF
//
//  Created by Christian Privitelli on 24/7/20.
//

import CloudKit

class FriendsManager: ObservableObject {
    
    // MARK: Properties
    
    private let container: CKContainer
    private let cloudKitStore = CloudKitStore.shared
    
    init(container: CKContainer = .appDefault) {
        self.container = container
    }
    
    /// Requests permission from the user to discover their contacts.
    /// - Parameter handler: The result handler. Not guaranteed to be executed on the main thread.
    /// - Tag: requestDiscoveryPermission
    func requestDiscoveryPermission(then handler: @escaping (Result<Bool, Error>) -> Void) {
        container.requestApplicationPermission([.userDiscoverability]) { (status, error) in
            if let error = error {
                handler(.failure(error))
                return
            }
            switch status {
            case .granted:
                handler(.success(true))
            case .denied:
                handler(.success(false))
            default:
                handler(.failure(FriendsManagerError.unknownError))
            }
        }
    }
    
    /// Asynchronously discovers the users friends. Fails if the adequate permissions have not been granted (you can request the required permission using [requestDiscoveryPermission](x-source-tag://requestDiscoveryPermission).
    /// - Parameter handler: The result handler. Not guaranteed to be executed on the main thread.
    func discoverFriends(then handler: @escaping (Result<[Friend], Error>) -> Void) {
        container.status(forApplicationPermission: .userDiscoverability) { [weak container] status, error in
            guard let container = container else { return }
            if let error = error {
                handler(.failure(error))
                return
            }
            if case .granted = status {
                container.discoverAllIdentities { identities, error in
                    if let error = error {
                        handler(.failure(error))
                        return
                    }
                    guard let identities = identities else {
                        handler(.failure(FriendsManagerError.unknownError))
                        return
                    }
                    print(identities)
                    
                    var friends: [Friend] = []
                    
                    for identity in identities {
                        let recordID = identity.userRecordID?.recordName ?? ""
                        let predicate = NSPredicate(format: "userRecordID == %@", recordID)
                        
                        CloudKitStore.shared.fetchRecords(
                            with: PublicUserRecord.self,
                            predicate: predicate,
                            scope: .public
                        ) { result in
                            switch result {
                            case .success(let records):
                                for user in records {
                                    friends.append(user.asFriend())
                                    
                                    if identity == identities.last && user.record == records.last?.record {
                                        handler(.success(friends))
                                    }
                                }
                            case .failure:
                                break
                            }
                        }
                    }
                }
            } else {
                handler(.failure(FriendsManagerError.insufficientPermissions))
            }
        }
    }
    
    // ** DONT USE ANYTHING BELOW YET **
    
    /// Creates empty SharedWithFriendsData record for current user as well as a share and saves it to the private db.
    /// - Parameter handler: What to do when the operation completes.
    ///
    /// This method is required before inviting or sharing other users. It creates a zone named SharedWithFriendsDataZone for information shared with your friends in your private db. A SharedWithFriendsData record is created inside that zone and will hold all data that should be only shared with friends. This record should hold activity, competiton and user info or any other data that should be shared with friends depending on the users settings. A share is created with public permission set to none so that only invited users/friends can access the data. The **private** user record is modified to contain the URL to the share sharing the SharedWithFriendsDataRecord.
    func beginSharing(completion: @escaping (Error?) -> Void) {
        /// Create new randomized zone in your private db to share your activity data.
        cloudKitStore.createZone(named: "SharedWithFriendsDataZone") { result in
            switch result {
            case .success(let zone):
                self.cloudKitStore.fetchUserRecord { result in
                    switch result {
                    case .success(let userRecord):
                        /// Create an empty `SharedWithFriendsData` record in the created zone.
                        let sharedData = SharedUserRecord(recordID: CKRecord.ID(zoneID: zone.zoneID))
                        sharedData.name = userRecord.name
                        sharedData.username = userRecord.username
                        sharedData.bio = userRecord.bio
                        sharedData.profilePictureURL = userRecord.profilePictureURL
                        
                        /// Create a share from the created activity record and set the public permission to none so no one can access it unless we explicitly allow them.
                        let share = CKShare(rootRecord: sharedData.record)
                        share.publicPermission = .none
                        
                        /// Operation to save the activity record and share.
                        let operation = CKModifyRecordsOperation(
                            recordsToSave: [sharedData.record, share],
                            recordIDsToDelete: nil
                        )
                        operation.qualityOfService = .userInitiated
                        
                        /// Placeholder for if saving share is successful.
                        var savedShare: CKShare?
                        
                        operation.perRecordCompletionBlock = { record, error in
                            if let error = error {
                                completion(error)
                            }
                            if let record = record as? CKShare {
                                savedShare = record
                            }
                        }
                        
                        operation.completionBlock = {
                            guard let savedShare = savedShare, let url = savedShare.url else {
                                completion(FriendsManagerError.unknownError)
                                return
                            }
                            
                            /// Save the saved share url to the user record so it can be accessed later.
                            userRecord.friendShareURL = url.absoluteString
                            self.cloudKitStore.saveUserRecord(userRecord) { result in
                                switch result {
                                case .success:
                                    completion(nil)
                                case .failure(let error):
                                    completion(error)
                                }
                            }
                        }
                        
                        self.container.privateCloudDatabase.add(operation)
                    case .failure(let error):
                        completion(error)
                    }
                }
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    func fetchFriends(completion: @escaping (Result<[Friend], Error>) -> Void) {
        cloudKitStore.fetchUserRecord { result in
            switch result {
            case .success(let privateUserRecord):
                let friendShareURLs = privateUserRecord.friendShareURLs?.map { URL(string: $0)! } ?? []
                let metadataFetchOperation = CKFetchShareMetadataOperation(shareURLs: friendShareURLs)
                metadataFetchOperation.qualityOfService = .userInitiated
                
                var friends: [Friend] = []
                
                metadataFetchOperation.perShareMetadataBlock = { _, metadata, error in
                    if let error = error {
                        completion(.failure(error))
                        print(error)
                        return
                    }
                    guard let metadata = metadata else { return }
                    let sharedUser = SharedUserRecord(record: metadata.rootRecord!)
                    let publicUserRecordID = CKRecord.ID(recordName: sharedUser.publicUserRecordName ?? "")
                    
                    let friend = Friend(
                        username: sharedUser.username ?? "",
                        name: sharedUser.name ?? "",
                        bio: sharedUser.bio ?? "",
                        profilePictureURL: sharedUser.profilePictureURL ?? "",
                        publicUserRecordID: publicUserRecordID,
                        privateUserRecordID: privateUserRecord.record.recordID
                    )
                    
                    friends.append(friend)
                }
                
                metadataFetchOperation.fetchShareMetadataCompletionBlock = { error in
                    if let error = error {
                        completion(.failure(error))
                    }
                    completion(.success(friends))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Create a singular friend request to a friend and save it to the public db.
    /// - Parameters:
    ///   - friend: The friend you would like to invite.
    ///   - completion: What to do when the operation completes.
    ///
    /// See the `invite(friends: [Friends])` method for more documentation.
    func invite(user: String, completion: @escaping (Error?) -> Void) {
        invite(users: [user], completion: completion)
    }
    
    /// Creates friend requests for each friend in the array of friends input in the public db.
    /// - Parameters:
    ///   - users: The users you would like to invite. Array of private user record names.
    ///   - completion: What to do when the operation completes.
    ///
    /// For this function to work correctly, a CKShare containing data to share with friends is required. Only run this function after you are  sure you have previously run `beginSharing`, otherwise it will fail.
    ///
    /// This function starts by fetching the current user record to get the share url for the CKShare you saved previously, if you have not saved previously and the URL cannot be found, it will complete with an error. After it fetches the URL, it uses a `CKFetchShareMetadataOperation` to get the metadata for the share URL. This metadata includes the share itself. We then convert the friends into CKShare.Participants and add them to the share. The changes to the share are saved with a `CKModifyRecordsOperation`. Upon completion of adding the participants to the share, we create the requests to be stored in the public db so other users can see if they have pending friend requests in which they can accept from the share url. It is ok to make this public as the public permission for the share is set to none and only people we have added as participants will be able to read the data.
    func invite(users: [String], completion: @escaping (Error?) -> Void) {
        /// Get the current user record.
        cloudKitStore.fetchUserRecord { result in
            switch result {
            case .success(let record):
                
                /// Get the friend share url from the fetched user record.
                guard let shareURLString = record.friendShareURL,
                      let shareURL = URL(string: shareURLString) else {
                    completion(FriendsManagerError.unknownError)
                    return
                }
                
                /// Fetch the share metadata from the friend share URL.
                let metadataFetchOperation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
                metadataFetchOperation.qualityOfService = .userInitiated
                
                var shareMetadata: [CKShare.Metadata] = []
                
                metadataFetchOperation.perShareMetadataBlock = { _, metadata, error in
                    if let error = error {
                        completion(error)
                    }
                    guard let metadata = metadata else { return }
                    shareMetadata.append(metadata)
                }
                
                metadataFetchOperation.fetchShareMetadataCompletionBlock = { error in
                    if let error = error {
                        completion(error)
                    }
                    
                    /// Get the associated share from the share metadata.
                    guard let shareURLMetadata = shareMetadata.first(where: { $0.share.url == shareURL }) else { return }
                    let share = shareURLMetadata.share
                    
                    /// Convert friends into CKShare Participants.
                    self.fetchShareParticipantsFromRecordNames(users: users) { result in
                        switch result {
                        case .success(let participants):
                            
                            /// Set the friends to have read access to the share. This will let them access your activity data.
                            for participant in participants {
                                participant.permission = .readOnly
                                share.addParticipant(participant)
                            }
                            
                            let operation = CKModifyRecordsOperation(
                                recordsToSave: [share],
                                recordIDsToDelete: nil
                            )
                            operation.qualityOfService = .userInitiated
                            
                            var savedShare: CKShare?
                            var shareCreationError: Error?
                            
                            operation.perRecordCompletionBlock = { record, error in
                                if let record = record as? CKShare {
                                    shareCreationError = error
                                    savedShare = record
                                }
                            }
                            
                            operation.completionBlock = {
                                if let error = shareCreationError {
                                    completion(error)
                                    return
                                }
                                guard let savedShare = savedShare, let url = savedShare.url else {
                                    completion(FriendsManagerError.unknownError)
                                    return
                                }
                                
                                /// Invite the friends by creating an invite with the friends user record name and save it to the public db.
                                var inviteRecords: [FriendRequestRecord] = []
                                
                                for userRecordName in users {
                                    let invite = FriendRequestRecord()
                                    invite.inviteePrivateUserRecordName = userRecordName
                                    invite.creatorPublicUserRecordName = record.publicUserRecordName
                                    invite.creatorShareURL = url.absoluteString
                                    inviteRecords.append(invite)
                                }
                                
                                let saveInvitationsOperations = CKModifyRecordsOperation(
                                    recordsToSave: inviteRecords.map({ $0.record }),
                                    recordIDsToDelete: nil
                                )
                                
                                saveInvitationsOperations.modifyRecordsCompletionBlock = { _, _, error in
                                    if let error = error {
                                        print(error)
                                        return
                                    }
                                    completion(nil)
                                }
                                
                                self.container.publicCloudDatabase.add(saveInvitationsOperations)
                            }
                            
                            self.container.privateCloudDatabase.add(operation)
                        case .failure(let error):
                            print(error)
                            completion(error)
                        }
                    }
                }
                self.container.add(metadataFetchOperation)
            case .failure(let error):
                print(error)
                completion(error)
            }
        }
    }
    
    /// Subscribe to new friend requests sent to the current user. A silent notification with the invite data will be sent and handled in the AppDelegate.
    /// - Parameter completion: What to do when the operation completes.
    func subscribeToFriendRequests(completion: @escaping (Error?) -> Void) {
        cloudKitStore.fetchUserRecord { result in
            switch result {
            case .success(let record):
                let predicate = NSPredicate(
                    format: "inviteeRecordName = %@", record.record.recordID.recordName
                )
                let subscription = CKQuerySubscription(
                    recordType: "FriendRequest",
                    predicate: predicate,
                    options: .firesOnRecordCreation
                )
                
                let notification = CKSubscription.NotificationInfo()
                notification.shouldSendContentAvailable = true
                
                subscription.notificationInfo = notification
                
                self.container.publicCloudDatabase.save(subscription) { _, error in
                    if let error = error {
                        completion(error)
                    }
                    completion(nil)
                }
            case .failure(let error):
                completion(error)
            }
        }
    }

    func fetchFriendRequests(type: FriendRequestType, completion: @escaping (Result<[FriendRequestRecord], Error>) -> Void) {
        container.fetchUserRecordID { recordID, error in
            if let error = error {
                completion(.failure(error))
            }
            guard let recordID = recordID else {
                completion(.failure(FriendsManagerError.unknownError))
                return
            }
            
            let userRecord = UserRecord(recordID: recordID)
            
            let predicate = NSPredicate(
                format: type == .received ? "inviteePrivateUserRecordName == %@" :
                                            "creatorPublicUserRecordName == %@",
                type == .received ? recordID.recordName : userRecord.publicUserRecordName!
            )
            let query = CKQuery(
                recordType: FriendRequestRecord.type,
                predicate: type == .all ? NSPredicate(value: true) : predicate
            )
            let operation = CKQueryOperation(query: query)
            
            operation.qualityOfService = .userInitiated
            var invitationRecords: [FriendRequestRecord] = []
            
            operation.recordFetchedBlock = { record in
                invitationRecords.append(FriendRequestRecord(record: record))
            }
            
            operation.queryCompletionBlock = { _, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(invitationRecords))
            }
            
            self.container.publicCloudDatabase.add(operation)
        }
    }
    
    func fetchAndCleanAcceptedRequests(completion: @escaping (Error?) -> Void) {
        cloudKitStore.fetchUserRecord { result in
            switch result {
            case .success(let privateUserRecord):
                let creatorPredicate = NSPredicate(format: "creatorPublicUserRecordName", privateUserRecord.publicUserRecordName ?? "")
                let acceptedPredicate = NSPredicate(format: "accepted == true")
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [creatorPredicate, acceptedPredicate])
                self.cloudKitStore.fetchRecords(with: FriendRequestRecord.self, predicate: predicate, scope: .public) { result in
                    switch result {
                    case .success(let friendRequests):
                        for friendRequest in friendRequests {
                            let friendRequestRecordID = friendRequest.record.recordID
                            if friendRequest.inviteeShareURL != nil && friendRequest.accepted ?? false {
                                privateUserRecord.friendShareURLs?.append(friendRequest.inviteeShareURL!)
                                self.cloudKitStore.deleteRecord(with: friendRequestRecordID, scope: .public) { result in
                                    switch result {
                                    case .success:
                                        if friendRequests.last?.record == friendRequest.record {
                                            completion(nil)
                                        }
                                    case .failure(let error):
                                        completion(error)
                                    }
                                }
                            }
                        }
                    case .failure(let error):
                        completion(error)
                    }
                }
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    func acceptFriendRequest(invitation: FriendRequestRecord, completion: @escaping (Error?) -> Void) {
        guard let shareURLString = invitation.creatorShareURL,
              let shareURL = URL(string: shareURLString) else {
            completion(FriendsManagerError.unknownError)
            return
        }
        
        let metadataFetchOperation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
        metadataFetchOperation.qualityOfService = .userInitiated
        
        var shareMetadata: [CKShare.Metadata] = []
        
        metadataFetchOperation.perShareMetadataBlock = { _, metadata, error in
            if let error = error {
                completion(error)
                print(error)
                return
            }
            guard let metadata = metadata else { return }
            shareMetadata.append(metadata)
        }
        
        metadataFetchOperation.fetchShareMetadataCompletionBlock = { error in
            if let error = error {
                completion(error)
                print(error)
            }

            let acceptOperation = CKAcceptSharesOperation(shareMetadatas: shareMetadata)
            acceptOperation.qualityOfService = .userInitiated
            
            acceptOperation.acceptSharesCompletionBlock = { error in
                if let error = error {
                    completion(error)
                }
                self.cloudKitStore.fetchUserRecord { result in
                    switch result {
                    case .success(let userRecord):
                        if userRecord.friendShareURLs == nil {
                            userRecord.friendShareURLs = []
                        }
                        userRecord.friendShareURLs!.append(shareURL.absoluteString)
                        self.cloudKitStore.saveUserRecord(userRecord) { result in
                            switch result {
                            case .success:
                                invitation.inviteeShareURL = userRecord.friendShareURL
                                invitation.accepted = true
                                self.cloudKitStore.saveRecord(invitation.record, scope: .public) { result in
                                    switch result {
                                    case .success:
                                        completion(nil)
                                    case .failure(let error):
                                        completion(error)
                                    }
                                }
                            case .failure(let error):
                                completion(error)
                            }
                        }
                    case .failure(let error):
                        completion(error)
                    }
                }
            }
            
            self.container.add(acceptOperation)
        }
        container.add(metadataFetchOperation)
    }
    
    /// Fetches share participants that can be used with a CKShare.
    private func fetchShareParticipantsFromRecordNames(
        users: [String],
        then completion: @escaping (Result<[CKShare.Participant], Error>) -> Void
    ) {
        let lookupInfo = users.map { CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: $0)) }
        let fetchParticipantsOperation = CKFetchShareParticipantsOperation(
            userIdentityLookupInfos: lookupInfo
        )
        fetchParticipantsOperation.qualityOfService = .userInitiated
        
        var participants = [CKShare.Participant]()
        
        fetchParticipantsOperation.shareParticipantFetchedBlock = { participant in
            participants.append(participant)
        }
        
        fetchParticipantsOperation.fetchShareParticipantsCompletionBlock = { error in
            if let error = error, participants.count == 0 {
                completion(.failure(error))
                return
            }
            let returnValue: [CKShare.Participant] = participants
            completion(.success(returnValue))
        }
        self.container.add(fetchParticipantsOperation)
    }
    
    // MARK: Friends Manager Error
    
    enum FriendsManagerError: Error {
        case unknownError
        case insufficientPermissions
    }
    
    enum FriendRequestType {
        case sent
        case received
        case all
    }
}
//let shareURLMetadata = shareMetadata.first { $0.share.url == shareURL }
//if let error = error {
//    completion(error)
//    print(error)
//    return
//}
//let fetchURLHolderOperation = CKFetchRecordsOperation(recordIDs: [shareURLMetadata!.rootRecordID])
//fetchURLHolderOperation.qualityOfService = .userInitiated
//fetchURLHolderOperation.fetchRecordsCompletionBlock = { records, error in
//    if let error = error {
//        completion(error)
//        print(error)
//        return
//    }
//    guard let recordRaw = records?.first?.value else {
//        completion(error)
//        return
//    }
//    //let record = SharedUserRecord(record: recordRaw)
//    completion(nil)
//}
//
//self.container.sharedCloudDatabase.add(fetchURLHolderOperation)
