import MetalKit
import SwiftUI
import QuartzCore

enum OrbState: String { case idle, listening, thinking, speaking, confirm, error }

private struct OrbUniforms {
    var time: Float = 0, energy: Float = 0, speed: Float = 1, swirl: Float = 0
    var levels = SIMD4<Float>(repeating: 0)
    var color = SIMD4<Float>(repeating: 1)
    var size = SIMD2<Float>(1, 1)
}

/// Scene → half-res gaussian bloom (N passes) → composite. Degrades itself if the GPU falls behind.
final class OrbRenderer: NSObject, MTKViewDelegate {
    var state: OrbState = .idle { didSet { view?.preferredFramesPerSecond = state == .idle ? 30 : fps } }
    var baseColor = SIMD3<Float>(0.25, 0.85, 1)
    var micLevels: Levels?
    var ttsLevels: Levels?

    private weak var view: MTKView?
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let scenePSO, blurPSO, compositePSO: MTLRenderPipelineState
    private var sceneTex, blurA, blurB: MTLTexture?
    private var u = OrbUniforms()
    private let start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()

    // Quality: bloom passes 3 → 2 → 1 → 0, then 30 fps. Knob: `budget` (ms of GPU time per frame).
    private var bloomPasses = 3
    private var fps = 60
    private let budget = 8.0
    private var slowFrames = 0
    private let gpuLock = NSLock()
    private var gpuMs = 0.0

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let lib = device.makeDefaultLibrary() else { return nil }
        self.device = device; self.queue = queue
        func pso(_ fragment: String, format: MTLPixelFormat, blend: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "fullscreen")
            d.fragmentFunction = lib.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let s = pso("orbScene", format: .rgba16Float, blend: false),
              let b = pso("blur", format: .rgba16Float, blend: false),
              let c = pso("composite", format: view.colorPixelFormat, blend: false) else { return nil }
        scenePSO = s; blurPSO = b; compositePSO = c
        super.init()
        self.view = view
        view.device = device
        view.preferredFramesPerSecond = 30
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { sceneTex = nil }

    private func makeTextures(_ size: CGSize) {
        func tex(_ w: Int, _ h: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: max(w, 1), height: max(h, 1), mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        let w = Int(size.width), h = Int(size.height)
        sceneTex = tex(w, h); blurA = tex(w / 2, h / 2); blurB = tex(w / 2, h / 2)
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - last, 0.1)); last = now
        animate(dt: dt, time: Float(now - start), size: view.drawableSize)
        adaptQuality()

        if sceneTex == nil { makeTextures(view.drawableSize) }
        guard let scene = sceneTex, let a = blurA, let b = blurB,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer() else { return }

        func target(_ t: MTLTexture) -> MTLRenderPassDescriptor {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = t; d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0); d.colorAttachments[0].storeAction = .store
            return d
        }
        func run(_ pd: MTLRenderPassDescriptor, _ pso: MTLRenderPipelineState, _ setup: (MTLRenderCommandEncoder) -> Void) {
            guard let e = cmd.makeRenderCommandEncoder(descriptor: pd) else { return }
            e.setRenderPipelineState(pso); setup(e)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        }

        run(target(scene), scenePSO) { $0.setFragmentBytes(&u, length: MemoryLayout<OrbUniforms>.stride, index: 0) }
        var src = scene
        for _ in 0..<bloomPasses {
            var h = SIMD2<Float>(1, 0), v = SIMD2<Float>(0, 1)
            run(target(a), blurPSO) { $0.setFragmentTexture(src, index: 0); $0.setFragmentBytes(&h, length: 8, index: 0) }
            run(target(b), blurPSO) { $0.setFragmentTexture(a, index: 0); $0.setFragmentBytes(&v, length: 8, index: 0) }
            src = b
        }
        var strength: Float = bloomPasses == 0 ? 0 : 0.9 + 0.8 * u.energy
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        run(pass, compositePSO) {
            $0.setFragmentTexture(scene, index: 0); $0.setFragmentTexture(bloomPasses == 0 ? scene : b, index: 1)
            $0.setFragmentBytes(&strength, length: 4, index: 0)
        }
        cmd.addCompletedHandler { [weak self] c in
            guard let self else { return }
            self.gpuLock.withLock { self.gpuMs = (c.gpuEndTime - c.gpuStartTime) * 1000 }
        }
        cmd.present(drawable)
        cmd.commit()
    }

    /// State targets, eased every frame so transitions animate.
    private func animate(dt: Float, time: Float, size: CGSize) {
        let mic = micLevels?.value ?? .zero, tts = ttsLevels?.value ?? .zero
        var energy: Float = 0.12, speed: Float = 0.6, swirl: Float = 0, levels = SIMD4<Float>(repeating: 0)
        var color = baseColor
        switch state {
        case .idle: break
        case .listening: energy = 0.35 + 0.65 * mic.x; speed = 1.0; levels = mic
        case .thinking: energy = 0.45 + 0.1 * sin(time * 3); speed = 1.8; swirl = 1
                        color = mix(baseColor, SIMD3(0.55, 0.45, 1), t: 0.35)
        case .speaking: energy = 0.3 + 0.7 * tts.x; speed = 1.2; levels = tts
        case .confirm: energy = 0.4 + 0.15 * sin(time * 4); speed = 0.9; color = SIMD3(1, 0.69, 0.13)
        case .error: energy = 0.25; speed = 0.5; color = SIMD3(1, 0.23, 0.23)
        }
        let k = 1 - exp(-dt * 8)          // ~120 ms ease
        let kAudio = 1 - exp(-dt * 25)    // audio follows faster
        u.energy += (energy - u.energy) * k
        u.speed += (speed - u.speed) * k
        u.swirl += (swirl - u.swirl) * k
        u.levels += (levels - u.levels) * kAudio
        let c = SIMD3(u.color.x, u.color.y, u.color.z)
        let nc = c + (color - c) * k
        u.color = SIMD4(nc, 1)
        u.time = time
        u.size = SIMD2(Float(size.width), Float(size.height))
    }

    private func adaptQuality() {
        let ms = gpuLock.withLock { gpuMs }
        slowFrames = ms > budget ? slowFrames + 1 : max(0, slowFrames - 1)
        guard slowFrames > 120 else { return }   // ~2 s of slow frames
        slowFrames = 0
        if bloomPasses > 0 { bloomPasses -= 1 } else if fps == 60 { fps = 30 }
        view?.preferredFramesPerSecond = fps
        Log.write("orb: qualità ridotta → bloom \(bloomPasses), \(fps) fps (GPU \(String(format: "%.1f", ms)) ms)")
    }

    static func rgb(hex: String) -> SIMD3<Float> {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x3FD8FF
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }
}

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> { a + (b - a) * t }

/// Transparent MTKView that lets the panel be dragged from the orb.
final class OrbMTKView: MTKView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct OrbView: NSViewRepresentable {
    let state: OrbState
    let colorHex: String
    let mic: Levels
    let tts: Levels

    final class Coordinator { var renderer: OrbRenderer? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let v = OrbMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm
        v.framebufferOnly = true
        v.layer?.isOpaque = false
        v.clearColor = MTLClearColorMake(0, 0, 0, 0)
        let r = OrbRenderer(view: v)
        r?.micLevels = mic; r?.ttsLevels = tts
        context.coordinator.renderer = r
        v.delegate = r
        return v
    }

    func updateNSView(_ v: MTKView, context: Context) {
        guard let r = context.coordinator.renderer else { return }
        if r.state != state { r.state = state }
        r.baseColor = OrbRenderer.rgb(hex: colorHex)
    }
}
