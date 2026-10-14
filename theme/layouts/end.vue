<script setup lang="ts">
import Loco from '../components/Loco.vue'

/**
 * Closing slide: content above the locomotive ribbon.
 */
defineProps<{
  ribbon?: string
}>()
</script>

<template>
  <div class="slidev-layout end te-end">
    <div class="te-end__content">
      <slot />
    </div>
    <Loco class="te-end__loco" :text="ribbon" />
  </div>
</template>
