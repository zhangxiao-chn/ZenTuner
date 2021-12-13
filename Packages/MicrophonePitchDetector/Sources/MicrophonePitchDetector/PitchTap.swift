// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import CMicrophonePitchDetector
import Accelerate

/// Tap to do pitch tracking on any node.
final class PitchTap {
    // MARK: - Properties

    private var bufferSize: UInt32 { 4_096 }
    private let input: Node
    private var tracker: PitchTrackerRef?
    private let handler: (Float) -> Void

    // MARK: - Starting

    /// Enable the tap on input
    func start() {
        input.avAudioNode.removeTap(onBus: 0)
        input.avAudioNode
            .installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
                self?.analyzePitch(buffer: buffer)
            }
    }

    // MARK: - Lifecycle

    /// Initialize the pitch tap
    ///
    /// - Parameters:
    ///   - input: Node to analyze
    ///   - handler: Callback to call when a pitch is detected
    init(_ input: Node, handler: @escaping (Float) -> Void) {
        self.input = input
        self.handler = handler
    }

    deinit {
        if let tracker = self.tracker {
            ztPitchTrackerDestroy(tracker)
        }
    }

    // MARK: - Private
    var rr = [Double]()

    private func analyzePitch(buffer: AVAudioPCMBuffer) {
        buffer.frameLength = bufferSize
        guard let floatData = buffer.floatChannelData else { return }

        let tracker: PitchTrackerRef
        if let existingTracker = self.tracker {
            tracker = existingTracker
        } else {
            tracker = ztPitchTrackerCreate(UInt32(buffer.format.sampleRate), Int32(bufferSize), 20)
            self.tracker = tracker
        }

        ztPitchTrackerAnalyze(tracker, floatData[0], bufferSize)
        //声音振幅，表示声音的大小,0.1以下可以认为是背景噪音
        var amp: Float = 0
        //声音的频率，表示声音的音调
        var pitch: Float = 0
        ztPitchTrackerGetResults(tracker, &amp, &pitch)

        //过滤掉音量比较小的声音
        if amp > 0.10 {
            rr.append(Double(pitch))
            if (rr.count > 5) {
                rr.remove(at: 0)
                var mn = 0.0
                var sddev = 0.0
                //计算5个临近的声音样本的频率的平均值和标准差
                //只有标准差小于一定的误差，才认为这一系列声音是有效的
                //从而排除那种短暂的噪音
                vDSP_normalizeD(rr, 1, nil, 1, &mn, &sddev, vDSP_Length(rr.count))
                sddev *= sqrt(Double(rr.count)/Double(rr.count - 1))
                print("平均值:\(mn) 标准差:\(sddev)")
                if (sddev < 20.0) {
                    self.handler(Float(mn))
                }
            }
        }
    }
}
