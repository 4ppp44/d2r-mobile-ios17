#pragma once
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
// The production registration/lifetime table supplies address resolution.
static id<MTLBuffer> legacy_buffer_at(uint64_t address, NSUInteger *offset);
static void legacy_use_all(id encoder, MTLRenderStages stages);
@interface NvLegacyArgumentTable : NSObject
@property(nonatomic,weak) id encoder;
@property(nonatomic) MTLRenderStages stages;
- (void)attachRender:(id<MTLRenderCommandEncoder>)encoder stages:(MTLRenderStages)stages;
- (void)attachCompute:(id<MTLComputeCommandEncoder>)encoder;
- (void)setAddress:(uint64_t)address atIndex:(NSUInteger)index;
- (void)setLegacyTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index;
- (void)setLegacySampler:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index;
@end
@implementation NvLegacyArgumentTable
- (void)attachRender:(id<MTLRenderCommandEncoder>)e stages:(MTLRenderStages)s { self.encoder=e; self.stages=s; }
- (void)attachCompute:(id<MTLComputeCommandEncoder>)e { self.encoder=e;self.stages=0; }
- (void)setAddress:(uint64_t)address atIndex:(NSUInteger)i {
 NSUInteger offset=0;id<MTLBuffer> b=address?legacy_buffer_at(address,&offset):nil;
 if(address&&!b) [NSException raise:@"NvLegacyUnregisteredAddress" format:@"unregistered GPU address %#llx at binding %lu",(unsigned long long)address,(unsigned long)i];
 id e=self.encoder;if(!e)[NSException raise:@"NvLegacyMissingEncoder" format:@"binding without encoder"];
 if(self.stages){id<MTLRenderCommandEncoder> r=e;
  if(self.stages&MTLRenderStageVertex)[r setVertexBuffer:b offset:offset atIndex:i];
  if(self.stages&MTLRenderStageFragment)[r setFragmentBuffer:b offset:offset atIndex:i];
 } else [(id<MTLComputeCommandEncoder>)e setBuffer:b offset:offset atIndex:i];
 legacy_use_all(e,self.stages);
}
- (void)setLegacyTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i {
 id e=self.encoder;if(!e)[NSException raise:@"NvLegacyMissingEncoder" format:@"texture without encoder"];
 if(self.stages){id<MTLRenderCommandEncoder> r=e;
  if(self.stages&MTLRenderStageVertex)[r setVertexTexture:t atIndex:i];
  if(self.stages&MTLRenderStageFragment)[r setFragmentTexture:t atIndex:i];
 }else [(id<MTLComputeCommandEncoder>)e setTexture:t atIndex:i];
 if(t) { if(self.stages)[(id<MTLRenderCommandEncoder>)e useResource:t usage:MTLResourceUsageRead|MTLResourceUsageWrite stages:self.stages];else [(id<MTLComputeCommandEncoder>)e useResource:t usage:MTLResourceUsageRead|MTLResourceUsageWrite]; }
}
- (void)setLegacySampler:(id<MTLSamplerState>)s atIndex:(NSUInteger)i {
 id e=self.encoder;if(!e)[NSException raise:@"NvLegacyMissingEncoder" format:@"sampler without encoder"];
 if(self.stages){id<MTLRenderCommandEncoder> r=e;
  if(self.stages&MTLRenderStageVertex)[r setVertexSamplerState:s atIndex:i];
  if(self.stages&MTLRenderStageFragment)[r setFragmentSamplerState:s atIndex:i];
 }else [(id<MTLComputeCommandEncoder>)e setSamplerState:s atIndex:i];
}
@end
