//
//  MyAudioReceiver.h
//  rtmp-aac
//
//  Created by JackyZ on 21/1/2016.
//  Copyright © 2016 Salmonapps. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TheAmazingAudioEngine.h"
#import "ViewController.h"

@interface MyAudioReceiver : NSObject<AEAudioReceiver>

@property (nonatomic, strong) ViewController * vc;

@end
