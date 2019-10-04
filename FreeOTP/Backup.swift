//
//  Backup.swift
//  FreeOTP
//
//  Created by Justin Stephenson on 9/30/19.
//  Copyright © 2019 Fedora Project. All rights reserved.
//

import Foundation

enum BackupDecision: Int {
    case undecided          // No backup decision made
    case enabled            // Backup feature has been enabled
    case softDisabled       // Backup is not(yet) enabled, but not permanently disabled
    case hardDisabled       // Backup functionality is removed entirely
}

final class Backup: NSObject, NSCoding, KeychainStorable {
    // FIXME: private vars?
    static var store = KeychainStore<Backup>()
    let account = "backup-account"
    var backupChoice = BackupDecision.undecided
    // FIXME: Struct for masterkey
    private var backupMasterKey = [UInt8]()
    private var backupMasterKeySalt = [UInt8]()
    private var backupMasterKeyIVData = Data()
    private var tokenArray = [Token]()
    private var otpArray = [OTP]()
    
    func encode(with coder: NSCoder) {
            coder.encode(backupChoice.rawValue, forKey: "backupChoice")
            coder.encode(backupMasterKey, forKey: "backupMasterKey")
            coder.encode(backupMasterKeySalt, forKey: "backupMasterKeySalt")
            coder.encode(backupMasterKeyIVData, forKey: "backupMasterKeyIVData")
            coder.encode(tokenArray, forKey: "tokenArray")
            coder.encode(otpArray, forKey: "otpArray")
    }

    required init?(coder: NSCoder) {
        if coder.containsValue(forKey: "backupChoice") {
            backupChoice = BackupDecision(rawValue: coder.decodeInteger(forKey: "backupChoice")) ?? .undecided
        }
        
        if coder.containsValue(forKey: "backupMasterKey") {
            backupMasterKey = coder.decodeObject(forKey: "backupMasterKey") as! [UInt8]
        }

        if coder.containsValue(forKey: "backupMasterKeySalt") {
            backupMasterKeySalt = coder.decodeObject(forKey: "backupMasterKeySalt") as! [UInt8]
        }
        
        if coder.containsValue(forKey: "backupMasterKeyIVData") {
            backupMasterKeyIVData = coder.decodeObject(forKey: "backupMasterKeyIVData") as! Data
        }

        if coder.containsValue(forKey: "tokenArray") {
            tokenArray = coder.decodeObject(forKey: "tokenArray") as! [Token]
        }

        if coder.containsValue(forKey: "otpArray") {
            otpArray = coder.decodeObject(forKey: "otpArray") as! [OTP]
        }
    }

    override init() {
        super.init()
    }

