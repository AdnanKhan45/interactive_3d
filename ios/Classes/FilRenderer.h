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

NS_ASSUME_NONNULL_BEGIN

// Objective-C class for PatchColor
@interface PatchColor : NSObject
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) NSData *colorData; // Stores float[4]
- (instancetype)initWithName:(NSString *)name color:(const float *)color;
- (void)getColor:(float *)color; // Retrieves float[4]
@end

@interface FILRenderer : UIView

@property(nonatomic, strong) NSDictionary<NSString *, id> *creationParams;

typedef struct {
    uint32_t id; // Changed to uint32_t to match Entity::getId()
    NSString *name;
} SelectedEntity;

@property(nonatomic, copy) void (^selectionCallback)(NSArray<NSValue *> *selectedEntities);

- (void)loadModel:(NSData *)modelBytes
        modelName:(NSString *)modelName
        resources:(NSDictionary<NSString *, NSData *> *)resources
        preselectedEntities:(nullable NSArray<NSString *> *)preselectedEntities
        selectionColor:(nullable NSArray<NSNumber *> *)selectionColor
        patchColors:(nullable NSArray<PatchColor *> *)patchColors;

- (void)loadEnvironment:(NSData *)iblBytes skyboxBytes:(NSData *)skyboxBytes;
- (void)setCameraZoomLevel:(float)zoom;
- (void)render;
- (void)destroyModel;

@end

NS_ASSUME_NONNULL_END
