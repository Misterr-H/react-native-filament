//
// Created by Hanno Gödecke on 20.03.24.
//

#pragma once

#include "FilamentAssetWrapper.h"
#include "FilamentBuffer.h"
#include "MaterialInstanceWrapper.h"
#include "MaterialWrapper.h"
#include "core/utils/EntityWrapper.h"
#include "jsi/PointerHolder.h"

#include <filament/RenderableManager.h>
#include <gltfio/TextureProvider.h>

namespace margelo {
using namespace filament;
using namespace gltfio;

class EngineWrapper;

class RenderableManagerImpl {
public:
  explicit RenderableManagerImpl(std::shared_ptr<Engine> engine, std::shared_ptr<Dispatcher> rendererDispatcher)
      : _engine(engine), _rendererDispatcher(rendererDispatcher) {
    _textureProvider = std::shared_ptr<TextureProvider>(filament::gltfio::createStbProvider(_engine.get()));
  }

public: // Public API
  int getPrimitiveCount(std::shared_ptr<EntityWrapper> entity);
  std::shared_ptr<MaterialInstanceWrapper> getMaterialInstanceAt(std::shared_ptr<EntityWrapper> entity, int index);
  void setMaterialInstanceAt(std::shared_ptr<EntityWrapper> entity, int index, std::shared_ptr<MaterialInstanceWrapper> materialInstance);

  /**
   * Convenience method to apply the given opacity to every material of all the asset's entities.
   * Prefer to use this method over `getMaterialInstanceAt` and `setOpacity` for performance reasons.
   */
  void setAssetEntitiesOpacity(std::shared_ptr<FilamentAssetWrapper> asset, double opacity);

  void setInstanceWrapperEntitiesOpacity(std::shared_ptr<FilamentInstanceWrapper> instanceWrapper, double opacity);

  void setInstanceEntitiesOpacity(FilamentInstance* instance, double opacity);

  /**
   * Will select the first material instance from the entity. Will set the baseColorMap parameter to the given textureBuffer.
   */
  void changeMaterialTextureMap(std::shared_ptr<EntityWrapper> entityWrapper, const std::string& materialName,
                                std::shared_ptr<FilamentBuffer> textureBuffer, const std::string& textureFlags = "none");

  void setCastShadow(std::shared_ptr<EntityWrapper> entityWrapper, bool castShadow);

  void setReceiveShadow(std::shared_ptr<EntityWrapper> entityWrapper, bool receiveShadow);

  std::shared_ptr<EntityWrapper> createPlane(std::shared_ptr<MaterialWrapper> materialWrapper, double halfExtendX, double halfExtendY,
                                             double halfExtendZ);

  /**
   * Takes an asset, gets the bounding box of all renderable entities and updates the bounding box to be multiplied by the given scale
   * factor.
   */
  void scaleBoundingBox(std::shared_ptr<FilamentAssetWrapper> assetWrapper, double scaleFactor);

private:
  // Calls the TextureProvider to start loading the resource
  void startUpdateResourceLoading();

private:
  std::shared_ptr<Engine> _engine;
  std::shared_ptr<Dispatcher> _rendererDispatcher;
  std::shared_ptr<TextureProvider> _textureProvider;
  // Keep a list of all material instances the RenderableManager creates, so we can clean them up when the RenderableManager is
  std::vector<std::shared_ptr<MaterialInstance>> _materialInstances;

private:
  constexpr static const char* TAG = "RenderableManagerImpl";
};

} // namespace margelo