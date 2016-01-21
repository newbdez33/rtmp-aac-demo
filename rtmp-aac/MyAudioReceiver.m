//
//  MyAudioReceiver.m
//  rtmp-aac
//
//  Created by JackyZ on 21/1/2016.
//  Copyright © 2016 Salmonapps. All rights reserved.
//

#import "MyAudioReceiver.h"

@implementation MyAudioReceiver

- (id)init {
    self = [super init];
    if (self) {
        //
    }
    return self;
}

static void audioCallback(__unsafe_unretained MyAudioReceiver *THIS,
                          __unsafe_unretained AEAudioController *audioController,
                          void                     *source,
                          const AudioTimeStamp     *time,
                          UInt32                    frames,
                          AudioBufferList          *audio) {
    NSLog(@"a:%@", @(audio->mBuffers[0].mDataByteSize));
    
}

- (AEAudioReceiverCallback)receiverCallback {
    return audioCallback;
}


@end
