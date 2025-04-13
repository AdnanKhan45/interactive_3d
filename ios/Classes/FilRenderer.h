
#import <UIKit/UIKit.h>

#import <Foundation/Foundation.h>

#include <filament/Camera.h>
#include <filament/Color.h>
#include <filament/Engine.h>
#include <filament/IndirectLight.h>
#include <filament/LightManager.h>
#include <filament/RenderableManager.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/Skybox.h>
#include <filament/TransformManager.h>
#include <filament/View.h>
#include <filament/Viewport.h>

#include <gltfio/AssetLoader.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <gltfio/materials/uberarchive.h>

#include <utils/EntityManager.h>
#include <utils/NameComponentManager.h>

#include <camutils/Manipulator.h>

@interface FILRenderer : UIView

// Filament Core Components
@property(nonatomic, readonly) filament::Engine* engine;
@property(nonatomic, readonly) filament::Scene* scene;
@property(nonatomic, readonly) filament::View* view;
@property(nonatomic, readonly) filament::Renderer* renderer;

// Model and Environment Components
- (void)loadModelGlb:(NSData*)buffer;
- (void)loadModelGltf:(NSData*)buffer callback:(NSData* (^)(NSString*))callback;
- (void)loadEnvironment:(NSData*)iblData skybox:(NSData*)skyboxData;
- (void)render;

// Cleanup
- (void)destroyModel;

@end
