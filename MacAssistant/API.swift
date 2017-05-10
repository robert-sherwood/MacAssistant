//
//  rpcBindings.swift
//  MacAssistant
//
//  Created by Vansh on 4/28/17.
//  Copyright © 2017 vanshgandhi. All rights reserved.
//

import Foundation
import gRPC

typealias AssistantService = Google_Assistant_Embedded_V1Alpha1_EmbeddedAssistantService
typealias AssistantCall = Google_Assistant_Embedded_V1Alpha1_EmbeddedAssistantConverseCall
typealias AudioInConfig = Google_Assistant_Embedded_V1alpha1_AudioInConfig
typealias AudioOutConfig = Google_Assistant_Embedded_V1alpha1_AudioOutConfig
typealias ConverseRequest = Google_Assistant_Embedded_V1alpha1_ConverseRequest
typealias ConverseConfig = Google_Assistant_Embedded_V1alpha1_ConverseConfig
typealias ConverseReponse = Google_Assistant_Embedded_V1alpha1_ConverseResponse
typealias ClientError = Google_Assistant_Embedded_V1Alpha1_EmbeddedAssistantClientError
typealias ConverseState = Google_Assistant_Embedded_V1alpha1_ConverseState

class API {
    
    private let ASSISTANT_API_ENDPOINT = "embeddedassistant.googleapis.com"
    private var service: AssistantService
    private var currentCall: AssistantCall?
    private var converseState: ConverseState?
    private var delegate: ConversationTextDelegate
    private var followUp = false
    
    public init(_ delegate: ConversationTextDelegate) {
        let u = Bundle.main.url(forResource: "roots", withExtension: "pem")!
        let certificate = try! String(contentsOf: u)
        service = AssistantService(address: ASSISTANT_API_ENDPOINT, certificates: certificate, host: nil)
        let token = "Bearer \(UserDefaults.standard.string(forKey: Constants.AUTH_TOKEN_KEY) ?? "")"
        service.metadata = Metadata(["authorization" : token])
        self.delegate = delegate
    }
    
    private func onReceive(response: ConverseReponse?, error: ClientError?) {
        if let response = response {
            self.debugPrint(result: response)
            self.followUp = response.result.microphoneMode == .dialogFollowOn
            self.converseState = nil
            do { self.converseState = try ConverseState(serializedData: response.result.conversationState) }
            catch { print("ConverseState parse error") }
            self.delegate.updateRequestText(response.result.spokenRequestText)
            self.delegate.updateResponseText(response.result.spokenResponseText.isEmpty ? "Speaking response..." : response.result.spokenResponseText)
            // TODO: Save file before playing it? 
            if response.audioOut.audioData.count > 0 { self.delegate.playResponse(response.audioOut.audioData) }
            if response.eventType == .endOfUtterance { self.delegate.stopListening() }
        }
        if let error = error { print("Initial receive error: \(error)") }
    }
    
    func initiateRequest() {
        var request = ConverseRequest()
        request.config = ConverseConfig()
        
        var audioInConfig = AudioInConfig()
        audioInConfig.sampleRateHertz = Int32(Constants.GOOGLE_SAMPLE_RATE)
        audioInConfig.encoding = .linear16
        request.config.audioInConfig = audioInConfig
        request.config.converseState = converseState ?? request.config.converseState        
        
        var audioOutConfig = AudioOutConfig()
        audioOutConfig.sampleRateHertz = Int32(Constants.GOOGLE_SAMPLE_RATE) // TODO: Play back the response and find the appropriate value
        audioOutConfig.encoding = .linear16
        audioOutConfig.volumePercentage = 50
        request.config.audioOutConfig = audioOutConfig
        
        do {
            currentCall = try service.converse(completion: { _ in print("Call completed") })
            try currentCall?.send(request) { print("Initial send error: \($0)") }
            try currentCall?.receive(completion: onReceive)
        } catch { print("Initial catch: \(error):\(error.localizedDescription)") }
    }
    
    func sendAudio(frame data: UnsafePointer<UnsafeMutablePointer<Int16>>, withLength length: Int) {
        var request = ConverseRequest()
        let buffer = UnsafeMutableBufferPointer(start: data[0], count: length) // convert from UnsafePointer to BufferPointer
        let data = Data(buffer: buffer) // Wrap Buffer in Data
        request.audioIn = data
        // Don't call currentCall?.receive() in here. Causes tooManyOperations error
        do { try currentCall?.send(request) { print("Frame send error: \($0.localizedDescription)") } }
        catch { print("Frame catch: \(error):\(error.localizedDescription)") }
    }
    
    func doneSpeaking() {
        do {
            try currentCall?.closeSend { print("Closed send") }
            try currentCall?.receive(completion: onReceive)
        } catch {
            print("Close catch: \(error):\(error.localizedDescription)")
        }
    }
    
    func debugPrint(result: ConverseReponse) {
        print("\n++++++++++++++++++++++++++++++")
        print("Close receive result error: \(result.error.code)")
        print("Close receive result result mic: \(result.result.microphoneMode)")
        print("Close receive result result responseText: \(result.result.spokenResponseText)")
        print("Close receive result result requestText: \(result.result.spokenRequestText)")
        print("Close receive eventType: \(result.eventType)")
        print("Close receive audio out count \(result.audioOut.audioData.count)")
        print("++++++++++++++++++++++++++++++\n")
    }
    
    
}