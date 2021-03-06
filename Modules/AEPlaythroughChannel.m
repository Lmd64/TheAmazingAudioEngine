//
//  AEPlaythroughChannel.m
//  TheAmazingAudioEngine
//
//  Created by Michael Tyson on 21/04/2012.
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "AEPlaythroughChannel.h"
#import "TPCircularBuffer.h"
#import "TPCircularBuffer+AudioBufferList.h"
#import "AEAudioController+AudiobusStub.h"

static const int kAudioBufferLength = 16384;

@interface AEPlaythroughChannel () {
    TPCircularBuffer _buffer;
    UInt32           _bufferMaxLatencyInFrames;
}
@property (nonatomic, retain) AEAudioController *audioController;
@end

@implementation AEPlaythroughChannel
@synthesize audioController=_audioController, volume = _volume;

+(NSSet *)keyPathsForValuesAffectingAudioDescription {
    return [NSSet setWithObject:@"audioController.inputAudioDescription"];
}

- (id)initWithAudioController:(AEAudioController*)audioController {
    if ( !(self = [super init]) ) return nil;
    TPCircularBufferInit(&_buffer, kAudioBufferLength);
    self.audioController = audioController;
    _volume = 1.0;
    _bufferMaxLatencyInFrames = 0;
    return self;
}

- (void)dealloc {
    TPCircularBufferCleanup(&_buffer);
    self.audioController = nil;
    self.inputPort = nil;
    [super dealloc];
}

static void inputCallback(id                        receiver,
                          AEAudioController        *audioController,
                          void                     *source,
                          const AudioTimeStamp     *time,
                          UInt32                    frames,
                          AudioBufferList          *audio) {
    AEPlaythroughChannel *THIS = receiver;
    
    if ( THIS->_inputPort && ABInputPortIsConnected(THIS->_inputPort) ) {
        // We'll dequeue from the input port when we render
    } else {
        TPCircularBufferCopyAudioBufferList(&THIS->_buffer, audio, time, kTPCircularBufferCopyAll, NULL);
    }
}

-(AEAudioControllerAudioCallback)receiverCallback {
    return inputCallback;
}

static OSStatus renderCallback(id                        channel,
                               AEAudioController        *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    AEPlaythroughChannel *THIS = channel;
    
    if ( THIS->_inputPort && ABInputPortIsConnected(THIS->_inputPort) ) {
        ABInputPortReceiveLive(THIS->_inputPort, audio, frames, NULL);
    } else {
        while ( 1 ) {
            // Discard any buffers with an incompatible format, in the event of a format change
            AudioBufferList *nextBuffer = TPCircularBufferNextBufferList(&THIS->_buffer, NULL);
            if ( !nextBuffer ) break;
            if ( nextBuffer->mNumberBuffers == audio->mNumberBuffers ) break;
            TPCircularBufferConsumeNextBufferList(&THIS->_buffer);
        }
        
        UInt32 fillCount = TPCircularBufferPeek(&THIS->_buffer, NULL, AEAudioControllerAudioDescription(audioController));
        if ( fillCount >= frames+THIS->_bufferMaxLatencyInFrames ) {
            UInt32 skip = fillCount - frames;
            TPCircularBufferDequeueBufferListFrames(&THIS->_buffer,
                                                    &skip,
                                                    NULL,
                                                    NULL,
                                                    AEAudioControllerAudioDescription(audioController));
        }
        
        TPCircularBufferDequeueBufferListFrames(&THIS->_buffer,
                                                &frames,
                                                audio,
                                                NULL,
                                                AEAudioControllerAudioDescription(audioController));
    }
    
    return noErr;
}

-(AEAudioControllerRenderCallback)renderCallback {
    return renderCallback;
}

-(AudioStreamBasicDescription)audioDescription {
    return _audioController.inputAudioDescription;
}

@end


