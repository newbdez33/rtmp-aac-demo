//
//  ViewController.m
//  rtmp-aac
//
//  Created by JackyZ on 20/1/2016.
//  Copyright © 2016 Salmonapps. All rights reserved.
//

#import "ViewController.h"
#import "KFRecorder.h"


@interface ViewController () <AVCaptureAudioDataOutputSampleBufferDelegate> {
    KFRecorder * recorder;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    recorder = [KFRecorder recorderWithName:@"test"];

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [recorder.session startRunning];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    //
}

- (IBAction)startAction:(UIButton *)sender {
    
    [recorder startRecording];
    
    sender.enabled = NO;
}

- (IBAction)stopAction:(UIButton *)sender {
    sender.enabled = NO;
}

@end
