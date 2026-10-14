<script setup lang="ts">
import MediaGrid from '../components/MediaGrid.vue'
import type { MediaFit, MediaInput } from '../utils/media.ts'

/**
 * Full-bleed photo/video slide driven by frontmatter:
 *
 *   layout: media
 *   split: 1/3 2/3
 *   media: [img_5233.webp, img_4973.mp4]
 *
 * Markdown content, when present, is shown above the grid and the slide
 * gets its regular padding back.
 */
withDefaults(defineProps<{
  media?: MediaInput | MediaInput[]
  split?: string | number[]
  fit?: MediaFit
  position?: string
  filter?: string
  gap?: string
  loop?: boolean
}>(), {
  loop: true,
})
</script>

<template>
  <div class="slidev-layout media te-media">
    <div class="te-media__content">
      <slot />
    </div>
    <MediaGrid
      class="te-media__grid"
      :media="media"
      :split="split"
      :fit="fit"
      :position="position"
      :filter="filter"
      :gap="gap"
      :loop="loop"
    />
  </div>
</template>