    private func generate_random(count: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: 32)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }

        if result == errSecSuccess {
            return data
        } else {
            return nil
        }
    }

    private func deriveKey(password: String, salt: [UInt8], rounds: Int) -> [UInt8]! {
        var derivedKeyData = [UInt8](repeating: 0, count: kCCKeySizeAES256)
        
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                          password,
                                          password.utf8.count,
                                          salt,
                                          salt.count,
                                          CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256),
                                          UInt32(rounds),
                                          &derivedKeyData,
                                          kCCKeySizeAES256)

        // FIXME: Remove prints
        if status == kCCSuccess {
            return derivedKeyData
        } else {
            print("ERROR deriving key")
            return nil
        }
    }
    
    private func aesCrypt(data: Data, keyData: Data, ivData: Data, operation: Int) -> Data! {
         let cryptLength  = size_t(data.count + kCCBlockSizeAES128)
         var cryptData = Data(count:cryptLength)
         let keyLength = size_t(kCCKeySizeAES256)
         let options = CCOptions(kCCOptionPKCS7Padding)
         var numBytesEncrypted: size_t = 0

         let cryptStatus = cryptData.withUnsafeMutableBytes {cryptBytes in
             data.withUnsafeBytes {dataBytes in
                 ivData.withUnsafeBytes {ivBytes in
                     keyData.withUnsafeBytes {keyBytes in
                         CCCrypt(CCOperation(operation),
                                   CCAlgorithm(kCCAlgorithmAES),
                                   options,
                                   keyBytes, keyLength,
                                   ivBytes,
                                   dataBytes, data.count,
                                   cryptBytes, cryptLength,
                                   &numBytesEncrypted)
                     }
                 }
             }
         }

         if UInt32(cryptStatus) == UInt32(kCCSuccess) {
             cryptData.removeSubrange(numBytesEncrypted..<cryptData.count)
         } else {
            return nil
         }

         return cryptData;
     }
    
    // FIXME: Remove
    func addTestTokens() {
        let urlc = URLComponents(string: "otpauth://hotp/Example:alice@google.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example2&image=http%3A%2F%2Ffoo%2Fbar")
        _ = TokenStore().add(urlc!)
        
        let urlc2 = URLComponents(string: "otpauth://hotp/foo?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====&algorithm=SHA256&digits=8")
        _ = TokenStore().add(urlc2!)
    }
    
    // FIXME: Add comments to each function
    func loadDecision() -> BackupDecision? {
        let defaults = UserDefaults.standard

        if let decision = BackupDecision(rawValue: defaults.integer(forKey: "backupDecision")) {
            print("returning loaded \(decision)")
            backupChoice = decision
            return decision
        }
        
        print("loadDecision: nil")
        return nil
    }

    // FIXME: Add comments to each function
    func saveDecision(decision: BackupDecision) -> Bool {
        let defaults = UserDefaults.standard
        defaults.set(decision.rawValue, forKey: "backupDecision")
        print("saving decision \(decision)")

        return true
    }
    
    // Perform a one-time Token Backup, encrypting token data with provided key
    func triggerBackup(key: [UInt8]) -> Int? {
        // Add OTP and Token instances into their respective Arrays
        let ts = TokenStore()

        if ts.count == 0 {
            return nil
        }
        
        for index in 0..<ts.count {
            if let token = ts.load(index) {
                let tknaccount = token.account
                print("Loaded index \(index) token")
                // Only add if both token and OTP data is found
                if let otp = OTP.store.load(tknaccount) {
                    print("adding: \(tknaccount) to array")
                    tokenArray.append(token)
                    otpArray.append(otp)
                } else {
                    continue
                }
            }
        }

        if tokenArray.isEmpty || otpArray.isEmpty {
            return nil
        }

        // Encode token array into Data
        let tokenArrayData = NSKeyedArchiver.archivedData(withRootObject: tokenArray)
        
        // Encrypt encoded data with master key
        let keyData = Data(bytes: key, count: key.count)
        let ivData = backupMasterKeyIVData

        if let encryptedTokenData = aesCrypt(data: tokenArrayData, keyData: keyData, ivData: ivData, operation: kCCEncrypt) {
            print("encrypted Token Data!")
            // Store encrypted data in userDefaults
            let defaults = UserDefaults.standard
            defaults.set(encryptedTokenData, forKey: "encryptedTokenData")
            print("Token Backup success")
        } else {
            return nil
        }
        
        let otpArrayData = NSKeyedArchiver.archivedData(withRootObject: otpArray)
        if let encryptedOTPData = aesCrypt(data: otpArrayData, keyData: keyData, ivData: ivData, operation: kCCEncrypt) {
            print("encrypted OTP Data!")
            let defaults = UserDefaults.standard
            defaults.set(encryptedOTPData, forKey: "encryptedOTPData")
            print("OTP Backup success")
        } else {
            return nil
        }

        return 0
    }
    
    @discardableResult func performBackup(choice: BackupDecision) -> Bool? {
        print("performBackup!, choice is \(choice)")
        var rc = 0
        // Load master key from keystore
        guard let bkp = Backup.store.load(account) else {
            return nil
        }
        
        backupMasterKey = bkp.backupMasterKey
        backupMasterKeySalt = bkp.backupMasterKeySalt
        backupMasterKeyIVData = bkp.backupMasterKeyIVData
        
        // FIXME: randomKey
        switch choice {
        case .enabled:
            rc = triggerBackup(key: backupMasterKey)!
        case .softDisabled:
            print("Softdisabled performBackup")
            // triggerBackup(with key: randomKey)
        case .hardDisabled:
            print("harddisabled performBackup")
        case .undecided:
            print("undecided performBackup")
        }
        
        return rc == 0
    }
    
    @discardableResult func enableBackups(masterPass: String) -> Bool {
        var rc = 0
        // FIXME: Add PW quality checks
        
        let salt = generate_random(count: 32)
        let ivData = Data(bytes: generate_random(count: 16)!, count: 16)

        // Derive the master key
        if let derivedKey = deriveKey(password: masterPass, salt: salt!, rounds: 100000) {
            
            let defaults = UserDefaults.standard
            backupMasterKey = derivedKey
            backupMasterKeySalt = salt!
            backupMasterKeyIVData = ivData
            
            // Store key data in UserDefaults
            defaults.set(backupMasterKey, forKey: "backupMasterKey")
            defaults.set(backupMasterKeySalt, forKey: "backupMasterKeySalt")
            defaults.set(backupMasterKeyIVData, forKey: "backupMasterKeyIVData")

            // FIXME: Remove, only for testing. Handle key already exists in keystore
            Backup.store.erase(account)
            
            // Add master key to Keychain store
            // FIXME: Remove Prints
            if !Backup.store.add(self) {
                 print("Error adding key, or key already exists")
            } else {
                Backup.store.save(self)
                print("Master Key added into Keystore")
            }
            
            if !saveDecision(decision: .enabled) {
                return false
            }
            
            // Initiate the first backup
            rc = triggerBackup(key: derivedKey)!
            
            return rc == 0
        }
        
        return false
    }
    
    func triggerRestore(with password: String) -> Int? {
        print("Trigger restore")
        var loadedOTPs = [OTP]()
        var loadedTokens = [Token]()
    
        // Load key from Application Data
        let defaults = UserDefaults.standard
        let testingMK = defaults.array(forKey: "backupMasterKey") as! [UInt8]
        let testingSalt = defaults.array(forKey: "backupMasterKeySalt") as! [UInt8]
        let testingIVData = defaults.data(forKey: "backupMasterKeyIVData")!
        
        if testingMK.isEmpty || testingSalt.isEmpty || testingIVData.isEmpty {
            print("Empty backup data")
            return nil
        }

        print("Derive key next")
        if let restoreDerivedKey = deriveKey(password: password, salt: testingSalt, rounds: 100000) {
            // Compare keys
            if testingMK == restoreDerivedKey {
                let keyData = Data(bytes: restoreDerivedKey, count: restoreDerivedKey.count)
                let ivData = testingIVData
                let defaults = UserDefaults.standard

                // Retrieve OTP data
                if let encryptedOTPData = defaults.object(forKey: "encryptedOTPData") as? Data {
                    // Decrypt data
                    if let decryptedOTPData = aesCrypt(data: encryptedOTPData, keyData: keyData,
                                                       ivData: ivData, operation: kCCDecrypt) {
                        print("OTPData: \(decryptedOTPData)")
                        // Decode data into Token array
                        if let decodedOTPs = NSKeyedUnarchiver.unarchiveObject(with: decryptedOTPData) as? [OTP] {
                            print("Token: \(decodedOTPs)")
                            print("Token Count: \(decodedOTPs.count)")
                            loadedOTPs = decodedOTPs
                        }
                    }
                }

                // Retrieve Token data
                if let encryptedTokenData = defaults.object(forKey: "encryptedTokenData") as? Data {
                    // Decrypt data
                    if let decryptedTokenData = aesCrypt(data: encryptedTokenData, keyData: keyData,
                                                         ivData: ivData, operation: kCCDecrypt) {
                        print("TokenData: \(decryptedTokenData)")
                        // Decode data into Token array
                        if let decodedTokens = NSKeyedUnarchiver.unarchiveObject(with: decryptedTokenData) as? [Token] {
                            print("Token: \(decodedTokens)")
                            print("Token Count: \(decodedTokens.count)")
                            print(decodedTokens.count)
                            loadedTokens = decodedTokens
                        }
                    }
                }
            } else {
                // Bad password
                return 1
            }
        }
        
        // Add tokens back into Keychain
        let ts = TokenStore()
        
        for (otp, token) in zip(loadedOTPs, loadedTokens) {
            if ts.addToken(otp, token) != nil {
                print("Added token!")
            }
        }
        
        // FIXME: Alert?
        print("Restore done, \(ts.count) tokens")
        return 0
    }
    
    func enableAutoBackups() -> Bool {
        if !saveDecision(decision: .softDisabled) {
             return false
        }
        
        print("Enable auto Backups")
        
        return true
    }
    
    func disableBackups() -> Bool {
        if !saveDecision(decision: .hardDisabled) {
             return false
        }
        
        print("disableBackups")

        return true
    }
        
    func backupExists() -> Bool {
        if UserDefaults.standard.object(forKey: "encryptedOTPData") != nil {
           return true
        }
        
        return false
    }
}
