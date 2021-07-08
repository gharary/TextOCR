//
//  ViewController.swift
//  TextOCR
//
//  Created by Mohammad Gharari on 7/3/20.
//  Copyright © 2020 Mohammad Gharari. All rights reserved.
//

import UIKit

import Vision
import CoreML



public var observationStringLookup : [VNTextObservation : String] = [:]
class ViewController: UIViewController {

    
    @IBOutlet weak var imageView: UIImageView!

    var model: VNCoreMLModel!
    var textMetadata = [Int: [Int: String]]()
    var currentImage : UIImage!
    
    
    
    
    @IBAction func imageBtn(_ sender: UIButton) {
        
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentPhotoPicker(sourceType: .photoLibrary)
            return
        }
        let photoSourcePicker = UIAlertController()
        let takePhoto = UIAlertAction(title: "Camera", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .camera)
        }
        let choosePhoto = UIAlertAction(title: "Photos Library", style: .default) { [unowned self] _ in
            self.presentPhotoPicker(sourceType: .photoLibrary)
        }
        photoSourcePicker.addAction(takePhoto)
        photoSourcePicker.addAction(choosePhoto)
        photoSourcePicker.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(photoSourcePicker, animated: true)

    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
     
        
    }

    
    
    
    

}
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        
        guard let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            fatalError("Error!")
        }
        observationStringLookup.removeAll()
        textMetadata.removeAll()
        imageView.image = uiImage
        createVisionRequest(image: uiImage)
    }
    
    private func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
    }
}

extension ViewController
{
    func createVisionRequest(image: UIImage)
    {
        
        currentImage = image
        guard let cgImage = image.cgImage else {
            return
        }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImageOrientation, options: [:])
        let vnRequests = [vnTextDetectionRequest]
        
