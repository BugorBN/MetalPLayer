//
//  ContentView.swift
//  TestMetalView
//
//  Created by Boris Bugor on 15/12/2024.
//

import SwiftUI
import AVFoundation
import UIKit
import MetalKit

class VideoPlayerView: UIView {
    private let player: AVPlayer
    
    private let videoView: MTKView = .init()
    var commandQueue: MTLCommandQueue?
    
    let playerItemVideoOutput = AVPlayerItemVideoOutput()
    
    var context: CIContext?
    var currentFrame: CIImage?
    var statusObserver: NSKeyValueObservation?
    
    var progress: Float

    lazy var displayLink: CADisplayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired(link:)))

    // MARK: - Public Properties
    var isPlaying: Bool {
        return player.rate != 0
    }
    
    func update(progress: Double) {
        self.progress = Float(progress)
    }

    init(url: URL, progress: Double) {
        self.progress = Float(progress)
        let videoItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: videoItem)
        let device = MTLCreateSystemDefaultDevice()!
        videoView.device = device
        commandQueue = device.makeCommandQueue()
        context = CIContext(mtlDevice: device)
        super.init(frame: .zero)
        commonInit()

        videoView.delegate = self
        videoView.framebufferOnly = false
        
        self.statusObserver = videoItem.observe(\.status, options: [.new, .old], changeHandler: { playerItem, change in
            if playerItem.status == .readyToPlay {
                playerItem.add(self.playerItemVideoOutput)
                self.displayLink.add(to: .main, forMode: .common)
            }
        })
    }
    
    @objc func displayLinkFired(link: CADisplayLink) {
      let currentTime = playerItemVideoOutput.itemTime(forHostTime: CACurrentMediaTime())
      if playerItemVideoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
        if let buffer = playerItemVideoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
          let frameImage = CIImage(cvImageBuffer: buffer)

          let pixelate = CIFilter(name: "CIPixellate")!
          pixelate.setValue(frameImage, forKey: kCIInputImageKey)
            pixelate.setValue(progress, forKey: kCIInputScaleKey)
          pixelate.setValue(CIVector(x: frameImage.extent.midX, y: frameImage.extent.midY), forKey: kCIInputCenterKey)
            self.currentFrame = pixelate.outputImage!.cropped(to: frameImage.extent)

          self.videoView.draw()
        }
      }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        backgroundColor = UIColor.black
        addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.frame = bounds

        // Add observer for playback completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
    
    func play() {
        player.play()
    }
    
    func pause() {
        player.pause()
    }
    
    func stop() {
        player.pause()
        player.seek(to: .zero)
    }
    
    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        videoView.frame = bounds
    }

    // MARK: - Notification Handlers
    @objc private func playerDidFinishPlaying() {
        // Optional: Perform any actions when playback completes
    }

    // MARK: - Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
        player.pause()
    }
}

extension VideoPlayerView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
      //*important* when rendering on the simulator, MTKViews render upside down. Test on an actual device.
      //create command buffer for ciContext to use to encode it's rendering instructions to our GPU
      guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
        return
      }

      //make sure we actually have a ciImage to work with
      guard let ciImage = currentFrame else {
          return
      }

      //make sure the current drawable object for this metal view is available (it's not in use by the previous draw cycle)
      guard let currentDrawable = view.currentDrawable else {
        return
      }
      let scaleX = view.drawableSize.width / ciImage.extent.width
      let scaleY = view.drawableSize.height / ciImage.extent.height

      //manually calculate an "Aspect Fit" scale and apply it to both axises
      let scaledImage = ciImage
            .transformed(by: CGAffineTransform(scaleX: max(scaleX, scaleY), y: max(scaleX, scaleY)))


      //render into the metal texture
        self.context?.render(
            scaledImage,
            to: currentDrawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: view.drawableSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

      //register where to draw the instructions in the command buffer once it executes
      commandBuffer.present(currentDrawable)
      //commit the command to the queue so it executes
      commandBuffer.commit()
    }
}

// SwiftUI Wrapper
struct VideoPlayerSwiftUIView: UIViewRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    @Binding var progress: Double
    
    func makeUIView(context: Context) -> VideoPlayerView {
        let playerView = VideoPlayerView(url: url, progress: progress)
        return playerView
    }
    
    func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        if isPlaying {
            uiView.play()
        } else {
            uiView.pause()
        }
        
        uiView.update(progress: progress)
    }
}

struct ContentView: View {
    @State private var isPlaying = false
    @State private var progress: Double = 1
    private let videoURL = Bundle.main.path(forResource: "IMG_8366", ofType: "mov").map(URL.init(fileURLWithPath:))!
    
    var body: some View {
        VideoPlayerSwiftUIView(url: videoURL, isPlaying: $isPlaying, progress: $progress)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                VStack {
                    if isPlaying {
                        Button(action: { isPlaying = false }) {
                            Image(systemName: "pause.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                        }
                    } else {
                        Button(action: { isPlaying = true }) {
                            Image(systemName: "play.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                        }
                    }
                    
                    Slider(value: $progress, in: 1...100)
                        .tint(Color.red)
                }.padding()
            }
    }
}

#Preview {
    ContentView()
}
