//
//  Settings.swift
//  Alexa iOS App
//
//

import Foundation
import AVFoundation

struct Settings {
    
    struct Credentials {
        static let APPLICATION_TYPE_ID = "AlexaIOSAppAR"
        static let DSN = "12345"
        
        static let SCOPES = ["alexa:all"]
        static let SCOPE_DATA = "{\"alexa:all\":{\"productID\":\"\(APPLICATION_TYPE_ID)\"," +
        "\"productInstanceAttributes\":{\"deviceSerialNumber\":\"\(DSN)\"}}}"
    }
    
    struct Audio {

        static let TEMP_FILE_NAME = "alexa.wav"
        static let RECORDING_SETTING =
            [AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
             AVEncoderBitRateKey: 16,
             AVNumberOfChannelsKey: 1,
             AVSampleRateKey: 16000.0] as [String : Any]
        static let SILENCE_THRESHOLD = -30.0 as Float
    }
    
    struct WakeWord {
        
        static let RESOURCE = Bundle.main.path(forResource: "common", ofType: "res")
        static let MODEL = Bundle.main.path(forResource: "alexa_02092017", ofType: "umdl")
        static let SENSITIVITY = "10"
        static let AUDIO_GAIN = 1.0 as Float
        static let TEMP_FILE_NAME = "snowboy.wav"
    }
}
