//
//  AppleFilamentRecorder.cpp
//  react-native-filament
//
//  Created by Marc Rousavy on 02.05.24.
//

#include "RNFAppleFilamentRecorder.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VTCompressionProperties.h>
#include <memory>
#include <mutex>

namespace margelo {

static int kCVPixelBufferLock_Write = 0;

AppleFilamentRecorder::AppleFilamentRecorder(std::shared_ptr<Dispatcher> renderThreadDispatcher, int width, int height, int fps,
                                             double bitRate)
    : FilamentRecorder(renderThreadDispatcher, width, height, fps, bitRate) {
  dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, -1);
  _queue = dispatch_queue_create("filament.recorder.queue", qos);

  Logger::log(TAG, "Creating CVPixelBuffer target texture...");
  NSDictionary* pixelBufferAttributes = @{
    (NSString*)kCVPixelBufferWidthKey : @(width),
    (NSString*)kCVPixelBufferHeightKey : @(height),
    (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (NSString*)kCVPixelBufferMetalCompatibilityKey : @(YES)
  };
  CVReturn result =
      CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)pixelBufferAttributes, &_pixelBuffer);
  if (result != kCVReturnSuccess) {
    throw std::runtime_error("Failed to create input texture CVPixelBuffer!");
  }

  Logger::log(TAG, "Creating temporary file...");
  NSString* tempDirectory = NSTemporaryDirectory();
  NSString* filename = [NSString stringWithFormat:@"%@.mp4", [[NSUUID UUID] UUIDString]];
  NSString* filePath = [tempDirectory stringByAppendingPathComponent:filename];
  _path = [NSURL fileURLWithPath:filePath];
  Logger::log(TAG, "Recording to " + std::string(filePath.UTF8String) + "...");

  Logger::log(TAG, "Creating AVAssetWriter...");
  NSError* error;
  _assetWriter = [AVAssetWriter assetWriterWithURL:_path fileType:AVFileTypeMPEG4 error:&error];
  if (error != nil) {
    std::string path = _path.absoluteString.UTF8String;
    std::string domain = error.domain.UTF8String;
    std::string code = std::to_string(error.code);
    throw std::runtime_error("Failed to create AVAssetWriter at " + path + ", error: " + domain + " (Code: " + code + ")");
  }
  _assetWriter.shouldOptimizeForNetworkUse = NO;

  Logger::log(TAG, "Creating AVAssetWriterInput...");
  AVVideoCodecType codec = AVVideoCodecTypeH264;
  NSString* profile = AVVideoProfileLevelH264HighAutoLevel;
  NSDictionary* outputSettings = @{
    AVVideoCodecKey : codec,
    AVVideoCompressionPropertiesKey : @{
      AVVideoExpectedSourceFrameRateKey : @(fps),
      AVVideoMaxKeyFrameIntervalKey : @(fps),
      AVVideoAverageBitRateKey : @(bitRate),
      AVVideoProfileLevelKey : profile
    },
    AVVideoWidthKey : @(width),
    AVVideoHeightKey : @(height)
  };
  _assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
  _assetWriterInput.expectsMediaDataInRealTime = NO;
  _assetWriterInput.performsMultiPassEncodingIfSupported = YES;
  if (![_assetWriter canAddInput:_assetWriterInput]) {
    std::string settingsJson = outputSettings.description.UTF8String;
    throw std::runtime_error("Failed to add AVAssetWriterInput to AVAssetWriter! Settings used: " + settingsJson);
  }

  Logger::log(TAG, "Adding AVAssetWriterInput...");
  [_assetWriter addInput:_assetWriterInput];

  Logger::log(TAG, "Creating AVAssetWriterInputPixelBufferAdaptor...");
  _pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_assetWriterInput
                                                                                         sourcePixelBufferAttributes:pixelBufferAttributes];
}

bool AppleFilamentRecorder::getSupportsHEVC() {
  // TODO: Remove this once we confirmed that H.264 works
  return false;
  NSArray<NSString*>* availablePresets = AVAssetExportSession.allExportPresets;
  for (NSString* preset in availablePresets) {
    if (preset == AVAssetExportPresetHEVCHighestQuality) {
      return true;
    }
  }
  return false;
}

void AppleFilamentRecorder::renderFrame(double timestamp) {
  std::unique_lock lock(_mutex);

  Logger::log(TAG, "Rendering Frame with timestamp %f...", timestamp);
  if (!_assetWriterInput.isReadyForMoreMediaData) {
    // This should never happen because we only poll Frames from the AVAssetWriter.
    // Once it's ready, renderFrame will be called. But better safe than sorry.
    throw std::runtime_error("AVAssetWriterInput was not ready for more data!");
  }

  CVPixelBufferPoolRef pool = _pixelBufferAdaptor.pixelBufferPool;
  if (pool == nil) {
    // The pool should always be created once startSession has been called. So in theory that also shouldn't happen.
    throw std::runtime_error("AVAssetWriterInputPixelBufferAdaptor's pixel buffer pool was nil! Cannot write Frame.");
  }

  // 1. Get (or create) a pixel buffer from the cache pool
  CVPixelBufferRef targetBuffer;
  CVReturn result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &targetBuffer);
  if (result != kCVReturnSuccess || targetBuffer == nil) {
    throw std::runtime_error("Failed to get a new CVPixelBuffer from the CVPixelBufferPool!");
  }

  // 2. Lock both pixel buffers for CPU access
  result = CVPixelBufferLockBaseAddress(_pixelBuffer, kCVPixelBufferLock_ReadOnly);
  if (result != kCVReturnSuccess) {
    throw std::runtime_error("Failed to lock input buffer for read access!");
  }
  result = CVPixelBufferLockBaseAddress(targetBuffer, /* write flag */ 0);
  if (result != kCVReturnSuccess) {
    throw std::runtime_error("Failed to lock target buffer for write access!");
  }

  // 3. Copy over Frame data
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(_pixelBuffer);
  size_t height = CVPixelBufferGetHeight(_pixelBuffer);
  void* destination = CVPixelBufferGetBaseAddress(targetBuffer);
  void* source = CVPixelBufferGetBaseAddress(_pixelBuffer);
  memcpy(destination, source, bytesPerRow * height);

  // 4. Unlock pixel buffers again
  CVPixelBufferUnlockBaseAddress(targetBuffer, kCVPixelBufferLock_Write);
  CVPixelBufferUnlockBaseAddress(_pixelBuffer, kCVPixelBufferLock_ReadOnly);

  // 5. Append the new copy of the buffer to the pool
  CMTime time = CMTimeMake(_frameCount++, getFps());
  BOOL success = [_pixelBufferAdaptor appendPixelBuffer:targetBuffer withPresentationTime:time];
  if (!success || _assetWriter.status != AVAssetWriterStatusWriting) {
    std::string errorMessage = "Unknown error (status " + std::to_string(_assetWriter.status) + ")";
    NSError* error = _assetWriter.error;
    if (error != nil) {
      errorMessage = getErrorMessage(error);
    }
    throw std::runtime_error("Failed to append buffer to AVAssetWriter! " + errorMessage);
  }

  // 6. Release the pixel buffer
  CFRelease(targetBuffer);
}

