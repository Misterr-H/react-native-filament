import React, { useCallback, useEffect } from 'react'
import { useSharedValue } from 'react-native-worklets-core'
import { Button, SafeAreaView, StyleSheet, View } from 'react-native'
import {
  DynamicResolutionOptions,
  Entity,
  FilamentView,
  FilamentProvider,
  Float3,
  Material,
  runOnWorklet,
  useBuffer,
  useFilamentContext,
  withCleanupScope,
} from 'react-native-filament'
import { useDefaultLight } from './hooks/useDefaultLight'
import { Config } from './config'
import { getAssetPath } from './utils/getAssetPasth'

const cameraPosition: Float3 = [0, 3, 10]
const cameraTarget: Float3 = [0, 0, 0]
const cameraUp: Float3 = [0, 1, 0]

function Renderer() {
  const { engine, camera, view, renderableManager, scene, transformManager } = useFilamentContext()
  useDefaultLight()

  const prevAspectRatio = useSharedValue(0)
  const renderCallback = useCallback(() => {
    'worklet'

    const aspectRatio = view.getAspectRatio()
    if (prevAspectRatio.value !== aspectRatio) {
      prevAspectRatio.value = aspectRatio
      // Setup camera lens:
      const { focalLengthInMillimeters, near, far } = Config.camera
      camera.setLensProjection(focalLengthInMillimeters, aspectRatio, near, far)
      console.log('Updated camera lens!')
    }

    camera.lookAt(cameraPosition, cameraTarget, cameraUp)
  }, [camera, prevAspectRatio, view])

  // TODO: check if we can replace material
  const materialBuffer = useBuffer({ source: getAssetPath('baked_color.filamat') })
  useEffect(() => {
    'worklet'

    if (materialBuffer == null) return

    let entity: Entity | undefined
    let localMaterial: Material | undefined
    runOnWorklet(() => {
      'worklet'

      // create the material
      // const material = engine.createMaterial(materialBuffer)

      const debugEntity = renderableManager.createDebugCubeWireframe([1.5, 1, 3], undefined, undefined)
      scene.addEntity(debugEntity)
      return [debugEntity, undefined] as const
    })().then(([e, material]) => {
      entity = e
      localMaterial = material
    })

    return () => {
      if (entity == null) return
      scene.removeEntity(entity)
      withCleanupScope(() => {
        if (localMaterial != null) {
          localMaterial.release()
        }
      })()
    }
  }, [engine, materialBuffer, renderableManager, scene, transformManager])

  return (
    <SafeAreaView style={styles.container}>
      <FilamentView style={styles.filamentView} enableTransparentRendering={false} renderCallback={renderCallback} />
    </SafeAreaView>
  )
}

// Dynamic Resolution can greatly improve the performance on lower end android devices.
// It will downscale the resolution (thus reducing the load on the GPU) when the frame rate drops
// below the target frame rate (currently hard coded to 60 FPS).
const dynamicResolutionOptions: DynamicResolutionOptions = {
  enabled: true,
}

export function WorkletExample() {
  const [showView, setShowView] = React.useState(true)

  return (
    <View style={styles.container}>
      {showView ? (
        <FilamentProvider>
          <Renderer />
        </FilamentProvider>
      ) : (
        <View style={styles.container} />
      )}
      <Button
        title="Toggle view"
        onPress={() => {
          setInterval(() => {
            setShowView((prev) => !prev)
          }, 195)
        }}
      />
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  filamentView: {
    flex: 1,
    // backgroundColor: 'black',
  },
})