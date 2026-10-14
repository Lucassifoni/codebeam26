<script setup lang="ts">
import Loco from '../components/Loco.vue'

/**
 * Title slide: the first `h1` is followed by the locomotive ribbon,
 * the rest of the slide content flows below it.
 * The `ribbon` frontmatter key seeds the bit sequence.
 */
defineProps<{
  ribbon?: string
}>()
</script>

<template>
  <div class="slidev-layout cover te-cover">
    <slot />
    <Loco class="te-cover__loco" :text="ribbon" />
  </div>
</template>
