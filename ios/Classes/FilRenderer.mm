#import "FILRenderer.h"
#include <image/Ktx1Bundle.h>
#include <ktxreader/Ktx1Reader.h>
#include <filament/MaterialInstance.h>
#include <filament/IndirectLight.h>
#include <filament/Skybox.h>
#include <math/vec4.h>

using namespace filament;
using namespace utils;
using namespace filament::gltfio;
using namespace image;

@implementation PatchColor

- (instancetype)initWithName:(NSString *)name color:(const float *)color {
    self = [super init];
    if (self) {
        _name = [name copy];
        _colorData = [NSData dataWithBytes:color length:4 * sizeof(float)];
    }
    return self;
}

- (void)getColor:(float *)color {
    if (_colorData.length == 4 * sizeof(float)) {
        [self.colorData getBytes:color length:4 * sizeof(float)];
    } else {
        // Default to white if data is invalid
        color[0] = 1.0f; color[1] = 1.0f; color[2] = 1.0f; color[3] = 1.0f;
    }
}

@end

@interface FILRenderer () {
    Engine* _engine;
    Renderer* _renderer;
    Scene* _scene;
    View* _view;
    Camera* _camera;
    Entity _cameraEntity; // Store camera entity for destruction
    SwapChain* _swapChain;
    filament::gltfio::AssetLoader* _assetLoader;
    filament::gltfio::ResourceLoader* _resourceLoader;
    FilamentAsset* _asset;
    NameComponentManager* _nameManager;
    NSMutableArray<NSValue *>* _selectedEntities;
    NSArray<NSNumber *>* _selectionColor;
    NSArray<PatchColor *>* _patchColors;
    NSArray<NSString *>* _preselectedEntities;
    CADisplayLink* _displayLink;
    MaterialProvider* _materialProvider;
    TextureProvider* _stbDecoder;
    TextureProvider* _ktxDecoder;
    NSTimeInterval _startTime;
    IndirectLight* _indirectLight;
    Skybox* _skybox;
    Texture* _iblTexture;
    Texture* _skyboxTexture;
    BOOL _modelLoaded;
}
@end

@implementation FILRenderer

@synthesize creationParams = _creationParams;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _selectedEntities = [NSMutableArray array];
        _modelLoaded = NO;
        [self setupFilament];
    }
    return self;
}

- (void)setupFilament {
    self.contentScaleFactor = UIScreen.mainScreen.nativeScale;

    // Initialize Filament
    _engine = Engine::create();
    _renderer = _engine->createRenderer();
    _scene = _engine->createScene();
    _view = _engine->createView();
    _view->setScene(_scene);

    // Configure Camera
    _cameraEntity = EntityManager::get().create();
    _camera = _engine->createCamera(_cameraEntity);
    _view->setCamera(_camera);
    _camera->setProjection(50.0, double(self.bounds.size.width) / self.bounds.size.height, 0.1, 100.0);
    _camera->lookAt({0, 0, 5}, {0, 0, 0}, {0, 1, 0});

    // Create SwapChain
    CAMetalLayer* metalLayer = (CAMetalLayer*)self.layer;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _swapChain = _engine->createSwapChain((__bridge void*)metalLayer);

    // Setup AssetLoader and ResourceLoader
    _assetLoader = filament::gltfio::AssetLoader::create({_engine, nullptr, nullptr});

    // Setup NameComponentManager for entity names
    _nameManager = new NameComponentManager(EntityManager::get());

    // Setup render loop
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    // Setup tap gesture (placeholder, as picking is not implemented)
    UITapGestureRecognizer* tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tapRecognizer.numberOfTapsRequired = 1;
    [self addGestureRecognizer:tapRecognizer];

    // Configure view options
    View::DynamicResolutionOptions dynOptions = {};
    dynOptions.enabled = true;
    dynOptions.quality = View::QualityLevel::MEDIUM;
    _view->setDynamicResolutionOptions(dynOptions);

    View::MultiSampleAntiAliasingOptions msaaOptions = {};
    msaaOptions.enabled = true;
    _view->setMultiSampleAntiAliasingOptions(msaaOptions);

    View::AmbientOcclusionOptions aoOptions = {};
    aoOptions.enabled = true;
    _view->setAmbientOcclusionOptions(aoOptions);

    View::BloomOptions bloomOptions = {};
    bloomOptions.enabled = true;
    _view->setBloomOptions(bloomOptions);

    _view->setAntiAliasing(View::AntiAliasing::FXAA);

    NSLog(@"Filament initialized successfully");
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        CGPoint location = [recognizer locationInView:self];
        NSLog(@"Tap at (%f, %f) - Picking not implemented", location.x, location.y);
        // TODO: Implement picking if needed
    }
}

