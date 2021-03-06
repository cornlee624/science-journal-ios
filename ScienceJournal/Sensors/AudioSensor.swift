/*
 *  Copyright 2019 Google Inc. All Rights Reserved.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import AVFoundation
import Foundation

/// A sensor that uses the audio capture to collect data from the microphone.
class AudioSensor: Sensor {

  // MARK: - Properties

  private let audioCapture: AudioCapture
  static private var sampleBufferUpdateBlocks = [String: AudioCapture.SampleBufferUpdateBlock]()
  private var startCompletion: ((Error?) -> ())?

  // MARK: - Public

  /// Designated initializer.
  ///
  /// - Parameters:
  ///   - sensorId: The sensor ID.
  ///   - name: The name of the sensor.
  ///   - textDescription: The text description of the sensor.
  ///   - iconName: The icon name for the sensor.
  ///   - animatingIconView: The animating icon view.
  ///   - unitDescription: Units the sensor's values are measured in.
  ///   - learnMore: The contents of the learn more view for a sensor.
  ///   - audioCapture: The audio capture to use for measuring sound.
  ///   - sensorTimer: The sensor timer to use for this sensor.
  init(sensorId: String,
       name: String,
       textDescription: String,
       iconName: String,
       animatingIconView: SensorAnimationView,
       unitDescription: String,
       learnMore: LearnMore,
       audioCapture: AudioCapture,
       sensorTimer: SensorTimer) {
    self.audioCapture = audioCapture
    super.init(sensorId: sensorId,
               name: name,
               textDescription: textDescription,
               iconName: iconName,
               animatingIconView: animatingIconView,
               unitDescription: unitDescription,
               learnMore: learnMore,
               sensorTimer: sensorTimer)
    isSupported = self.audioCapture.isSupported
    displaysLoadingState = true
  }

  override func start(completion: ((Error?) -> ())?) {
    state = .loading
    audioCapture.beginUsing(self) { (hasMicrophonePermission) in
      guard hasMicrophonePermission else {
        self.state = .noPermission(.userPermissionError(.microphone))
        DispatchQueue.main.async {
          completion?(SensorError.userPermissionError(.microphone))
        }
        return
      }

      self.state = .ready
      DispatchQueue.main.async {
        completion?(nil)
      }
    }
    startCompletion = completion
  }

  override func pause() {
    guard state != .paused else { return }
    state = .paused
    audioCapture.endUsing(self)
  }

  override func prepareForBackground() {
    pause()
  }

  override func prepareForForeground()  {
    if listenerBlocks.count > 0 {
      start(completion: startCompletion)
    }
  }

  override func callListenerBlocksWithData(atMilliseconds milliseconds: Int64) {
    guard let audioSampleBuffer = audioCapture.lastAudioSampleBuffer else { return }
    callListenerBlocksWithAudioSampleBuffer(audioSampleBuffer, atMilliseconds: milliseconds)
  }

  /// Calls listener blocks with audio data. Must be overriden by subclasses to call with the data
  /// value it is associated with.
  ///
  /// - Parameters:
  ///   - audioSampleBuffer: The sample buffer accessed from the audio capture.
  ///   - milliseconds: The date in milliseconds when the timer fired.
  func callListenerBlocksWithAudioSampleBuffer(_ audioSampleBuffer: UnsafeBufferPointer<Int16>,
                                               atMilliseconds milliseconds: Int64) {
    fatalError("`callListenerBlocksWithAudioSampleBuffer` must be overridden by the subclass.")
  }

  /// Sets a block to be called with the last audio sample buffer, each time it is updated. Only one
  /// block is allowed per sensor. Setting a new block will remove any existing update blocks.
  ///
  /// - Parameter: sampleBufferUpdateBlock: A block called with the last audio sample buffer, each
  ///                                       time it is updated.
  func setSampleBufferUpdateBlock(_
      sampleBufferUpdateBlock: @escaping AudioCapture.SampleBufferUpdateBlock) {
    // Set the update block in the dictionary of sample buffer update blocks.
    AudioSensor.sampleBufferUpdateBlocks[sensorId] = sampleBufferUpdateBlock

    guard AudioSensor.sampleBufferUpdateBlocks.count == 1 else { return }
    // If this is the first sample buffer update block, set an update block in the audio capture to
    // start receiving updates.
    audioCapture.setSampleBufferUpdateBlock { (sampleBuffer) in
      // Call each of the sample buffer update blocks whenever an update is received from the audio
      // capture.
      for (_, updateBlock) in AudioSensor.sampleBufferUpdateBlocks {
        updateBlock(sampleBuffer)
      }
    }
  }

  /// Removes the sensor's block to be called with the last audio sample buffer, each time it is
  /// updated.
  func removeSampleBufferUpdateBlock() {
    // Remove the update block from the dictionary of sample buffer update blocks.
    AudioSensor.sampleBufferUpdateBlocks[sensorId] = nil

    guard AudioSensor.sampleBufferUpdateBlocks.count == 0 else { return }
    // If there are no more sample buffer update blocks, remove the update block from the audio
    // capture to stop receiving updates.
    audioCapture.setSampleBufferUpdateBlock(nil)
  }

}
