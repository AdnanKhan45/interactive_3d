#import "FILRenderer.h"

#include <image/Ktx1Bundle.h>
#include <ktxreader/Ktx1Reader.h>

using namespace filament;
using namespace utils;
using namespace filament::gltfio;
using namespace ktxreader;


@interface FILRenderer ()
@property(nonatomic) filament::SwapChain* swapChain;
@property(nonatomic) filament::Camera* camera;
@property(nonatomic) filament::gltfio::AssetLoader* assetLoader;
@property(nonatomic) filament::gltfio::ResourceLoader* resourceLoader;
@property(nonatomic) filament::gltfio::FilamentAsset* asset;
@property(nonatomic) filament::IndirectLight* indirectLight;
@end

@implementation FILRenderer

  MaterialProvider* _materialProvider;
  TextureProvider* _stbDecoder;
  TextureProvider* _ktxDecoder;
  NSTimeInterval _startTime;
  IndirectLight* _indirectLight;
  Skybox* _skybox;
  Texture* _iblTexture;
  Texture* _skyboxTexture;

  struct {
     Entity camera;
  } _entities;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupFilament];
    }
    return self;
}

- (void)setupFilament {
    self.contentScaleFactor = UIScreen.mainScreen.nativeScale;

    // Create Filament Engine and Core Components
    _engine = Engine::create();
    _renderer = _engine->createRenderer();
    _scene = _engine->createScene();
    _view = _engine->createView();
    _camera = _engine->createCamera(_entities.camera);
    _view->setScene(_scene);
    _view->setCamera(_camera);

    // Create SwapChain for rendering
    CAMetalLayer* metalLayer = (CAMetalLayer*)self.layer;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _swapChain = _engine->createSwapChain((__bridge void*)metalLayer);
    

    // Setup Asset Loader
    _assetLoader = AssetLoader::create({_engine, nullptr, nullptr});
    _resourceLoader = new ResourceLoader({.engine = _engine});
}

- (void)loadModelGlb:(NSData*)buffer {
    [self destroyModel];

    _asset = _assetLoader->createAsset(
            static_cast<const uint8_t*>(buffer.bytes), static_cast<uint32_t>(buffer.length));
    if (!_asset) return;

    _scene->addEntities(_asset->getEntities(), _asset->getEntityCount());
    _resourceLoader->loadResources(_asset);
    _asset->releaseSourceData();
}

- (void)loadModelGltf:(NSData*)buffer callback:(NSData* (^)(NSString*))callback {
    [self destroyModel];

    _asset = _assetLoader->createAsset(
            static_cast<const uint8_t*>(buffer.bytes), static_cast<uint32_t>(buffer.length));
    if (!_asset) return;

    for (size_t i = 0; i < _asset->getResourceUriCount(); i++) {
        NSString* uri = [NSString stringWithUTF8String:_asset->getResourceUris()[i]];
        NSData* resourceData = callback(uri);
        filament::gltfio::ResourceLoader::BufferDescriptor bufferDesc(
            resourceData.bytes, resourceData.length, nullptr);

        _resourceLoader->addResourceData(uri.UTF8String, std::move(bufferDesc));


    }

    _scene->addEntities(_asset->getEntities(), _asset->getEntityCount());
    _resourceLoader->loadResources(_asset);
    _asset->releaseSourceData();
}

- (void)loadEnvironment:(NSData*)iblData skybox:(NSData*)skyboxData {
    if (_indirectLight) _engine->destroy(_indirectLight);
    if (_skybox) _engine->destroy(_skybox);

    if (iblData) {
        Ktx1Bundle iblKtx((const uint8_t*)[iblData bytes], (uint32_t)iblData.length);
        if (iblKtx.getNumMipLevels() > 0) {
            _iblTexture = Ktx1Reader::createTexture(_engine, &iblKtx, false);
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
    
    
    if (skyboxData) {
        Ktx1Bundle skyboxKtx((const uint8_t*)[skyboxData bytes], (uint32_t)skyboxData.length);
        if (skyboxKtx.getNumMipLevels() > 0) {
            _skyboxTexture = Ktx1Reader::createTexture(_engine, &skyboxKtx, false);
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

- (void)render {
    if (_renderer->beginFrame(_swapChain)) {
        _renderer->render(_view);
        _renderer->endFrame();
    }
}

- (void)destroyModel {
    if (_asset) {
        _scene->removeEntities(_asset->getEntities(), _asset->getEntityCount());
        _assetLoader->destroyAsset(_asset);
        _asset = nullptr;
    }
}

- (void)dealloc {
    [self destroyModel];

    if (_indirectLight) _engine->destroy(_indirectLight);
    if (_skybox) _engine->destroy(_skybox);
    _engine->destroy(_swapChain);
    _engine->destroy(_view);
    _engine->destroy(_renderer);
    _engine->destroyCameraComponent(_entities.camera);
    _engine->destroy(_scene);
    delete _resourceLoader;
    AssetLoader::destroy(&_assetLoader);
    Engine::destroy(&_engine);
}

+ (Class)layerClass {
    return [CAMetalLayer class];
}

@end