void* AppleFilamentRecorder::getNativeWindow() {
  return static_cast<void*>(_pixelBuffer);
}

std::string AppleFilamentRecorder::getOutputFile() {
  NSString* path = _path.absoluteString;
  std::string stringPath = path.UTF8String;
  return stringPath;
}

std::string AppleFilamentRecorder::getErrorMessage(NSError* error) {
  NSString* string = [NSString stringWithFormat:@"%@ (%zu): %@", error.domain, error.code, error.userInfo.description];
  return std::string(string.UTF8String);
}

std::future<void> AppleFilamentRecorder::startRecording() {
  std::unique_lock lock(_mutex);

  Logger::log(TAG, "Starting recording...");
  auto self = shared<AppleFilamentRecorder>();
  return std::async(std::launch::async, [self]() {
    [self->_assetWriter startWriting];
    [self->_assetWriter startSessionAtSourceTime:kCMTimeZero];
    NSError* maybeError = self->_assetWriter.error;
    if (maybeError != nil) {
      std::string errorMessage = getErrorMessage(maybeError);
      throw std::runtime_error("Failed to start recording! Error: " + errorMessage);
    }
    Logger::log(TAG, "Recording started! Starting Media Data listener...");

    self->_isRecording = true;
    auto weakSelf = std::weak_ptr(self);
    [self->_assetWriterInput requestMediaDataWhenReadyOnQueue:self->_queue
                                                   usingBlock:[weakSelf]() {
                                                     Logger::log(TAG, "Recorder is ready for more data.");
                                                     auto self = weakSelf.lock();
                                                     if (self != nullptr) {
                                                       auto futurePromise =
                                                           self->_renderThreadDispatcher->runAsyncAwaitable<void>([self]() {
                                                             while ([self->_assetWriterInput isReadyForMoreMediaData]) {
                                                               // This will cause our JS render callbacks to be called, which will call
                                                               // renderFrame renderFrame will call appendPixelBuffer, and we should call
                                                               // appendPixelBuffer as long as isReadyForMoreMediaData is true.
                                                               bool shouldContinueNext = self->onReadyForMoreData();
                                                               if (!shouldContinueNext) {
                                                                 // stop the render queue
                                                                 [self->_assetWriterInput markAsFinished];
                                                               }
                                                             }
                                                           });
                                                       // The block in requestMediaDataWhenReadyOnQueue needs to call appendPixelBuffer
                                                       // synchronously
                                                       futurePromise.get();
                                                     }
                                                   }];
  });
}

std::future<std::string> AppleFilamentRecorder::stopRecording() {
  std::unique_lock lock(_mutex);

  Logger::log(TAG, "Stopping recording...");

  if (!_isRecording) {
    throw std::runtime_error("Cannot call stopRecording() when isRecording is false!");
  }
  if (_assetWriter.status != AVAssetWriterStatusWriting) {
    throw std::runtime_error("Cannot call stopRecording() when AssetWriter status is " + std::to_string(_assetWriter.status) + "!");
  }

  auto promise = std::make_shared<std::promise<std::string>>();
  auto self = shared<AppleFilamentRecorder>();
  dispatch_async(_queue, [self, promise]() {
    // Finish and wait for callback
    [self->_assetWriter finishWritingWithCompletionHandler:[self, promise]() {
      Logger::log(TAG, "Recording finished!");
      AVAssetWriterStatus status = self->_assetWriter.status;
      NSError* maybeError = self->_assetWriter.error;
      if (status != AVAssetWriterStatusCompleted || maybeError != nil) {
        Logger::log(TAG, "Recording finished with error; %zu", static_cast<int>(status));
        std::string statusString = std::to_string(static_cast<int>(status));
        std::string errorMessage = getErrorMessage(maybeError);
        auto error = std::runtime_error("AVAssetWriter didn't finish properly, status: " + statusString + ", error: " + errorMessage);
        auto exceptionPtr = std::make_exception_ptr(error);
        promise->set_exception(exceptionPtr);
        return;
      }

      Logger::log(TAG, "Recording finished successfully!");
      std::string path = self->getOutputFile();
      promise->set_value(path);
    }];

    self->_isRecording = false;
  });

  return promise->get_future();
}

} // namespace margelo
