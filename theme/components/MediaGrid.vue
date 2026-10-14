<script setup lang="ts">
import { computed, watchEffect } from 'vue'
import { gridColumns, normalizeMedia, parseSplit } from '../utils/media.ts'
import type { MediaFit, MediaInput } from '../utils/media.ts'

/**
 * Photos and videos laid out in columns.
 *
 * `media` is a file name (resolved against the shared `media/` directory),
 * an object `{ src, fit, position, filter, caption, loop }`, or a list of both.
 * `filter` is a CSS `filter` value applied to every item unless overridden.
 * `split` sets column widths (`"1/3 2/3"`); without it, items share one row
 * equally. Extra items wrap onto new rows following the split.
 * Videos play muted while their slide is active, and pause otherwise. They loop
 * unless `loop` is `false`, in which case they stop on their last frame, which
 * is also the frame used in exports.
 */
const props = withDefaults(defineProps<{
  media?: MediaInput | MediaInput[]
  split?: string | number[]
  fit?: MediaFit
  position?: string
  filter?: string
  gap?: string
  loop?: boolean
}>(), {
  fit: 'cover',
  position: 'center',
  loop: true,
})

const items = computed(() => normalizeMedia(props.media, {
  base: import.meta.env.BASE_URL,
  fit: props.fit,
  position: props.position,
  filter: props.filter,
  loop: props.loop,
}))

const weights = computed(() => parseSplit(props.split))

watchEffect(() => {
  if (props.split != null && weights.value === null)
    console.warn(`[MediaGrid] invalid split "${props.split}", using equal columns`)
})

const style = computed(() => ({
  gridTemplateColumns: gridColumns(weights.value, items.value.length),
  ...(props.gap ? { '--te-media-gap': props.gap } : {}),
}))
</script>

<template>
  <div class="te-media-grid" :style="style">
    <figure v-for="(item, i) in items" :key="`${i}:${item.src}`" class="te-media-grid__cell">
      <SlidevVideo
        v-if="item.kind === 'video'"
        class="te-media-grid__media"
        :src="item.src"
        :style="{ objectFit: item.fit, objectPosition: item.position, filter: item.filter }"
        autoplay
        autoreset="slide"
        muted
        :loop="item.loop"
        :print-timestamp="item.loop ? undefined : 'last'"
        playsinline
        preload="auto"
      />
      <img
        v-else
        class="te-media-grid__media"
        :src="item.src"
        :alt="item.caption ?? ''"
        :style="{ objectFit: item.fit, objectPosition: item.position, filter: item.filter }"
        draggable="false"
      >
      <figcaption v-if="item.caption" class="te-media-grid__caption">
        {{ item.caption }}
      </figcaption>
    </figure>
  </div>
</template>
