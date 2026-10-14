<script setup lang="ts">
import { computed, ref, useTemplateRef, watch } from 'vue'
import { useIsSlideActive } from '@slidev/client'
import { haystackLayout, haystackStep } from '../utils/haystack.ts'
import { resolveMediaSrc } from '../utils/media.ts'

/**
 * Images piled over a full-slide backdrop at seeded random positions and
 * rotations, each with a slight shadow. Later items land on top.
 *
 * `items` are file names resolved against the shared `media/` directory.
 * `width` is the CSS width of one item, `maxRotation` the rotation bound in
 * degrees, `seed` selects the arrangement and `background` the backdrop.
 * `duration` is the time in seconds over which the pile builds up each time
 * the slide is shown, each item popping in place; `0` shows the full pile at once.
 * The build-up waits for every image to be loaded and decoded, so an item never
 * shows its shadow ahead of its picture.
 */
const props = withDefaults(defineProps<{
  items?: string[]
  width?: string
  maxRotation?: number
  seed?: string
  background?: string
  duration?: number
}>(), {
  items: () => [],
  width: '360px',
  maxRotation: 45,
  seed: 'haystack',
  background: '#000',
  duration: 8,
})

const isActive = useIsSlideActive()
const images = useTemplateRef<HTMLImageElement[]>('images')
const ready = ref(false)

const placements = computed(() => haystackLayout(props.items.length, {
  seed: props.seed,
  maxRotation: props.maxRotation,
}))

const step = computed(() => haystackStep(props.items.length, props.duration))

const pile = computed(() => props.items.map((item, i) => ({
  src: resolveMediaSrc(item, import.meta.env.BASE_URL),
  style: {
    'left': `${placements.value[i].x * 100}%`,
    'top': `${placements.value[i].y * 100}%`,
    'rotate': `${placements.value[i].rotation}deg`,
    '--te-haystack-index': i,
  },
})))

const staggered = computed(() => isActive.value && step.value > 0)

watch(staggered, async (active) => {
  ready.value = false
  if (!active)
    return
  await Promise.allSettled((images.value ?? []).map(image => image.decode()))
  ready.value = staggered.value
}, { immediate: true, flush: 'post' })
</script>

<template>
  <div
    class="te-haystack"
    :class="{ 'te-haystack--pending': staggered && !ready, 'te-haystack--animate': staggered && ready }"
    :style="{ 'background': background, '--te-haystack-width': width, '--te-haystack-step': `${step}ms` }"
  >
    <img
      v-for="(item, i) in pile"
      ref="images"
      :key="`${i}:${item.src}`"
      class="te-haystack__item"
      :src="item.src"
      :style="item.style"
      alt=""
      decoding="sync"
      draggable="false"
    >
  </div>
</template>
