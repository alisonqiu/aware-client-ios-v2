//
//  AppDelegate.swift
//  aware-client-ios-v2
//
//  Created by Yuuki Nishiyama on 2019/02/27.
//  Copyright © 2019 Yuuki Nishiyama. All rights reserved.
//

import UIKit
import CoreData
import AWAREFramework
import Speech

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    private let AUDIO_LEN_IN_SECOND = 6
    
    private let SAMPLE_RATE = 16000

    private lazy var module: InferenceModule = {
        if let filePath = Bundle.main.path(forResource:
            "wav2vec2", ofType: "ptl"),
            let module = InferenceModule(fileAtPath: filePath) {
            return module
        } else {
            fatalError("Can't find the model file!")
        }
    }()
    private let lockQueue = DispatchQueue(label: "name.lock.queue");

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
        let core    = AWARECore.shared()
        let manager = AWARESensorManager.shared()
        let study   = AWAREStudy.shared()

        manager.addSensors(with: study)
        if manager.getAllSensors().count > 0 {
            core.setAnchor()
            if let fitbit = manager.getSensor(SENSOR_PLUGIN_FITBIT) as? Fitbit {
                fitbit.viewController = window?.rootViewController
            }
            if let ambientNoise = manager.getSensor(SENSOR_AMBIENT_NOISE) as? AmbientNoise {
                ambientNoise.delegate = self
            }
            core.activate()
            manager.add(AWAREEventLogger.shared())
            manager.add(AWAREStatusMonitor.shared())
            
            core.requestPermissionForPushNotification { (status, error) in
                
            }
        }

        IOSESM.setESMAppearedState(false)

        let key = "aware-client-v2.setting.key.is-not-first-time"
        if(!UserDefaults.standard.bool(forKey:key)){
            study.setCleanOldDataType(cleanOldDataTypeNever)
            UserDefaults.standard.set(true, forKey: key)
        }

        if UserDefaults.standard.bool(forKey: AdvancedSettingsIdentifiers.statusMonitor.rawValue){
            AWAREStatusMonitor.shared().activate(withCheckInterval: 60)
        }
        
        UNUserNotificationCenter.current().delegate = self
        
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"application:didFinishLaunchingWithOptions:launchOptions:"]);
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"applicationWillResignActive:"]);
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        IOSESM.setESMAppearedState(false)
        UIApplication.shared.applicationIconBadgeNumber = 0
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"applicationDidEnterBackground:"]);
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"applicationWillEnterForeground:"]);
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"applicationDidBecomeActive:"]);
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
        AWAREUtils.sendLocalPushNotification(withTitle: NSLocalizedString("terminate_title" , comment: ""),
                                             body: NSLocalizedString("terminate_msg" , comment: ""),
                                             timeInterval: 1,
                                             repeats: false)
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"applicationWillTerminate:"]);
        self.saveContext()
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        
        AWAREEventLogger.shared().logEvent(["class":"AppDelegate",
                                            "event":"application:open:options"]);
        
        if url.scheme == "fitbit" {
            let manager = AWARESensorManager.shared()
            if let fitbit = manager.getSensor(SENSOR_PLUGIN_FITBIT) as? Fitbit {
                fitbit.handle(url, sourceApplication: nil, annotation: options)
            }
        } else if url.scheme == "aware-ssl" || url.scheme == "aware" {
            var studyURL = url.absoluteString
            if studyURL.prefix(9) == "aware-ssl" {
                let range = studyURL.range(of: "aware-ssl")
                if let range = range {
                    studyURL = studyURL.replacingCharacters(in: range, with: "https")
                }
            } else if studyURL.prefix(5) == "aware" {
                let range = studyURL.range(of: "aware")
                if let range = range {
                    studyURL = studyURL.replacingCharacters(in: range, with: "http")
                }
            }
            let study = AWAREStudy.shared()
             study.join(withURL: studyURL) { (settings, status, error) in
                if status == AwareStudyStateUpdate || status == AwareStudyStateNew {
                    let core = AWARECore.shared()
                    core.requestPermissionForPushNotification { (notifState, error) in
                        core.requestPermissionForBackgroundSensing{ (locStatus) in
                            core.activate()
                            let manager = AWARESensorManager.shared()
                            manager.stopAndRemoveAllSensors()
                            manager.addSensors(with: study)
                            if let fitbit = manager.getSensor(SENSOR_PLUGIN_FITBIT) as? Fitbit {
                                fitbit.viewController = self.window?.rootViewController
                            }
                            if let ambientNoise = manager.getSensor(SENSOR_AMBIENT_NOISE) as? AmbientNoise {
                                ambientNoise.delegate = self
                            }
                            manager.add(AWAREEventLogger.shared())
                            manager.add(AWAREStatusMonitor.shared())
                            manager.startAllSensors()
                            manager.createDBTablesOnAwareServer()
                        }
                    }
                }else {
                    // print("Error: ")
                }
            }
        }
        
        return true
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "aware_client_ios_v2")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving support

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

}

extension AppDelegate : UNUserNotificationCenterDelegate,AVAudioRecorderDelegate,AWAREAmbientNoiseDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                openSettingsFor notification: UNNotification?) {
        
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if let userInfo = notification.request.content.userInfo as? [String:Any]{
            print(userInfo)
        }
        completionHandler([.alert])
    }
    

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let userInfo = userInfo as? [String:Any]{
            // SilentPushManager().executeOperations(userInfo)
            PushNotificationResponder().response(withPayload: userInfo)
        }
        
        if AWAREStudy.shared().isDebug(){ print("didReceiveRemoteNotification:start") }
        
        let dispatchTime = DispatchTime.now() + 20
        DispatchQueue.main.asyncAfter( deadline: dispatchTime ) {
            
            if AWAREStudy.shared().isDebug(){ print("didReceiveRemoteNotification:end") }
            
            completionHandler(.noData)
        }
    }

    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let push = PushNotification(awareStudy: AWAREStudy.shared())
        push.saveDeviceToken(with: deviceToken)
        push.startSyncDB()
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        
    }
    
    func audioDidSave(_ audio_url: URL!, completion callback: ((String?) -> Void)!) {
                let file = try! AVAudioFile(forReading: audio_url)
        
                if (file.length == 0){
                    return;
                }
                //file.fileFormat: <AVAudioFormat 0x600001306800:  1 ch,  16000 Hz, Float32>
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate, channels: 1, interleaved: false)
        
        
                let buf = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(file.length))
        
                try! file.read(into: buf!)
        
                var floatArray = Array(UnsafeBufferPointer(start: buf?.floatChannelData![0], count:Int(buf!.frameLength)))
                var z = floatArray.map {$0}
                z.append(0)
        
                var result = "default";
                //DispatchQueue.global().async {
                    self.lockQueue.async {
                        z.withUnsafeMutableBytes {
                            
                            //getting result, baseAddress: 0x00007fb87d900020 bufLength:96000
                            result = self.module.recognize($0.baseAddress!, bufLength: Int32(self.AUDIO_LEN_IN_SECOND * self.SAMPLE_RATE))!
                            print("-------result: \(result)")
                            
                            DispatchQueue.main.async {
                                //self.tvResult.text = result
                                //self.btnStart.setTitle("Start", for: .normal)
                                callback(result);
                                
                            }
                        }
                   // }
                }
        
    }
}