- (void)loadModel:(NSData *)modelBytes
        modelName:(NSString *)modelName
        resources:(NSDictionary<NSString *, NSData *> *)resources
        preselectedEntities:(nullable NSArray<NSString *> *)preselectedEntities
        selectionColor:(nullable NSArray<NSNumber *> *)selectionColor
        patchColors:(nullable NSArray<PatchColor *> *)patchColors {
    NSLog(@"Loading model: %@, bytes: %lu", modelName, (unsigned long)modelBytes.length);
    [self destroyModel];

    _selectionColor = selectionColor;
    _patchColors = patchColors;
    _preselectedEntities = preselectedEntities;

    _asset = _assetLoader->createAsset((const uint8_t*)modelBytes.bytes, (uint32_t)modelBytes.length);
    if (!_asset) {
        NSLog(@"Failed to load model: %@", modelName);
        return;
    }

    if ([modelName.lowercaseString hasSuffix:@".gltf"]) {
        for (NSString *uri in resources.allKeys) {
            NSData *resourceData = resources[uri];
            _resourceLoader->addResourceData([uri UTF8String], {resourceData.bytes, resourceData.length});
        }
        _resourceLoader->loadResources(_asset);
    }

    // Add asset entities to the scene
    const Entity* entities = _asset->getEntities();
    size_t entityCount = _asset->getEntityCount();
    for (size_t i = 0; i < entityCount; i++) {
        Entity entity = entities[i];
        _scene->addEntity(entity);
        if (_nameManager && [modelName.lowercaseString hasSuffix:@".gltf"]) {
            const char* name = _asset->getName(entity);
            if (name) {
                _nameManager->addComponent(entity);
                _nameManager->setName(_nameManager->getInstance(entity), name);
            }
        }
    }

    // Auto-scale model
    Aabb bounds = _asset->getBoundingBox();
    math::float3 boundsMin = bounds.min;
    math::float3 boundsMax = bounds.max;
    float maxExtent = std::max({boundsMax.x - boundsMin.x, boundsMax.y - boundsMin.y, boundsMax.z - boundsMin.z});
    if (maxExtent > 0) {
        float scale = 2.0f / maxExtent;
        math::mat4f transform = math::mat4f::scaling(scale);
        Entity root = _asset->getRoot();
        if (root) {
            TransformManager& tm = _engine->getTransformManager();
            auto instance = tm.getInstance(root);
            tm.setTransform(instance, transform);
        }
    }

    // Apply preselected entities
    if (_preselectedEntities) {
        for (NSString *name in _preselectedEntities) {
            const Entity* entities = _asset->getEntities();
            size_t count = _asset->getEntityCount();
            for (size_t i = 0; i < count; i++) {
                Entity entity = entities[i];
                NSString *entityName = [self getEntityName:entity];
                if ([name isEqualToString:entityName]) {
                    float color[4] = {0.0f, 1.0f, 0.0f, 1.0f};
                    if (_selectionColor && _selectionColor.count == 4) {
                        for (int i = 0; i < 4; i++) {
                            color[i] = [_selectionColor[i] floatValue];
                        }
                    }
                    for (PatchColor *patch in _patchColors) {
                        if ([patch.name isEqualToString:entityName]) {
                            [patch getColor:color];
                            break;
                        }
                    }
                    [self setRenderableColor:entity r:color[0] g:color[1] b:color[2] a:color[3]];
                    [self addSelectedEntity:entity name:entityName];
                }
            }
        }
        [self notifySelectionChanged];
    }

    _modelLoaded = YES;
    NSLog(@"Loaded model: %@", modelName);
}

- (void)loadEnvironment:(NSData *)iblBytes skyboxBytes:(NSData *)skyboxBytes {
    if (_indirectLight) _engine->destroy(_indirectLight);
    if (_skybox) _engine->destroy(_skybox);

    if (iblBytes) {
        Ktx1Bundle iblKtx((const uint8_t*)[iblBytes bytes], (uint32_t)iblBytes.length);
        if (iblKtx.getNumMipLevels() > 0) {
            _iblTexture = ktxreader::Ktx1Reader::createTexture(_engine, &iblKtx, false);
            if (_iblTexture) {
                _indirectLight = IndirectLight::Builder()
                        .reflections(_iblTexture)
                        .intensity(50000.0f)
                        .build(*_engine);
                _scene->setIndirectLight(_indirectLight);
            } else {
                NSLog(@"Failed to create texture from IBL KTX file");
            }
        } else {
            NSLog(@"Failed to parse IBL KTX file");
        }
    } else {
        NSLog(@"Failed to load IBL KTX file");
    }

    if (skyboxBytes) {
        Ktx1Bundle skyboxKtx((const uint8_t*)[skyboxBytes bytes], (uint32_t)skyboxBytes.length);
        if (skyboxKtx.getNumMipLevels() > 0) {
            _skyboxTexture = ktxreader::Ktx1Reader::createTexture(_engine, &skyboxKtx, false);
            if (_skyboxTexture) {
                _skybox = Skybox::Builder()
                        .environment(_skyboxTexture)
                        .build(*_engine);
                _scene->setSkybox(_skybox);
            } else {
                NSLog(@"Failed to create texture from Skybox KTX file");
            }
        } else {
            NSLog(@"Failed to parse Skybox KTX file");
        }
    } else {
        NSLog(@"Failed to load Skybox KTX file");
    }

    _scene->setIndirectLight(_indirectLight);
    _scene->setSkybox(_skybox);
}


