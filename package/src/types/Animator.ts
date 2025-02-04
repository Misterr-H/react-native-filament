import { FilamentInstance } from './FilamentInstance'

/**
 * Updates matrices according to glTF animation and skin definitions.
 *
 * Animator can be used for two things:
 * - Updating matrices in filament::TransformManager components according to glTF animation definitions.
 * - Updating bone matrices in filament::RenderableManager components according to glTF skin definitions.
 *
 * For a usage example, see the documentation for AssetLoader.
 */
export interface Animator {
  /**
   * Applies rotation, translation, and scale to entities that have been targeted by the given
   * animation definition. Uses filament::TransformManager.
   *
   * @param animationIndex Zero-based index for the animation of interest.
   * @param time Elapsed time of interest in seconds.
   */
  applyAnimation(animIndex: number, time: number): void

  /**
   * Applies a blended transform to the union of nodes affected by two animations.
   * Used for cross-fading from a previous skinning-based animation or rigid body animation.
   *
   * First, this stashes the current transform hierarchy into a transient memory buffer.
   *
   * Next, this applies previousAnimIndex / previousAnimTime to the actual asset by internally
   * calling applyAnimation().
   *
   * Finally, the stashed local transforms are lerped (via the scale / translation / rotation
   * components) with their live counterparts, and the results are pushed to the asset.
   *
   * To achieve a cross fade effect with skinned models, clients will typically call animator
   * methods in this order: (1) applyAnimation (2) applyCrossFade (3) updateBoneMatrices. The
   * animation that clients pass to applyAnimation is the "current" animation corresponding to
   * alpha=1, while the "previous" animation passed to applyCrossFade corresponds to alpha=0.
   */
  applyCrossFade(previousAnimIndex: number, previousAnimTime: number, alpha: number): void

  /**
   * Computes root-to-node transforms for all bone nodes, then passes
   * the results into filament::RenderableManager::setBones.
   * Uses filament::TransformManager and filament::RenderableManager.
   *
   * NOTE: this operation is independent of animation.
   */
  updateBoneMatrices(): void

  /**
   * Will apply all transforms of the animation to the same entities/bones when calling {@linkcode updateBoneMatrices}.
   * This is useful if you have multiple assets sharing the same skeleton and you want to animate them in sync (e.g. clothing).
   * Internally calls {@linkcode applyAnimationToInstance}.
   *
   * @note Entities / bones are identified by name.
   *
   * @returns The id of the instance in the sync list.
   */
  addToSyncList(instance: FilamentInstance): number

  /**
   * Will remove the instance from the sync list.
   */
  removeFromSyncList(instanceId: number): void

  /**
   * Pass the identity matrix into all bone nodes, useful for returning to the T pose.
   *
   * NOTE: this operation is independent of animation.
   */
  resetBoneMatrices(): void

  /** Returns the number of animation definitions in the glTF asset. */
  getAnimationCount(): number

  /** Returns the number of animation definitions in the asset. */
  getAnimationDuration(animIndex: number): number

  /**
   * Returns the name of the specified animation, or an
   * empty string if none was specified.
   */
  getAnimationName(animIndex: number): string
}
