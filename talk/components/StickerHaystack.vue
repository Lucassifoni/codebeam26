<script setup lang="ts">
import Haystack from '../../../theme/components/Haystack.vue'

/**
 * Every sticker of `media/stickers/` piled over a black slide.
 * The directory is listed at build time, so new stickers are picked up
 * without touching the deck. Props are forwarded to `Haystack`.
 */
const stickers = Object.keys(import.meta.glob('../../../media/stickers/*.png'))
  .map(path => `stickers/${path.slice(path.lastIndexOf('/') + 1)}`)
  .sort()
</script>

<template>
  <Haystack :items="stickers" />
</template>
