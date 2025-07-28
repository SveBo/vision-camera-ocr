import Vision
import AVFoundation
import MLKitVision
import MLKitTextRecognition
import CoreImage
import UIKit
// use_framework! import
#if canImport(VisionCamera)
import VisionCamera
#endif
 
@objc(OCRFrameProcessorPlugin)
public class OCRFrameProcessorPlugin: FrameProcessorPlugin {
 
    private static let textRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions.init())
 
    private static func getBlockArray(_ blocks: [TextBlock]) -> [[String: Any]] {
 
        var blockArray: [[String: Any]] = []
 
        for block in blocks {
            blockArray.append([
                "text": block.text,
                "recognizedLanguages": getRecognizedLanguages(block.recognizedLanguages),
                "cornerPoints": getCornerPoints(block.cornerPoints),
                "frame": getFrame(block.frame),
                "boundingBox": getBoundingBox(block.frame) as Any,
                "lines": getLineArray(block.lines),
            ])
        }
 
        return blockArray
    }
 
    private static func getLineArray(_ lines: [TextLine]) -> [[String: Any]] {
 
        var lineArray: [[String: Any]] = []
 
        for line in lines {
            lineArray.append([
                "text": line.text,
                "recognizedLanguages": getRecognizedLanguages(line.recognizedLanguages),
                "cornerPoints": getCornerPoints(line.cornerPoints),
                "frame": getFrame(line.frame),
                "boundingBox": getBoundingBox(line.frame) as Any,
                "elements": getElementArray(line.elements),
            ])
        }
 
        return lineArray
    }
 
    private static func getElementArray(_ elements: [TextElement]) -> [[String: Any]] {
 
        var elementArray: [[String: Any]] = []
 
        for element in elements {
            elementArray.append([
                "text": element.text,
                "cornerPoints": getCornerPoints(element.cornerPoints),
                "frame": getFrame(element.frame),
                "boundingBox": getBoundingBox(element.frame) as Any,
                "symbols": []
            ])
        }
 
        return elementArray
    }
 
    private static func getRecognizedLanguages(_ languages: [TextRecognizedLanguage]) -> [String] {
 
        var languageArray: [String] = []
 
        for language in languages {
            guard let code = language.languageCode else {
                print("No language code exists")
                break;
            }
            languageArray.append(code)
        }
 
        return languageArray
    }
 
    private static func getCornerPoints(_ cornerPoints: [NSValue]) -> [[String: CGFloat]] {
 
        var cornerPointArray: [[String: CGFloat]] = []
 
        for cornerPoint in cornerPoints {
            guard let point = cornerPoint as? CGPoint else {
                print("Failed to convert corner point to CGPoint")
                break;
            }
            cornerPointArray.append([ "x": point.x, "y": point.y])
        }
 
        return cornerPointArray
    }
 
    private static func getFrame(_ frameRect: CGRect) -> [String: CGFloat] {
 
        let offsetX = (frameRect.midX - ceil(frameRect.width)) / 2.0
        let offsetY = (frameRect.midY - ceil(frameRect.height)) / 2.0
 
        let x = frameRect.maxX + offsetX
        let y = frameRect.minY + offsetY
 
        return [
          "x": frameRect.midX + (frameRect.midX - x),
          "y": frameRect.midY + (y - frameRect.midY),
          "width": frameRect.width,
          "height": frameRect.height,
          "boundingCenterX": frameRect.midX,
          "boundingCenterY": frameRect.midY
        ]
    }
 
    private static func getBoundingBox(_ rect: CGRect?) -> [String: CGFloat]? {
         return rect.map {[
             "left": $0.minX,
             "top": $0.maxY,
             "right": $0.maxX,
             "bottom": $0.minY
         ]}
    }
 
    private func rotationAngle(for orientation: String) -> Int {
        switch orientation.lowercased() {
        case "portrait":
            return 0
        case "landscape-left":
            return 90
        case "portrait-upside-down":
            return 180
        case "landscape-right":
            return 270
        default:
            return 0
        }
    }
 
   private  func angleFor(imageOrientation: UIImage.Orientation) -> Int {
        switch imageOrientation {
            case .up, .upMirrored:
                return 0
            case .right, .rightMirrored:
                return 90
            case .down, .downMirrored:
                return 180
            case .left, .leftMirrored:
                return 270
            @unknown default:
                return 0 // fallback
        }
    }
 
 
    public override func callback(_ frame: Frame, withArguments arguments: [AnyHashable: Any]?) -> Any? {
 
        guard let imageBuffer = CMSampleBufferGetImageBuffer(frame.buffer) else {
          print("Failed to get image buffer from sample buffer.")
          return nil
        }
 
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
 
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create bitmap from image.")
            return nil
        }
 
        let image = UIImage(cgImage: cgImage)
 
        let visionImage = VisionImage(image: image)
 
        // Set the orientation of visionImage to the opposite of the frame's orientation
        // Opposite compare to the `up` orientation
        // https://github.com/ismaelsousa/vision-camera-ocr/pull/16/files
        // https://github.com/mrousavy/react-native-vision-camera/pull/3077
 
        switch frame.orientation {
            case .left:
                visionImage.orientation = .right
            case .right:
                visionImage.orientation = .left
 
            default: visionImage.orientation = frame.orientation
            }
 
        if let args = arguments,
           let outputOrientation = args["outputOrientation"] as? String {
            // if we get the outputOrientation from js, use it
            let frameAngle = angleFor(imageOrientation: frame.orientation)
            let targetAngle = rotationAngle(for: outputOrientation)
            let newOrientation = ((targetAngle - frameAngle) % 360 + 360) % 360
            switch newOrientation {
                case 0:
                    visionImage.orientation = .up
                case 90:
                    visionImage.orientation = .right
                case 180:
                    visionImage.orientation = .down
 
            default: visionImage.orientation = .left
                }
        }
 
        var result: Text
 
        do {
          result = try OCRFrameProcessorPlugin.textRecognizer.results(in: visionImage)
        } catch let error {
          print("Failed to recognize text with error: \(error.localizedDescription).")
          return nil
        }
 
        return [
            "result": [
                "text": result.text,
                "blocks": OCRFrameProcessorPlugin.getBlockArray(result.blocks),
            ]
        ]
    }
}