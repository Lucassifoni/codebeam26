<script setup lang="ts">
import MediaGrid from './MediaGrid.vue'
import type { MediaFit } from '../utils/media.ts'

/**
 * A single photo or video filling its container, for use inside other layouts:
 * `<Media src="img_4973.mp4" fit="contain" caption="..." />`.
 */
const props = withDefaults(defineProps<{
  src: string
  fit?: MediaFit
  position?: string
  filter?: string
  caption?: string
  loop?: boolean
}>(), {
  loop: true,
})
</script>

<template>
  <MediaGrid class="te-media-single" :media="{ ...props }" />
</template>
