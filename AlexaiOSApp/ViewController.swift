//
//  ViewController.swift
//  SecondARApp
//
//  Created by Reddy, Anjali on 6/21/19.
//  Copyright © 2019 Reddy, Anjali. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation
import SceneKit.ModelIO
import Speech

class ViewController: UIViewController,AVAudioPlayerDelegate, AVAudioRecorderDelegate, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder!
    private var audioPlayer: AVAudioPlayer!
    private var soundPlayer: AVAudioPlayer!
   
    private var avsClient = AlexaVoiceServiceClient()
    private var speakToken: String?
    
    private var snowboy: SnowboyWrapper!
    private var snowboyTimer: Timer!
    private var snowboyTempSoundFileURL: URL!
    private var stopCaptureTimer: Timer!
    
    private var imageURL:UIImageView!
    private var responses = [String]()
    
    var grids = [Grid]()
    //var chompPlayer:AVAudioPlayer? = nil
    var imageNodes = [SCNNode]()
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        print("Returning URL")
        print(paths[0])
        return paths[0]
    }
    func dataFilePath(data:Data) -> Void {
        print("In audio saver")
        //let fileURL = Bundle.main.url(forResource: "saved", withExtension:"wav")
        let filename = getDocumentsDirectory().appendingPathComponent("output.wav")

        do {
            try data.write(to: filename, options: .atomic)
            convertToText(audioURL: filename.absoluteURL)
        } catch {
             print("In audio saver error")
            print(error)
        }
    }
    
    /* Load sound from file */
    func loadSound(filename: String) -> AVAudioPlayer {
        let url = Bundle.main.url(forResource: filename, withExtension: "caf")
        
        var player = AVAudioPlayer()
        do {
            try player = AVAudioPlayer(contentsOf: url!)
            player.prepareToPlay()
        } catch {
            print("Error loading \(url!): \(error.localizedDescription)")
        }
        return player
    }
 
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions = ARSCNDebugOptions.showFeaturePoints
        let scene = SCNScene()
        sceneView.scene = scene
        //self.soundPlayer = self.loadSound(filename: "chomp")
        /**
        let welcomeText = SKLabelNode(fontNamed:"Chalkduster")
        welcomeText.text = "Welcome to ARlexa!"
        welcomeText.fontSize = 65
        welcomeText.fontColor = SKColor.blue
        **/
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
       
        sceneView.addGestureRecognizer(tapGesture)
        
        // Alexa
        snowboy = SnowboyWrapper(resources: Settings.WakeWord.RESOURCE, modelStr: Settings.WakeWord.MODEL)
        snowboy.setSensitivity(Settings.WakeWord.SENSITIVITY)
        snowboy.setAudioGain(Settings.WakeWord.AUDIO_GAIN)
        
        avsClient.directiveHandler = self.directiveHandler
        
        prepareAudioSessionForWakeWord()
        
        snowboyTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(startListening), userInfo: nil, repeats: true)
    }
   

    @objc
    func tappednew(_ gesture: UITapGestureRecognizer) {
        print("size")
        print(self.imageNodes.count)
        if self.imageNodes.count > 0 {
        self.imageNodes[self.imageNodes.count-1].removeFromParentNode()
        }
        //self.soundPlayer?.play()
        // Get 2D position of touch event on screen
        let touchPosition = gesture.location(in: sceneView)
        
        // Translate those 2D points to 3D points using hitTest (existing plane)
        let hitTestResults = sceneView.hitTest(touchPosition, types: .existingPlaneUsingExtent)
        
        // Get hitTest results and ensure that the hitTest corresponds to a grid that has been placed on a wall
        guard let hitTest = hitTestResults.first, let anchor = hitTest.anchor as? ARPlaneAnchor, let gridIndex = grids.index(where: { $0.anchor == anchor }) else {
            return
        }
        self.imageNodes.append(addPainting(hitTest, grids[gridIndex]))
    }
    
    func addPainting(_ hitResult: ARHitTestResult, _ grid: Grid) -> SCNNode {
        // 1.
        let planeGeometry = SCNPlane(width: 0.1, height: 0.25)
        let material = SCNMaterial()
        guard let url = Bundle.main.url(forResource: "chair_swan", withExtension: "usdz")
            else {
                fatalError()
        }
        //let url = URL(string: "http://i.imgur.com/w5rkSIj.jpg")
        // Use  for url string let url = URL(string: "http://i.imgur.com/w5rkSIj.jpg")
        
        let data = try? Data(contentsOf: url)
        if let imageData = data {
            let image = UIImage(data: imageData)
            material.diffuse.contents = image//UIImage(string: url)
            planeGeometry.materials = [material]
        }
        
        // 2.
        let paintingNode = SCNNode(geometry: planeGeometry)
        paintingNode.transform = SCNMatrix4(hitResult.anchor!.transform)
        paintingNode.eulerAngles = SCNVector3(paintingNode.eulerAngles.x + (-Float.pi / 2), paintingNode.eulerAngles.y, paintingNode.eulerAngles.z)
        paintingNode.position = SCNVector3(hitResult.worldTransform.columns.3.x, hitResult.worldTransform.columns.3.y, hitResult.worldTransform.columns.3.z)
        
        sceneView.scene.rootNode.addChildNode(paintingNode)
        
        grid.removeFromParentNode()
        return paintingNode
    }
  
    //Add text string
    func imageWith(name: String?) -> UIImage? {
        
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let nameLabel = UILabel(frame: frame)
        nameLabel.textAlignment = .center
        nameLabel.backgroundColor = .lightGray
        nameLabel.textColor = .white
        nameLabel.font = UIFont.boldSystemFont(ofSize: 20)
        nameLabel.text = name
        UIGraphicsBeginImageContext(frame.size)
        if let currentContext = UIGraphicsGetCurrentContext() {
            nameLabel.layer.render(in: currentContext)
            let nameImage = UIGraphicsGetImageFromCurrentImageContext()
            return nameImage
        }
        return nil
    }
    
    func addItemToPosition(_ position: SCNVector3, _ touchCoordinates: CGPoint) {
        //let scene = SCNScene(named: "art.scnassets/1.jpg")
        //let image = imageWith(name: "Text")
        //fetch image from url
        
        var bottomImage:UIImage!
        /**if let url = NSURL(string: "https://i5.wal.co/asr/07d325dc-fb42-4bf6-8f4f-2216c8f212d3_1.f37c57e8e7f730446d61017c1ed7e666.jpeg-31135b62c2c5bb63013bceff884c88ac42f3ee5d-optim-180x180.jpg") {
            if let data = NSData(contentsOf: url as URL) {
                bottomImage = UIImage(data: data as Data)
            }
        }**/
        if let url = Bundle.main.url(forResource: "05", withExtension: "png") {
            
            let data = try? Data(contentsOf: url)
            if let imageData = data {
                bottomImage = UIImage(data: imageData)
            }
        }
        
        let topImage = imageWith(name: "Weather")
        
        
        let size = CGSize(width: topImage!.size.width, height: topImage!.size.height + bottomImage!.size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        
        topImage!.draw(in: CGRect(x: 0, y: 0, width: size.width, height: topImage!.size.height))
        bottomImage!.draw(in: CGRect(x: 0, y: topImage!.size.height, width: size.width, height: bottomImage!.size.height))
        
        let newImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        DispatchQueue.main.async {
            self.imageURL = UIImageView(image: newImage)
            self.imageURL.frame = CGRect(x: touchCoordinates.x, y: touchCoordinates.y, width: 100, height: 100)
            //delete previous image
            let previous = self.view.subviews
            if(previous.count > 1) {
                let lastView = previous[previous.count-1]
                lastView.removeFromSuperview()
            }
            self.view.addSubview(self.imageURL)
            
        }
        //usdz is not working properly
        //guard let url = Bundle.main.url(forResource: "duo_plus", withExtension: "usdz") else { fatalError() }
        //let mdlAsset = MDLAsset(url: url)
        //let scene = SCNScene(mdlAsset: mdlAsset)
        
        //SCN images work
        /**
         let scene = SCNScene(named: "art.scnassets/ship.scn")
         DispatchQueue.main.async {
         if let node = scene?.rootNode.childNode(withName: "ship", recursively: false) {
         node.position = position
         self.sceneView.scene.rootNode.addChildNode(node)
         }
         }**/
        /**
         if let node = scene?.rootNode.childNode(withName: "1", recursively: false) {
         node.position = position
         self.sceneView.scene.rootNode.addChildNode(node)
         print(node.position)
         }**/
        
    }
    
    func addItemToPositionCGP(_ touchCoordinates: CGPoint) {
        //let scene = SCNScene(named: "art.scnassets/1.jpg")
        //let image = imageWith(name: "Text")
        //fetch image from url
        
        var bottomImage:UIImage!
        /**if let url = NSURL(string: "https://i5.wal.co/asr/07d325dc-fb42-4bf6-8f4f-2216c8f212d3_1.f37c57e8e7f730446d61017c1ed7e666.jpeg-31135b62c2c5bb63013bceff884c88ac42f3ee5d-optim-180x180.jpg") {
         if let data = NSData(contentsOf: url as URL) {
         bottomImage = UIImage(data: data as Data)
         }
         }**/
        if let url = Bundle.main.url(forResource: "05", withExtension: "png") {
            
            let data = try? Data(contentsOf: url)
            if let imageData = data {
                bottomImage = UIImage(data: imageData)
            }
        }
        
        let topImage = imageWith(name: "Weather")
        
        
        let size = CGSize(width: topImage!.size.width, height: topImage!.size.height + bottomImage!.size.height)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        
        topImage!.draw(in: CGRect(x: 0, y: 0, width: size.width, height: topImage!.size.height))
        bottomImage!.draw(in: CGRect(x: 0, y: topImage!.size.height, width: size.width, height: bottomImage!.size.height))
        
        let newImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        DispatchQueue.main.async {
            self.imageURL = UIImageView(image: newImage)
            self.imageURL.frame = CGRect(x: touchCoordinates.x, y: touchCoordinates.y, width: 100, height: 100)
            //delete previous image
            let previous = self.view.subviews
            if(previous.count > 1) {
                let lastView = previous[previous.count-1]
                lastView.removeFromSuperview()
            }
            self.view.addSubview(self.imageURL)
            
        }
    }
    
    @objc
    func didTap(_ gesture: UITapGestureRecognizer) {
        let sceneViewTappedOn = gesture.view as! ARSCNView
        let touchCoordinates = gesture.location(in: sceneViewTappedOn)
        let hitTest = sceneViewTappedOn.hitTest(touchCoordinates, types: .existingPlaneUsingExtent)
        
        guard !hitTest.isEmpty, let hitTestResult = hitTest.first else {
            return
        }
        
        let position = SCNVector3(hitTestResult.worldTransform.columns.3.x,
                                  hitTestResult.worldTransform.columns.3.y,
                                  hitTestResult.worldTransform.columns.3.z)
        
        addItemToPosition(position, touchCoordinates)
    }
    
    /**
    if let url = Bundle.main.url(forResource: "amazon-alexa-logo-png-10", withExtension: "png") {
        let data = try? Data(contentsOf: url)
        if let imageData = data {
            bottomImage = UIImage(data: imageData)
        }
    }
    let topImage = imageWith(name: "Welcome to ARAlexa")
 **/
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Enable horizontal plane detection
        configuration.planeDetection = .vertical
        
        // show Feature Points
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        
        // Run the view's session
        sceneView.session.run(configuration)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }

    // MARK: - ARSCNViewDelegate
    

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        
       /** if let planeAnchor = anchor as? ARPlaneAnchor {
            
            let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
            plane.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: 0.75)
            
            let planeNode = SCNNode(geometry: plane)
            planeNode.position = SCNVector3Make(planeAnchor.center.x, planeAnchor.center.x, planeAnchor.center.z)
            planeNode.eulerAngles.x = -.pi / 2
            
            node.addChildNode(planeNode)
        } **/
        guard let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal else { return }
        let grid = Grid(anchor: planeAnchor)
        self.grids.append(grid)
        node.addChildNode(grid)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        /**if let planeAnchor = anchor as? ARPlaneAnchor,
            let planeNode = node.childNodes.first,
            let plane = planeNode.geometry as? SCNPlane {
            plane.width = CGFloat(planeAnchor.extent.x)
            plane.height = CGFloat(planeAnchor.extent.z)
            planeNode.position = SCNVector3Make(planeAnchor.center.x, 0, planeAnchor.center.z)
        }**/
        guard let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal else { return }
        let grid = self.grids.filter { grid in
            return grid.anchor.identifier == planeAnchor.identifier
            }.first
        
        guard let foundGrid = grid else {
            return
        }
        
        foundGrid.update(anchor: planeAnchor)
    }

    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
        
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    func prepareAudioSessionForWakeWord() {
        
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            snowboyTempSoundFileURL = directory.appendingPathComponent(Settings.WakeWord.TEMP_FILE_NAME)
            try audioRecorder = AVAudioRecorder(url: snowboyTempSoundFileURL, settings: Settings.Audio.RECORDING_SETTING as [String : AnyObject])
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
            audioRecorder.delegate = self
        } catch let ex {
            print("Audio session for wake word has an error: \(ex.localizedDescription)")
        }
    }
    
    @objc func startListening() {
        
        audioRecorder.record(forDuration: 1.0)
    }
    
    func runSnowboy() {
        
        let file = try! AVAudioFile(forReading: snowboyTempSoundFileURL)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(file.length))
        try! file.read(into: buffer!)
        //let cnt = Int(buffer?.frameLength)
        var array:Array<Float> = Array()
        if let cnt = buffer?.frameLength {
            array = Array(UnsafeBufferPointer(start: buffer?.floatChannelData![0], count: Int(cnt)))
        } else {
            array = Array(UnsafeBufferPointer(start: buffer?.floatChannelData![0], count: Int(200)))
        }
        
        var result:Int32 = 0
        if let cnt = buffer?.frameLength {
            result = snowboy.runDetection(array, length: Int32(cnt))
        } else {
            result = snowboy.runDetection(array, length: Int32(20000))
        }
        
        print("Snowboy result: \(result)")
        
        // Wake word matches
        if (result == 1) {
            DispatchQueue.main.async { () -> Void in
                print("Alexa is listening")
                self.view.subviews[self.view.subviews.count-1].removeFromSuperview()
            }
            
            prepareAudioSession()
            
            audioRecorder.isMeteringEnabled = true
            audioRecorder.record()
            stopCaptureTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(checkAudioMetering), userInfo: nil, repeats: true)
        } else {
            DispatchQueue.main.async { () -> Void in
                print("Say Alexa")
            }
        }
    }
    
    @objc func checkAudioMetering() {
        
        audioRecorder.updateMeters()
        let power = audioRecorder.averagePower(forChannel: 0)
        print("Average power: \(power)")
        if (power < Settings.Audio.SILENCE_THRESHOLD) {
            
            DispatchQueue.main.async { () -> Void in
                print("Waiting for Alexa to respond...")
            }
            
            stopCaptureTimer.invalidate()
            snowboyTimer.invalidate()
            audioRecorder.stop()
            
            do {
                try avsClient.postRecording(audioData: Data(contentsOf: audioRecorder.url))
            } catch let ex {
                print("AVS Client threw an error: \(ex.localizedDescription)")
            }
            
            prepareAudioSessionForWakeWord()
            snowboyTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(startListening), userInfo: nil, repeats: true)
        }
    }
    
    func prepareAudioSession() {
        
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = directory.appendingPathComponent(Settings.Audio.TEMP_FILE_NAME)
            try audioRecorder = AVAudioRecorder(url: fileURL, settings: Settings.Audio.RECORDING_SETTING as [String : AnyObject])
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with:[AVAudioSessionCategoryOptions.allowBluetooth, AVAudioSessionCategoryOptions.allowBluetoothA2DP])
        } catch let ex {
            print("Audio session has an error: \(ex.localizedDescription)")
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Audio player is finished playing")
        print("Alexa iOS Demo")
        
        self.avsClient.sendEvent(namespace: "SpeechSynthesizer", name: "SpeechFinished", token: self.speakToken!)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player has an error: \(String(describing: error?.localizedDescription))")
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("Audio recorder is finished recording")
        runSnowboy()
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Audio recorder has an error: \(String(describing: error?.localizedDescription))")
    }
    
    func directiveHandler(directives: [DirectiveData]) {
        // Store the token for directive "Speak"
        print("start to play Audio")
        for directive in directives {
            if (directive.contentType == "application/json") {
                do {
                    let jsonData = try JSONSerialization.jsonObject(with: directive.data) as! [String:Any]
                    let directiveJson = jsonData["directive"] as! [String:Any]
                    let header = directiveJson["header"] as! [String:String]
                    if (header["name"] == "Speak") {
                        let payload = directiveJson["payload"] as! [String:String]
                        self.speakToken = payload["token"]!
                    }
                } catch let ex {
                    print("Directive data has an error: \(ex.localizedDescription)")
                }
            }
        }
        
        // Play the audio
        for directive in directives {
            if (directive.contentType == "application/octet-stream") {
                DispatchQueue.main.async { () -> Void in
                    print("Alexa is speaking")
                }
                do {
                    self.avsClient.sendEvent(namespace: "SpeechSynthesizer", name: "SpeechStarted", token: self.speakToken!)
                    
                    try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with:[AVAudioSessionCategoryOptions.allowBluetooth, AVAudioSessionCategoryOptions.allowBluetoothA2DP])
                    try self.audioPlayer = AVAudioPlayer(data: directive.data)
                    //AudioFileWriteBytes(audioFile, false, 0, directive.data, 20)
                    self.audioPlayer.delegate = self
                    self.audioPlayer.prepareToPlay()
                    
                    self.audioPlayer.play()
                    print("print x and Y")
                    
                    addItemToPositionCGP(CGPoint.init(x: self.sceneView.frame.midX, y: self.sceneView.frame.midY))
                    //self.avsClient.sendGUIPostRequest()
                
                    /**DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { // Change `2.0` to the desired number of seconds.
                        // Code you want to be delayed
                    }**/
                    dataFilePath(data: self.audioPlayer.data!)
                    
                } catch let ex {
                    print("Audio player has an error: \(ex.localizedDescription)")
                }
            }
        }
        
    }
    
    func getLabelText(labelText:String)-> Void {
        
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        label.center = CGPoint(x: 160, y: 260)
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = labelText
        label.textColor = UIColor.black
        
        label.font = UIFont(name: "HelveticaNeue", size: CGFloat(22))
        //label.adjustsFontSizeToFitWidth = true
        self.view.addSubview(label)
        
    }
    
    func convertToText(audioURL:URL)-> Void {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            if authStatus == SFSpeechRecognizerAuthorizationStatus.authorized {
        //let audioURL = Bundle.main.url(forResource: "swvader03", withExtension: "wav")
        print("Converting to text")
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
    
        if (recognizer?.isAvailable)! {
        recognizer?.recognitionTask(with: request) { result, error in
        guard error == nil else { print("Error: \(error!)"); return }
        guard let result = result else { print("No result!"); return }
        print(result.bestTranscription.formattedString)
        self.responses.append(result.bestTranscription.formattedString)
        self.getLabelText(labelText: self.responses[self.responses.count-1])
        }
        } else {
        print("Device doesn't support speech recognition")}}
        }
    }

}
