//
//  KFRecorder.m
//  FFmpegEncoder
//
//  Created by Christopher Ballinger on 1/16/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import "KFRecorder.h"
#import "KFAACEncoder.h"
#import "KFFrame.h"
#import "Endian.h"

#import "Utilities.h"

NSString *const NotifNewAssetGroupCreated = @"NotifNewAssetGroupCreated";

@interface KFRecorder()

@property (nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property (nonatomic, strong) dispatch_queue_t audioQueue;
@property (nonatomic, strong) AVCaptureConnection *audioConnection;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *folderName;
@property (nonatomic) CMTime originalSample;
@property (nonatomic) CMTime latestSample;
@property (nonatomic) double currentSegmentDuration;
@property (nonatomic) NSDate *lastFragmentDate;

@end

@implementation KFRecorder

+ (instancetype)recorderWithName:(NSString *)name
{
    KFRecorder *recorder = [KFRecorder new];
    recorder.name = name;
    return recorder;
}

- (instancetype)init
{
    self = [super init];
    if (!self) return nil;

    [self setupSession];
    [self setupEncoders];

    return self;
}

- (AVCaptureDevice *)audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0)
    {
        return [devices objectAtIndex:0];
    }

    return nil;
}

- (void)setupEncoders
{
    self.audioSampleRate = 44100;
    int audioBitrate = 64 * 1024; // 64 Kbps

    self.aacEncoder = [[KFAACEncoder alloc] initWithBitrate:audioBitrate sampleRate:self.audioSampleRate channels:1];
    self.aacEncoder.delegate = self;
    self.aacEncoder.addADTSHeader = YES;
}

- (void)setupAudioCapture
{
    // create capture device with video input

    /*
     * Create audio connection
     */
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    AVCaptureDeviceInput *audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:&error];
    if (error)
    {
        NSLog(@"Error getting audio input device: %@", error.description);
    }
    if ([self.session canAddInput:audioInput])
    {
        [self.session addInput:audioInput];
    }

    self.audioQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioOutput setSampleBufferDelegate:self queue:self.audioQueue];
    if ([self.session canAddOutput:self.audioOutput])
    {
        [self.session addOutput:self.audioOutput];
    }
    self.audioConnection = [self.audioOutput connectionWithMediaType:AVMediaTypeAudio];
}

#pragma mark KFEncoderDelegate method
- (void)encoder:(KFEncoder *)encoder encodedFrame:(KFFrame *)frame
{

    CMTime scaledTime = CMTimeSubtract(frame.pts, self.originalSample);
    NSLog(@"data:%@", frame.data);
        //[self.hlsWriter processEncodedData:frame.data presentationTimestamp:scaledTime streamIndex:1 isKeyFrame:NO];
}

#pragma mark AVCaptureOutputDelegate method
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (!self.isRecording) return;
    [self.aacEncoder encodeSampleBuffer:sampleBuffer];

}

- (double)durationRecorded
{
    if (self.isRecording)
    {
        return self.currentSegmentDuration + [[NSDate date] timeIntervalSinceDate:self.lastFragmentDate];
    }
    else
    {
        return self.currentSegmentDuration;
    }
}

- (void)setupSession
{
    self.session = [[AVCaptureSession alloc] init];
    [self setupAudioCapture];

}

- (void)startRecording
{
    self.lastFragmentDate = [NSDate date];
    self.currentSegmentDuration = 0;
    self.originalSample = CMTimeMakeWithSeconds(0, 0);
    self.latestSample = CMTimeMakeWithSeconds(0, 0);

    self.isRecording = YES;
    if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidStartRecording:error:)])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate recorderDidStartRecording:self error:nil];
        });
    }

}

- (void)stopRecording
{
    self.isRecording = NO;

    dispatch_async(self.audioQueue, ^{ // put this on video queue so we don't accidentially write a frame while closing.
        NSError *error = nil;
        //[self.hlsWriter finishWriting:&error];
        if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidFinishRecording:error:)])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate recorderDidFinishRecording:self error:error];
            });
        }
    });
}

@end