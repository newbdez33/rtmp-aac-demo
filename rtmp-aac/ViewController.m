//
//  ViewController.m
//  rtmp-aac
//
//  Created by JackyZ on 20/1/2016.
//  Copyright © 2016 Salmonapps. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "TheAmazingAudioEngine.h"
#import "MyAudioReceiver.h"

@interface ViewController () <AVCaptureAudioDataOutputSampleBufferDelegate> {
    
//    AEAudioController * taaeController;
    MyAudioReceiver * receiver;
    
    AudioConverterRef m_converter;
    AVCaptureSession * m_capture;
    
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
//    taaeController = [[AEAudioController alloc] initWithAudioDescription:AEAudioStreamBasicDescriptionNonInterleavedFloatStereo inputEnabled:YES];
//    taaeController.preferredBufferDuration = 0.005;
//    taaeController.useMeasurementMode = YES;
//    taaeController.automaticLatencyManagement = YES;
//    [taaeController start:nil];
//    receiver = [[MyAudioReceiver alloc] init];
//    receiver.vc = self;
//    [taaeController addInputReceiver:receiver];
    
    [self open];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)open {
    
    NSError * error;
    
    m_capture = [[AVCaptureSession alloc] init];
    AVCaptureDevice * audioDev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (audioDev == nil) {
        NSLog(@"Count'd create audio capture device");
        return;
    }
    
    
    //input
    AVCaptureDeviceInput * audioIn = [AVCaptureDeviceInput deviceInputWithDevice:audioDev error:&error];
    if (error != nil) {
        NSLog(@"Couldn't create audio input");
        return;
    }
    if ([m_capture canAddInput:audioIn] == NO) {
        NSLog(@"Couldn't add audio input");
        return;
    }
    [m_capture addInput:audioIn];
    
    //output
    AVCaptureAudioDataOutput * audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [audioOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    if ([m_capture canAddOutput:audioOutput] == NO) {
        NSLog(@"Couldn't add audio output");
        return;
    }
    [m_capture addOutput:audioOutput];
    
    [audioOutput connectionWithMediaType:AVMediaTypeAudio];
    [m_capture startRunning];
    return;
    
}

- (void)close {
    if (m_capture != nil && [m_capture isRunning]) {
        [m_capture stopRunning];
    }
    return;
}

- (BOOL)isOpen {
    if (m_capture == nil) {
        return NO;
    }
    return [m_capture isRunning];
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type fromManufacturer:(UInt32)manufacturer {
    
    static AudioClassDescription audioDesc;
    UInt32 encoderSpecifier = type, size = 0;
    OSStatus status;
    
    memset(&audioDesc, 0, sizeof(audioDesc));
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    if (status) {
        return nil;
    }
    
    uint32_t count = size / sizeof(AudioClassDescription);
    AudioClassDescription descs[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, descs);
    for (uint32_t i=0; i < count; i++) {
        if ( (type == descs[i].mSubType) && (manufacturer == descs[i].mManufacturer)) {
            memcpy(&audioDesc, &descs[i], sizeof(audioDesc));
            break;
        }
    }
    return &audioDesc;
}

- (BOOL)createAudioConvert:(CMSampleBufferRef)sampleBuffer {
    if (m_converter != nil) {
        return YES;
    }
    
    AudioStreamBasicDescription inputFormat = *(CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer))); // 输入音频格式
    AudioStreamBasicDescription outputFormat;
    
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate        =   inputFormat.mSampleRate;
    outputFormat.mFormatID          =   kAudioFormatMPEG4AAC;
    outputFormat.mChannelsPerFrame  =   inputFormat.mChannelsPerFrame;
    outputFormat.mFramesPerPacket   =   1024;   //AAC fixed
    
    
    AudioClassDescription * desc = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    if (AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, desc, &m_converter) != noErr) {
        NSLog(@"AudioConverterNewSpecific failed");
        return NO;
    }
    
    return YES;
}

OSStatus inputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    AudioBufferList bufferList = *(AudioBufferList*)inUserData;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mData           = bufferList.mBuffers[0].mData;
    ioData->mBuffers[0].mDataByteSize   = bufferList.mBuffers[0].mDataByteSize;
    return noErr;
}

NSString *NSStringFromOSStatus(OSStatus errCode)
{
    if (errCode == noErr)
        return @"noErr";
    char message[5] = {0};
    *(UInt32*) message = CFSwapInt32HostToBig(errCode);
    return [NSString stringWithCString:message encoding:NSASCIIStringEncoding];
}

- (BOOL)aac:(CMSampleBufferRef)sampleBuffer aacData:(char *) aacData aacLen:(int *)aacLen {
    
    if ([self createAudioConvert:sampleBuffer] != YES) {
        return NO;
    }
    
    CMBlockBufferRef blockBuffer = nil;
    AudioBufferList inBufferList;
    if (CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inBufferList, sizeof(inBufferList), NULL, NULL, 0, &blockBuffer)) {
        NSLog(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed");
        return NO;
    }
    
    AudioBufferList outBufferList;
    outBufferList.mNumberBuffers                =   1;
    outBufferList.mBuffers[0].mNumberChannels   =   inBufferList.mBuffers[0].mNumberChannels;
    outBufferList.mBuffers[0].mDataByteSize     =   *aacLen;
    outBufferList.mBuffers[0].mData             =   aacData;
    UInt32 outputDataPacketSize                 =   1;
    OSStatus st = AudioConverterFillComplexBuffer(m_converter, inputDataProc, &inBufferList, &outputDataPacketSize, &outBufferList, NULL);
    if (st != noErr) {
        NSLog(@"AudioConverterFillComplexBuffer failed:%@", NSStringFromOSStatus(st));
        return NO;
    }
    NSLog(@"in:%@, out:%@", @(inBufferList.mBuffers[0].mDataByteSize), @(outBufferList.mBuffers[0].mDataByteSize));
    *aacLen = outBufferList.mBuffers[0].mDataByteSize;
    CFRelease(blockBuffer);
    return YES;
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    //NSLog(@"sam:%@", sampleBuffer);
    char szBuf[4096];
    int nSize = sizeof(szBuf);
    if ([self aac:sampleBuffer aacData:szBuf aacLen:&nSize] == YES) {
        NSLog(@"OK:%@", @(nSize));
    }else {
        NSLog(@"Failed!");
    }
}

@end
