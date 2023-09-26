//
//  AudioModel.swift
//  AudioLabSwift
//
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.
//

import Foundation
import Accelerate

class AudioModel {
    
    // MARK: Properties
    private var BUFFER_SIZE:Int
	private var MX_ARR_SIZE:Int
	private var BATCH_SIZE:Int
    // thse properties are for interfaceing with the API
    // the user can access these arrays at any time and plot them if they like
    var timeData:[Float]
    var fftData:[Float]
	var mxData:[Float]
    
    // MARK: Public Methods
    init(buffer_size:Int) {
        BUFFER_SIZE = buffer_size
		MX_ARR_SIZE = 20
        // Pseudo-round up the batch sizes to ensure a 21st sample point is not made
        BATCH_SIZE = ((BUFFER_SIZE/2)/MX_ARR_SIZE) + 1
        // anything not lazily instatntiated should be allocated here
        timeData = Array.init(repeating: 0.0, count: BUFFER_SIZE)
        fftData = Array.init(repeating: 0.0, count: BUFFER_SIZE/2)
		mxData = Array.init(repeating: 0.0, count: MX_ARR_SIZE)
    }
    
    // public function for starting processing of microphone data
    func startMicrophoneProcessing(withFps:Double){
        // setup the microphone to copy to circualr buffer
        if let manager = self.audioManager{
            manager.inputBlock = self.handleMicrophone
            
            // repeat this fps times per second using the timer class
            //   every time this is called, we update the arrays "timeData" and "fftData"
            Timer.scheduledTimer(withTimeInterval: 1.0/withFps, repeats: true) { _ in
                self.runEveryInterval()
            }
            
        }
    }
    
    func playAudioFile(){
        // set the output block to read from and play the audio file
        if let manager = self.audioManager,
           let fileReader = self.fileReader{
            manager.outputBlock = self.handleSpeakerQueryWithAudioFile
            fileReader.play() // tell file Reader to start filling its buffer
            Timer.scheduledTimer(withTimeInterval: 1.0/20, repeats: true) { _ in
                self.runEveryInterval()
            }
        }
    }
    
    // You must call this when you want the audio to start being handled by our model
    func play(){
        if let manager = self.audioManager{
            manager.play()
        }
    }
    
    // Will pause the existing manager
    func pause(){
        if let manager = self.audioManager{
            manager.pause()
        }
    }
    
    //==========================================
    // MARK: Private Properties
    private lazy var audioManager:Novocaine? = {
        return Novocaine.audioManager()
    }()
    
    private lazy var fftHelper:FFTHelper? = {
        return FFTHelper.init(fftSize: Int32(BUFFER_SIZE))
    }()
    
    
    private lazy var inputBuffer:CircularBuffer? = {
        return CircularBuffer.init(numChannels: Int64(self.audioManager!.numInputChannels),
                                   andBufferSize: Int64(BUFFER_SIZE))
    }()
    
    private var volume:Float = 1.0 // internal storage for volume
    
    //==========================================
    // MARK: Private Methods
    // NONE for this model
    
    
    private lazy var fileReader:AudioFileReader? = {
        // find song in the main Bundle
        if let url = Bundle.main.url(forResource: "satisfaction", withExtension: "mp3"){
            // if we could find the url for the song in main bundle, setup file reader
            // the file reader is doing a lot here becasue its a decoder
            // so when it decodes the compressed mp3, it needs to know how many samples
            // the speaker is expecting and how many output channels the speaker has (mono, left/right, surround, etc.)
            var tmpFileReader:AudioFileReader? = AudioFileReader.init(audioFileURL: url,
                                                   samplingRate: Float(audioManager!.samplingRate),
                                                   numChannels: audioManager!.numOutputChannels)
            
            tmpFileReader!.currentTime = 0.0 // start from time zero!
            print("Audio file succesfully loaded for \(url)")
            return tmpFileReader
        }else{
            print("Could not initialize audio input file")
            return nil
        }
    }()
    
    
    //==========================================
    // MARK: Model Callback Methods
    private func runEveryInterval(){
        if inputBuffer != nil {
            // copy time data to swift array
            self.inputBuffer!.fetchFreshData(&timeData,
                                             withNumSamples: Int64(BUFFER_SIZE))
            
            // now take FFT
            fftHelper!.performForwardFFT(withData: &timeData,
                                         andCopydBMagnitudeToBuffer: &fftData)
            
            // at this point, we have saved the data to the arrays:
            //   timeData: the raw audio samples
            //   fftData:  the FFT of those same samples
            // the user can now use these variables however they like

            // Compute maxima of ArraySlice (with a size of BATCH_SIZE) through max(by: {$0 < $1}) w/ unwrapping optional Float to Float.leastNormalMagnitude
            for slice in stride(from: 0, to: fftData.count-1, by: BATCH_SIZE) {
                mxData[slice/BATCH_SIZE] = fftData[slice...min(slice+BATCH_SIZE-1, fftData.count - 1)].max(by: <) ?? Float.leastNormalMagnitude
			}
            
        }
    }
    
    //==========================================
    // MARK: Audiocard Callbacks
    // in obj-C it was (^InputBlock)(float *data, UInt32 numFrames, UInt32 numChannels)
    // and in swift this translates to:
    private func handleMicrophone (data:Optional<UnsafeMutablePointer<Float>>, numFrames:UInt32, numChannels: UInt32) {
        // copy samples from the microphone into circular buffer
        self.inputBuffer?.addNewFloatData(data, withNumSamples: Int64(numFrames))
    }
    
    
    private func handleSpeakerQueryWithAudioFile(data:Optional<UnsafeMutablePointer<Float>>,
                                                 numFrames:UInt32,
                                                 numChannels: UInt32){
        
        
        if let file = self.fileReader{
            
            // read from file, loading into data (a float pointer)
            if let arrayData = data{
                // get samples from audio file, pass array by reference
                file.retrieveFreshAudio(arrayData,
                                        numFrames: numFrames,
                                        numChannels: numChannels)
                // that is it! The file was just loaded into the data array
                
                // adjust volume of audio file output
                vDSP_vsmul(arrayData, 1, &(self.volume), arrayData, 1, vDSP_Length(numFrames*numChannels))
                
                // Copy in the newly loaded audio data into the input buffer for the graphs, to run in sync
                self.inputBuffer?.addNewFloatData(arrayData, withNumSamples: Int64(numFrames))

                
            }
            
            
            
        }
    }
    
}