        DispatchQueue.global(qos: .background).async {
            do{
                try requestHandler.perform(vnRequests)
            }catch let error as NSError {
                print("Error in performing Image request: \(error)")
            }
        }
        
    }
    
    var vnTextDetectionRequest : VNDetectTextRectanglesRequest{
        let request = VNDetectTextRectanglesRequest { (request,error) in
            if let error = error as NSError? {
                print("Error in detecting - \(error)")
                return
            }
            else {
                guard let observations = request.results as? [VNTextObservation]
                    else {
                        return
                }
                
                var numberOfWords = 0
                for textObservation in observations {
                    var numberOfCharacters = 0
                    for rectangleObservation in textObservation.characterBoxes! {
                        let croppedImage = self.crop(image: self.currentImage, rectangle: rectangleObservation)
                        if let croppedImage = croppedImage {
                            let processedImage = self.preProcess(image: croppedImage)
                            self.imageClassifier(image: processedImage,
                                               wordNumber: numberOfWords,
                                               characterNumber: numberOfCharacters, currentObservation: textObservation)
                            numberOfCharacters += 1
                        }
                    }
                    numberOfWords += 1
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
                    self.drawRectanglesOnObservations(observations: observations)
                })
                
            }
        }
        
        request.reportCharacterBoxes = true
        
        return request
    }
    
    
    
    //COREML
    func imageClassifier(image: UIImage, wordNumber: Int, characterNumber: Int, currentObservation : VNTextObservation){
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation],
                let topResult = results.first else {
                    fatalError("Unexpected result type from VNCoreMLRequest")
            }
            let result = topResult.identifier
            let classificationInfo: [String: Any] = ["wordNumber" : wordNumber,
                                                     "characterNumber" : characterNumber,
                                                     "class" : result]
            self?.handleResult(classificationInfo, currentObservation: currentObservation)
        }
        guard let ciImage = CIImage(image: image) else {
            fatalError("Could not convert UIImage to CIImage :(")
        }
        let handler = VNImageRequestHandler(ciImage: ciImage)
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([request])
            }
            catch {
                print(error)
            }
        }
    }
    
    func handleResult(_ result: [String: Any], currentObservation : VNTextObservation) {
        objc_sync_enter(self)
        guard let wordNumber = result["wordNumber"] as? Int else {
            return
        }
        guard let characterNumber = result["characterNumber"] as? Int else {
            return
        }
        guard let characterClass = result["class"] as? String else {
            return
        }
        if (textMetadata[wordNumber] == nil) {
            let tmp: [Int: String] = [characterNumber: characterClass]
            textMetadata[wordNumber] = tmp
        } else {
            var tmp = textMetadata[wordNumber]!
            tmp[characterNumber] = characterClass
            textMetadata[wordNumber] = tmp
        }
        objc_sync_exit(self)
        DispatchQueue.main.async {
            self.doTextDetection(currentObservation: currentObservation)
        }
    }
    
    func doTextDetection(currentObservation : VNTextObservation) {
        var result: String = ""
        if (textMetadata.isEmpty) {
            print("The image does not contain any text.")
            return
        }
        let sortedKeys = textMetadata.keys.sorted()
        for sortedKey in sortedKeys {
            result +=  word(fromDictionary: textMetadata[sortedKey]!) + " "
            
        }
        
        observationStringLookup[currentObservation] = result
        
    }
    
    func word(fromDictionary dictionary: [Int : String]) -> String {
        let sortedKeys = dictionary.keys.sorted()
        var word: String = ""
        for sortedKey in sortedKeys {
            let char: String = dictionary[sortedKey]!
            word += char
        }
        return word
    }
    
    
    //Draw recognised texts.
    func drawRectanglesOnObservations(observations : [VNDetectedObjectObservation]){
        DispatchQueue.main.async {
            guard let image = self.imageView.image
                else{
                    print("Failure in retriving image")
                    return
            }
            let imageSize = image.size
            var imageTransform = CGAffineTransform.identity.scaledBy(x: 1, y: -1).translatedBy(x: 0, y: -imageSize.height)
            imageTransform = imageTransform.scaledBy(x: imageSize.width, y: imageSize.height)
            UIGraphicsBeginImageContextWithOptions(imageSize, true, 0)
            let graphicsContext = UIGraphicsGetCurrentContext()
            image.draw(in: CGRect(origin: .zero, size: imageSize))
            
            graphicsContext?.saveGState()
            graphicsContext?.setLineJoin(.round)
            graphicsContext?.setLineWidth(8.0)
            
            graphicsContext?.setFillColor(red: 0, green: 1, blue: 0, alpha: 0.3)
            graphicsContext?.setStrokeColor(UIColor.green.cgColor)
            
            
            
            var previousString = ""
            let elements = ["VISION","COREML"]
            
            observations.forEach { (observation) in
                
                var string = observationStringLookup[observation as! VNTextObservation] ?? ""
                let tempString = string
                string = string.replacingOccurrences(of: previousString, with: "")
                string = string.trim()
                previousString = tempString
                
                if elements.contains(where: string.contains){
                    
                    let observationBounds = observation.boundingBox.applying(imageTransform)
                    graphicsContext?.addRect(observationBounds)
                }
                
                
            }
            graphicsContext?.drawPath(using: CGPathDrawingMode.fillStroke)
            graphicsContext?.restoreGState()
            
            let drawnImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            self.imageView.image = drawnImage
            
        }
    }
    
    
    
    func resize(image: UIImage, targetSize: CGSize) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }

    func convertToGrayscale(image: UIImage) -> UIImage {
        let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let context = CGContext(data: nil,
                                width: Int(UInt(image.size.width)),
                                height: Int(UInt(image.size.height)),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)
        context?.draw(image.cgImage!,
                      in: CGRect(x: 0.0, y: 0.0, width: image.size.width, height: image.size.height))
        let imageRef: CGImage = context!.makeImage()!
        let newImage: UIImage = UIImage(cgImage: imageRef)
        return newImage
    }

    func insertInsets(image: UIImage, insetWidthDimension: CGFloat, insetHeightDimension: CGFloat)
        -> UIImage {
            let adjustedImage = adjustColors(image: image)
            let upperLeftPoint: CGPoint = CGPoint(x: 0, y: 0)
            let lowerLeftPoint: CGPoint = CGPoint(x: 0, y: adjustedImage.size.height - 1)
            let upperRightPoint: CGPoint = CGPoint(x: adjustedImage.size.width - 1, y: 0)
            let lowerRightPoint: CGPoint = CGPoint(x: adjustedImage.size.width - 1,
                                                   y: adjustedImage.size.height - 1)
            let upperLeftColor: UIColor = getPixelColor(fromImage: adjustedImage, pixel: upperLeftPoint)
            let lowerLeftColor: UIColor = getPixelColor(fromImage: adjustedImage, pixel: lowerLeftPoint)
            let upperRightColor: UIColor = getPixelColor(fromImage: adjustedImage, pixel: upperRightPoint)
            let lowerRightColor: UIColor = getPixelColor(fromImage: adjustedImage, pixel: lowerRightPoint)
            let color =
                averageColor(fromColors: [upperLeftColor, lowerLeftColor, upperRightColor, lowerRightColor])
            let insets = UIEdgeInsets(top: insetHeightDimension,
                                      left: insetWidthDimension,
                                      bottom: insetHeightDimension,
                                      right: insetWidthDimension)
            let size = CGSize(width: adjustedImage.size.width + insets.left + insets.right,
                              height: adjustedImage.size.height + insets.top + insets.bottom)
            UIGraphicsBeginImageContextWithOptions(size, false, adjustedImage.scale)
            let origin = CGPoint(x: insets.left, y: insets.top)
            adjustedImage.draw(at: origin)
            let imageWithInsets = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return convertTransparent(image: imageWithInsets!, color: color)
    }

    func averageColor(fromColors colors: [UIColor]) -> UIColor {
        var averages = [CGFloat]()
        for i in 0..<4 {
            var total: CGFloat = 0
            for j in 0..<colors.count {
                let current = colors[j]
                let value = CGFloat(current.cgColor.components![i])
                total += value
            }
            let avg = total / CGFloat(colors.count)
            averages.append(avg)
        }
        return UIColor(red: averages[0], green: averages[1], blue: averages[2], alpha: averages[3])
    }

    func adjustColors(image: UIImage) -> UIImage {
        let context = CIContext(options: nil)
        if let currentFilter = CIFilter(name: "CIColorControls") {
            let beginImage = CIImage(image: image)
            currentFilter.setValue(beginImage, forKey: kCIInputImageKey)
            currentFilter.setValue(0, forKey: kCIInputSaturationKey)
            currentFilter.setValue(1.45, forKey: kCIInputContrastKey) //previous 1.5
            if let output = currentFilter.outputImage {
                if let cgimg = context.createCGImage(output, from: output.extent) {
                    let processedImage = UIImage(cgImage: cgimg)
                    return processedImage
                }
            }
        }
        return image
    }

    func fixOrientation(image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        if let normalizedImage: UIImage = UIGraphicsGetImageFromCurrentImageContext() {
            UIGraphicsEndImageContext()
            return normalizedImage
        } else {
            return image
        }
    }

    func convertTransparent(image: UIImage, color: UIColor) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        let width = image.size.width
        let height = image.size.height
        let imageRect: CGRect = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        let ctx: CGContext = UIGraphicsGetCurrentContext()!
        let redValue = CGFloat(color.cgColor.components![0])
        let greenValue = CGFloat(color.cgColor.components![1])
        let blueValue = CGFloat(color.cgColor.components![2])
        let alphaValue = CGFloat(color.cgColor.components![3])
        ctx.setFillColor(red: redValue, green: greenValue, blue: blueValue, alpha: alphaValue)
        ctx.fill(imageRect)
        image.draw(in: imageRect)
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }

    func getPixelColor(fromImage image: UIImage, pixel: CGPoint) -> UIColor {
        let pixelData = image.cgImage!.dataProvider!.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        let pixelInfo: Int = ((Int(image.size.width) * Int(pixel.y)) + Int(pixel.x)) * 4
        let r = CGFloat(data[pixelInfo]) / CGFloat(255.0)
        let g = CGFloat(data[pixelInfo + 1]) / CGFloat(255.0)
        let b = CGFloat(data[pixelInfo + 2]) / CGFloat(255.0)
        let a = CGFloat(data[pixelInfo + 3]) / CGFloat(255.0)
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    func crop(image: UIImage, rectangle: VNRectangleObservation) -> UIImage? {
        var t: CGAffineTransform = CGAffineTransform.identity;
        t = t.scaledBy(x: image.size.width, y: -image.size.height);
        t = t.translatedBy(x: 0, y: -1 );
        let x = rectangle.boundingBox.applying(t).origin.x
        let y = rectangle.boundingBox.applying(t).origin.y
        let width = rectangle.boundingBox.applying(t).width
        let height = rectangle.boundingBox.applying(t).height
        let fromRect = CGRect(x: x, y: y, width: width, height: height)
        let drawImage = image.cgImage!.cropping(to: fromRect)
        if let drawImage = drawImage {
            let uiImage = UIImage(cgImage: drawImage)
            return uiImage
        }
        return nil
    }

    func preProcess(image: UIImage) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let addToHeight2 = height / 2
        let addToWidth2 = ((6 * height) / 3 - width) / 2
        let imageWithInsets = insertInsets(image: image,
                                           insetWidthDimension: addToWidth2,
                                           insetHeightDimension: addToHeight2)
        let size = CGSize(width: 28, height: 28)
        let resizedImage = resize(image: imageWithInsets, targetSize: size)
        let grayScaleImage = convertToGrayscale(image: resizedImage)
        return grayScaleImage
    }

}


