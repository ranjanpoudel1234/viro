//
//  VROAudioManager.m
//  React
//
//  Created by Vik Advani on 4/20/16.
//  Copyright © 2016 Viro Media. All rights reserved.
//

#import "VROAudioManager.h"
#import "VRTScene.h"
#import "RCTConvert.h"
#import "RCTLog.h"
#import "VROUtils.h"

@interface SoundWrapper:NSObject {
  
}

- (instancetype)initSound:(std::shared_ptr<VROSoundEffect>) soundEffect;
- (std::shared_ptr<VROSoundEffect>)getSound;

@end

@implementation SoundWrapper {
  std::shared_ptr<VROSoundEffect> _soundEffect;
}

- (instancetype)initWithSound:(std::shared_ptr<VROSoundEffect>) soundEffect {
  self = [self init];
  _soundEffect = soundEffect;
  return self;
}

- (std::shared_ptr<VROSoundEffect>)getSound {
  return _soundEffect;
}
@end

// Simple class to store encapsulate url and soundData together.
@interface VROSoundTrack:NSObject {
  
}

@property (nonatomic, readwrite) NSURL *url;
@property (nonatomic, readwrite) NSData *soundData;

@end

@implementation VROSoundTrack {
  
}

-(instancetype)initWithURL:(NSURL *)url {
  self = [self init];
  if(self) {
    self.url = url;
   }
  return self;
}


@end

const int kLoopTrack = -1;
const int kPlayTrackOnce = 0;
@implementation VROAudioManager {
  __weak VRTScene  *_currentSceneView;
  //dictionary of sound effects, path to SoundEffects
  NSMutableDictionary *_cachedSounds;
  NSMutableArray *_currentlyQueuedTrack;
  NSURL *_currentTrackUrl;
  BOOL _loopingTrack;
}

RCT_EXPORT_MODULE()

- (instancetype)init
{
  self = [super init];
  _currentlyQueuedTrack = [[NSMutableArray alloc] init];
  return self;
}

-(void)setCurrentScene:(VRTScene *)sceneView {
  _currentSceneView = sceneView;
  if([_currentlyQueuedTrack count] > 0){
    VROSoundTrack *currentTrack = [_currentlyQueuedTrack objectAtIndex:0];
    // Set the track if the track is local OR if it has already been loaded
    if([currentTrack.url isFileURL] || currentTrack.soundData) {
      [_currentSceneView scene]->getBackgroundAudioPlayer().setTrack(currentTrack.soundData, _loopingTrack ? kLoopTrack: kPlayTrackOnce);
      [_currentlyQueuedTrack removeObjectAtIndex:0];
    }
  }

  [_currentSceneView scene]->getBackgroundAudioPlayer().play();
}

RCT_EXPORT_METHOD(playBackgroundAudio:(NSDictionary *)sceneTrack loop:(BOOL)isLooping) {
  
  _loopingTrack = isLooping;
  NSString *path;
  if (!(path = [RCTConvert NSString:sceneTrack[@"uri"]])) {
    RCTLogError(@"Unable to play sound with no path!");
  }
  
  NSURL *URL = [RCTConvert NSURL:path];
  // For now replace the song queue for every new request, this means if we get another play call, the
  // previous play will be invalid if the track is still downloading from the network.
  // TODO: VIRO-133 - When we add spatial audio, we'll allow multiple tracks. 
  [_currentlyQueuedTrack removeAllObjects];
  VROSoundTrack *track = [[VROSoundTrack alloc] initWithURL:URL];
  [_currentlyQueuedTrack addObject:track];

  //do async call for network urls.
  if([path hasPrefix:@"http"]) {
    downloadDataWithURL(URL, ^(NSData *data, NSError *error) {
      if(!error) {
        // Check to see if we still want to play this track when the callback finishes.
        if([_currentlyQueuedTrack count] > 0) {
          VROSoundTrack *queuedSong = [_currentlyQueuedTrack objectAtIndex:0];
          queuedSong.soundData = data;
          if(queuedSong.url == URL && _currentSceneView != nil) {
            [_currentSceneView scene]->getBackgroundAudioPlayer().setTrack(data, _loopingTrack ? kLoopTrack: kPlayTrackOnce);
            [_currentSceneView scene]->getBackgroundAudioPlayer().play();
            [_currentlyQueuedTrack removeAllObjects];
          }
        }
      }
    });
    return;
  }
  
  if(_currentSceneView != nil) {
    [_currentSceneView scene]->getBackgroundAudioPlayer().setTrack(URL, _loopingTrack ? kLoopTrack: kPlayTrackOnce);
    [_currentSceneView scene]->getBackgroundAudioPlayer().play();
    [_currentlyQueuedTrack removeAllObjects];
  }
}

RCT_EXPORT_METHOD(stopBackgroundAudio) {
  if(_currentSceneView != nil) {
    [_currentSceneView scene]->getBackgroundAudioPlayer().stop();
  }
}

RCT_EXPORT_METHOD(playSoundEffect:(NSDictionary *)soundDict) {
  if(_cachedSounds == nil) {
    _cachedSounds = [[NSMutableDictionary alloc] init];
  }
  
  NSString *path;
  if (!(path = [RCTConvert NSString:soundDict[@"uri"]])) {
    RCTLogError(@"Unable to play sound with no path!");
  }
  
  NSURL *URL = [RCTConvert NSURL:path];
  SoundWrapper *soundWrapper = [_cachedSounds objectForKey:path];
  if(soundWrapper == nil){
    if([path hasPrefix:@"http"]) {
      downloadDataWithURL(URL, ^(NSData *data, NSError *error) {
        if(!error) {
          SoundWrapper *sound = [self createAndCacheSoundEffectWithURL:URL data:data key:path];
          //play the sound (they'll be a delay as it first downloads).
          [sound getSound]->play();
        }
      });
      return;
    }else {
      soundWrapper = [self createAndCacheSoundEffectWithURL:URL data:nil key:path];
    }
  }
  
  [soundWrapper getSound]->play();
}

- (SoundWrapper *)createAndCacheSoundEffectWithURL:(NSURL *)url data:(NSData *)data key:(NSString *)key {
  std::shared_ptr<VROSoundEffect> sound;
  if(data != nil) {
    sound = std::make_shared<VROSoundEffect>(data);
  }
  else {
    sound = std::make_shared<VROSoundEffect>(url);
  }
  
  SoundWrapper *soundWrapper = [[SoundWrapper alloc] initWithSound:sound];
  [_cachedSounds setObject:soundWrapper forKey:key];
  return soundWrapper;
}

@end