- (void)setCameraZoomLevel:(float)zoom {
    if (!_modelLoaded) return;

    double aspect = double(self.bounds.size.width) / double(self.bounds.size.height);
    double defaultFov = 50.0;
    double newFov = defaultFov / zoom;

    _camera->setProjection(newFov, aspect, 0.1, 100.0, Camera::Fov::VERTICAL);
    NSLog(@"Camera zoom set: zoom = %f, newFov = %f", zoom, newFov);
}

- (void)render {
    if (_renderer->beginFrame(_swapChain)) {
        _renderer->render(_view);
        _renderer->endFrame();
    }
}

- (void)destroyModel {
    if (_modelLoaded) {
        if (_asset) {
            _assetLoader->destroyAsset(_asset);
            _asset = nullptr;
        }
        [_selectedEntities removeAllObjects];
        _modelLoaded = NO;
    }
}

- (void)dealloc {
    [self destroyModel];
    [_displayLink invalidate];
    if (_assetLoader) {
        _assetLoader->destroy(&_assetLoader);
    }
    if (_resourceLoader) {
        delete _resourceLoader;
    }
    if (_nameManager) {
        delete _nameManager;
    }
    if (_engine) {
        _engine->destroy(_swapChain);
        _engine->destroy(_view);
        _engine->destroy(_renderer);
        _engine->destroy(_scene);
        if (_cameraEntity) {
            EntityManager::get().destroy(_cameraEntity);
        }
        Engine::destroy(&_engine);
    }
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (NSString *)getEntityName:(Entity)entity {
    if (_nameManager->hasComponent(entity)) {
        auto instance = _nameManager->getInstance(entity);
        const char* name = _nameManager->getName(instance);
        return name ? @(name) : @"Unnamed Entity";
    }
    return @"Unnamed Entity";
}

- (BOOL)isEntitySelected:(Entity)entity {
    for (NSValue *value in _selectedEntities) {
        SelectedEntity selected;
        [value getValue:&selected];
        if (selected.id == entity.getId()) {
            return YES;
        }
    }
    return NO;
}

- (void)addSelectedEntity:(Entity)entity name:(NSString *)name {
    SelectedEntity selected = {entity.getId(), name};
    NSValue *value = [NSValue valueWithBytes:&selected objCType:@encode(SelectedEntity)];
    [_selectedEntities addObject:value];
}

- (void)removeSelectedEntity:(Entity)entity {
    for (NSValue *value in _selectedEntities.copy) {
        SelectedEntity selected;
        [value getValue:&selected];
        if (selected.id == entity.getId()) {
            [_selectedEntities removeObject:value];
        }
    }
}

- (void)notifySelectionChanged {
    if (self.selectionCallback) {
        self.selectionCallback(_selectedEntities);
    }
}

- (void)setRenderableColor:(Entity)entity r:(float)r g:(float)g b:(float)b a:(float)a {
    RenderableManager& rcm = _engine->getRenderableManager();
    if (!rcm.hasComponent(entity)) return;

    auto ri = rcm.getInstance(entity);
    size_t count = rcm.getPrimitiveCount(ri);
    for (size_t i = 0; i < count; i++) {
        MaterialInstance* materialInst = rcm.getMaterialInstanceAt(ri, i);
        if (materialInst) {
            materialInst->setParameter("baseColorFactor", filament::math::float4{r, g, b, a});
        }
    }
}

- (void)resetRenderableColor:(Entity)entity {
    RenderableManager& rcm = _engine->getRenderableManager();
    if (!rcm.hasComponent(entity)) return;

    auto ri = rcm.getInstance(entity);
    size_t count = rcm.getPrimitiveCount(ri);
    for (size_t i = 0; i < count; i++) {
        MaterialInstance* materialInst = rcm.getMaterialInstanceAt(ri, i);
        if (materialInst) {
            materialInst->setParameter("baseColorFactor", filament::math::float4{1.0f, 1.0f, 1.0f, 1.0f});
        }
    }
}

@end
