//
//  AlexaViewController.swift
//  Alexa iOS App
//
//

import UIKit
import AVFoundation
import SceneKit
import ARKit

class AlexaViewController: UIViewController, AVAudioPlayerDelegate, AVAudioRecorderDelegate, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var pingBtn: UIButton!
    @IBOutlet weak var startDownchannelBtn: UIButton!
    @IBOutlet weak var pushToTalkBtn: UIButton!
    @IBOutlet weak var wakeWordBtn: UIButton!
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder!
    private var audioPlayer: AVAudioPlayer!
    private var isRecording = false
    
    private var avsClient = AlexaVoiceServiceClient()
    private var speakToken: String?
    
    private var snowboy: SnowboyWrapper!
    private var snowboyTimer: Timer!
    private var snowboyTempSoundFileURL: URL!
    private var stopCaptureTimer: Timer!
    private var isListening = false
    
    var grids = [Grid]()
    var imageNodes = [SCNNode]()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Set the view's delegate
        sceneView.delegate = self
        
        snowboy = SnowboyWrapper(resources: Settings.WakeWord.RESOURCE, modelStr: Settings.WakeWord.MODEL)
        snowboy.setSensitivity(Settings.WakeWord.SENSITIVITY)
        snowboy.setAudioGain(Settings.WakeWord.AUDIO_GAIN)
        
        avsClient.pingHandler = self.pingHandler
        avsClient.syncHandler = self.syncHandler
        avsClient.directiveHandler = self.directiveHandler
        avsClient.downchannelHandler = self.downchannelHandler
        
        // AR view
        
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions = ARSCNDebugOptions.showFeaturePoints
        let scene = SCNScene()
        sceneView.scene = scene
        //self.chompPlayer = self.loadSound(filename: "chomp")
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tappednew))
        print("Hello there")
        print(tapGesture)
        sceneView.addGestureRecognizer(tapGesture)
    }
    
    @IBAction func onClickPingBtn(_ sender: Any) {
        avsClient.ping()
    }
    
    @IBAction func onClickStartDownchannelBtn(_ sender: Any) {
        avsClient.startDownchannel()
    }
    
    @IBAction func onClickPushToTalkBtn(_ sender: Any) {
        
        if (self.isRecording) {
            audioRecorder.stop()
            
            self.isRecording = false
            pushToTalkBtn.setTitle("Push to Talk", for: .normal)
            
            do {
                try avsClient.postRecording(audioData: Data(contentsOf: audioRecorder.url))
            } catch let ex {
                print("AVS Client threw an error: \(ex.localizedDescription)")
            }
        } else {
            prepareAudioSession()
            
            audioRecorder.prepareToRecord()
            audioRecorder.record()
            
            self.isRecording = true
            pushToTalkBtn.setTitle("Recording, click to stop", for: .normal)
        }
    }
    
    @IBAction func onClickWakeWordBtn(_ sender: Any) {
        
        if (self.isListening) {
            self.isListening = false
            wakeWordBtn.setTitle("Start Wake Word", for: .normal)

            snowboyTimer.invalidate()
        } else {
            self.isListening = true
            wakeWordBtn.setTitle("Listening, click to stop", for: .normal)
            
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

    func pingHandler(isSuccess: Bool) {
        DispatchQueue.main.async { () -> Void in
            if (isSuccess) {
                self.infoLabel.text = "Ping success!"
            } else {
                self.infoLabel.text = "Ping failure!"
            }
        }
    }
    
    func syncHandler(isSuccess: Bool) {
        DispatchQueue.main.async { () -> Void in
            if (isSuccess) {
                self.infoLabel.text = "Sync success!"
            } else {
                self.infoLabel.text = "Sync failure!"
            }
        }
    }
    
    func directiveHandler(directives: [DirectiveData]) {
        // Store the token for directive "Speak"
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
                    self.infoLabel.text = "Alexa is speaking"
                }
                do {
                    self.avsClient.sendEvent(namespace: "SpeechSynthesizer", name: "SpeechStarted", token: self.speakToken!)
                    
                    try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with:[AVAudioSessionCategoryOptions.allowBluetooth, AVAudioSessionCategoryOptions.allowBluetoothA2DP])
                    try self.audioPlayer = AVAudioPlayer(data: directive.data)
                    self.audioPlayer.delegate = self
                    self.audioPlayer.prepareToPlay()
                    self.audioPlayer.play()
                } catch let ex {
                    print("Audio player has an error: \(ex.localizedDescription)")
                }
            }
        }
    }
    
    func downchannelHandler(directive: String) {
        
        do {
            let jsonData = try JSONSerialization.jsonObject(with: directive.data(using: String.Encoding.utf8)!) as! [String:Any]
            let directiveJson = jsonData["directive"] as! [String:Any]
            let header = directiveJson["header"] as! [String:String]
            if (header["name"] == "StopCapture") {
                // Handle StopCapture
            } else if (header["name"] == "SetAlert") {
                // Handle SetAlert
                let payload = directiveJson["payload"] as! [String:String]
                let scheduledTime = payload["scheduledTime"]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                dateFormatter.locale = Locale.init(identifier: "en_US")
                let futureDate = dateFormatter.date(from: scheduledTime!)
                
                let numberOfSecondsDiff = Calendar.current.dateComponents([.second], from: Date(), to: futureDate!).second ?? 0
            
                DispatchQueue.main.async { () -> Void in
                    Timer.scheduledTimer(timeInterval: TimeInterval(numberOfSecondsDiff),
                                         target: self,
                                         selector: #selector(self.timerStart),
                                         userInfo: nil,
                                         repeats: false)
                }
                
                print("Downchannel SetAlert scheduledTime: \(scheduledTime!); \(numberOfSecondsDiff) seconds from now.")
            }
        } catch let ex {
            print("Downchannel error: \(ex.localizedDescription)")
        }
    }
    
    @objc func timerStart() {
        print("Timer is triggered")
        DispatchQueue.main.async { () -> Void in
            self.infoLabel.text = "Time is up!"
        }
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
            array = Array(UnsafeBufferPointer(start: buffer?.floatChannelData![0], count: Int(20000)))
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
                self.infoLabel.text = "Alexa is listening"
            }
            
            prepareAudioSession()
            
            audioRecorder.isMeteringEnabled = true
            audioRecorder.record()
            stopCaptureTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(checkAudioMetering), userInfo: nil, repeats: true)
        } else {
            DispatchQueue.main.async { () -> Void in
                self.infoLabel.text = "Say Alexa"
            }
        }
    }
    
    @objc func checkAudioMetering() {
        
        audioRecorder.updateMeters()
        let power = audioRecorder.averagePower(forChannel: 0)
        print("Average power: \(power)")
        if (power < Settings.Audio.SILENCE_THRESHOLD) {
            
            DispatchQueue.main.async { () -> Void in
                self.infoLabel.text = "Waiting for Alexa to respond..."
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
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Audio player is finished playing")
        self.infoLabel.text = "Alexa iOS Demo"
        
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
    
    @objc
    func tappednew(_ gesture: UITapGestureRecognizer) {
        print("size")
        print(self.imageNodes.count)
        if self.imageNodes.count > 0 {
            self.imageNodes[self.imageNodes.count-1].removeFromParentNode()
        }
        //self.chompPlayer?.play()
        // Get 2D position of touch event on screen
        let touchPosition = gesture.location(in: sceneView)
        
        // Translate those 2D points to 3D points using hitTest (existing plane)
        let hitTestResults = sceneView.hitTest(touchPosition, types: .existingPlaneUsingExtent)
        
        // Get hitTest results and ensure that the hitTest corresponds to a grid that has been placed on a wall
        guard let hitTest = hitTestResults.first, let anchor = hitTest.anchor as? ARPlaneAnchor, let gridIndex = self.grids.index(where: { $0.anchor == anchor }) else {
            return
        }
        self.imageNodes.append(addPainting(hitTest, self.grids[gridIndex]))
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Enable horizontal plane detection
        configuration.planeDetection = .horizontal
        
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
}


