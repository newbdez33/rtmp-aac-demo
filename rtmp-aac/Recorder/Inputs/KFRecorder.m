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

#include <librtmp/rtmp.h>
#include <librtmp/amf.h>
#include <librtmp/log.h>
#import "libRTMPClient.h"

NSString *const NotifNewAssetGroupCreated = @"NotifNewAssetGroupCreated";

@interface KFRecorder() {
    libRTMPClient *rtmp;
}

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

void send_pkt(RTMP* pRtmp,char* buf, int buflen, int type, unsigned int timestamp)
{
    int ret;
    RTMPPacket rtmp_pakt;
    RTMPPacket_Reset(&rtmp_pakt);
    RTMPPacket_Alloc(&rtmp_pakt, buflen);
    rtmp_pakt.m_packetType = type;
    rtmp_pakt.m_nBodySize = buflen;
    rtmp_pakt.m_nTimeStamp = timestamp;
    rtmp_pakt.m_nChannel = 4;
    rtmp_pakt.m_headerType = RTMP_PACKET_SIZE_LARGE;
    rtmp_pakt.m_nInfoField2 = pRtmp->m_stream_id;
    memcpy(rtmp_pakt.m_body, buf, buflen);
    ret = RTMP_SendPacket(pRtmp, &rtmp_pakt, 0);
    RTMPPacket_Free(&rtmp_pakt);
}

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
    static double p = 0;

    //CMTime scaledTime = CMTimeSubtract(frame.pts, self.originalSample);
    //NSLog(@"raw aac data:%@", frame.data, frame.pts.value);
        //[self.hlsWriter processEncodedData:frame.data presentationTimestamp:scaledTime streamIndex:1 isKeyFrame:NO];
//    if (frame.data != nil) {
        //1024*1000000/44100= 22.32ms
        NSLog(@"p:%@", @(CMTimeGetSeconds(frame.pts)));
        [rtmp writeAACDataToStream:frame.data time:p+=(CMTimeGetSeconds(frame.pts)/1000)];
//    }else {
//        
//    }

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

- (void)startRecording:(NSString *)url
{
    //rtmp://52.76.198.49:1935/live/jacky
//    BOOL ret = [_rtmp openWithURL:@"http://192.168.31.199:1935/live/jacky" enableWrite:YES];
    rtmp = [[libRTMPClient alloc] init];
    [rtmp connect:url];
    
    
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
    
    [rtmp disconnect];

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